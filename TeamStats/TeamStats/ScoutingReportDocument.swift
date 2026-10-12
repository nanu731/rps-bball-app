import Foundation
import PDFKit
import Darwin

// Local input preparation only; this never establishes a stored or approved report.
nonisolated struct ScoutingReportDocument: Sendable {
    static let maximumBytes = 5 * 1_024 * 1_024
    let bytes: Data
    let pageCount: Int

    static func read(_ url: URL) throws -> ScoutingReportDocument {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ScoutingReportDocumentError.unreadable }
        // Keep the read bounded, and never follow a final symlink or block on a special file.
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw ScoutingReportDocumentError.unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0 else { throw ScoutingReportDocumentError.unreadable }
        guard before.st_size <= maximumBytes else { throw ScoutingReportDocumentError.tooLarge }
        var bytes = Data()
        do {
            while bytes.count <= maximumBytes {
                try Task.checkCancellation()
                let remaining = maximumBytes + 1 - bytes.count
                guard let chunk = try handle.read(upToCount: min(65_536, remaining)),
                      !chunk.isEmpty else { break }
                bytes.append(chunk)
                guard bytes.count <= maximumBytes else { throw ScoutingReportDocumentError.tooLarge }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScoutingReportDocumentError {
            throw error
        } catch {
            throw ScoutingReportDocumentError.unreadable
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, after.st_size == before.st_size,
              bytes.count == before.st_size else { throw ScoutingReportDocumentError.unreadable }
        try Task.checkCancellation()
        guard let document = PDFDocument(data: bytes) else {
            throw ScoutingReportDocumentError.unreadable
        }
        guard !document.isEncrypted else { throw ScoutingReportDocumentError.encrypted }
        guard document.pageCount > 0 else { throw ScoutingReportDocumentError.unreadable }
        try Task.checkCancellation()
        return ScoutingReportDocument(bytes: bytes, pageCount: document.pageCount)
    }
}

nonisolated enum ScoutingReportDocumentError: LocalizedError, Equatable {
    case unreadable, tooLarge, encrypted

    var errorDescription: String? {
        switch self {
        case .unreadable: "The report could not be read. Choose another PDF. The original is unchanged."
        case .tooLarge: "Choose a PDF of 5 MiB or less. The original is unchanged."
        case .encrypted: "Choose a PDF without password encryption. TeamStats does not request report passwords. The original is unchanged."
        }
    }
}
