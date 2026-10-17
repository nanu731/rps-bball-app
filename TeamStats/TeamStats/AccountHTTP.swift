import Foundation

/// Auth transport policy, separate from the SDK's refresh/session coordination.
nonisolated enum AccountHTTP {
    enum Failure: Error { case unavailable, tooLarge, invalidResponse }

    static func session(resourceTimeout: TimeInterval = 30) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(15, resourceTimeout)
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    static func send(_ request: URLRequest, session: URLSession,
                     budget: Duration = .seconds(30), maximum: Int = 1024 * 1024,
                     jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) async throws -> (Data, URLResponse) {
        let diagnostic = OperationDiagnostics.shared.begin(.authentication, attempts: 0)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        // Only this identity read is replay-safe. File GETs reserve transfer allowance.
        let safeRead = request.httpMethod == "GET" && request.url?.path == "/auth/v1/user"
        do {
            let result = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask {
                    for attempt in 0..<(safeRead ? 3 : 1) {
                        try Task.checkCancellation()
                        diagnostic.attempt()
                        var delay: Double?
                        do {
                            let result = try await read(request, session: session, maximum: maximum)
                            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                            let transient = [408, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 530].contains(status)
                            if !safeRead {
                                // Auth's SDK interceptor otherwise retries these POST responses.
                                if transient { throw Failure.unavailable }
                                return result
                            }
                            if !transient { return result }
                            guard attempt < 2 else { throw Failure.unavailable }
                            let retry = (result.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                            let serverDate = (result.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date").flatMap(httpDate)
                            delay = retryDelay(retry, now: serverDate ?? Date())
                        } catch let error as URLError {
                            guard safeRead, attempt < 2,
                                  [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code) else { throw error }
                        }
                        let backoff = pow(2, Double(attempt)) * max(0, min(1, jitter()))
                        let wait = max(delay ?? 0, backoff)
                        guard wait.isFinite, clock.now.advanced(by: .seconds(wait)) < deadline else { throw Failure.unavailable }
                        try await clock.sleep(for: .seconds(wait))
                    }
                    throw Failure.unavailable
                }
                group.addTask {
                    try await clock.sleep(until: deadline)
                    throw Failure.unavailable
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw Failure.unavailable }
                try Task.checkCancellation()
                return result
            }
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            let failure: DiagnosticFailure = [401, 403, 404].contains(status) ? .denied : status >= 500 ? .unavailable : .invalid
            diagnostic.finish((200..<300).contains(status) ? .succeeded : .failed,
                              failure: (200..<300).contains(status) ? .none : failure)
            return result
        } catch is CancellationError {
            diagnostic.finish(safeRead ? .cancelled : .unconfirmed, failure: .cancelled)
            throw CancellationError()
        }
        catch {
            if Task.isCancelled {
                diagnostic.finish(safeRead ? .cancelled : .unconfirmed, failure: .cancelled)
                throw CancellationError()
            }
            diagnostic.finish(safeRead ? .failed : .unconfirmed, failure: .unavailable)
            // Do not let the SDK retry POSTs or multiply this transport's read budget.
            // Confirmed HTTP denials were returned intact above for Auth's own cleanup.
            throw error as? Failure ?? Failure.unavailable
        }
    }

    static func retryDelay(_ value: String?, now: Date) -> Double? {
        guard let raw = value else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            // Even an unrepresentably large valid delay must never become an early retry.
            return Double(value) ?? .infinity
        }
        return httpDate(value).map { max(0, $0.timeIntervalSince(now)) }
    }

    private static func httpDate(_ value: String) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return format.date(from: value)
    }

    private static func read(_ original: URLRequest, session: URLSession, maximum: Int) async throws -> (Data, URLResponse) {
        var request = original
        request.timeoutInterval = min(request.timeoutInterval, 15)
        let (stream, response) = try await session.bytes(for: request, delegate: RedirectBlocker())
        defer { stream.task.cancel() }
        guard let response = response as? HTTPURLResponse, !(300..<400).contains(response.statusCode) else { throw Failure.invalidResponse }
        guard response.expectedContentLength <= maximum else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < maximum else { throw Failure.tooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}

nonisolated private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
