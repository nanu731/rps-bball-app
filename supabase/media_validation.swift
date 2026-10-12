import Foundation
import PDFKit
import CoreGraphics
import AVFoundation
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin

// Trusted local worker: the gateway must supervise this process group (including
// renderer children), enforce wall60s/CPU45s/RSS512MiB, and discard raw stderr.
// Resource exhaustion is a failed validation, never an upload receipt.

struct ValidationRequest: Decodable { let path: String; let kind: String }
struct ValidationReply: Encodable {
    let valid: Bool
    let media_type: String?
    let byte_count: Int?
    let sha256: String?
    let details: [String: Int]
    let failure_reason: String?
}
enum ValidationFailure: String, Error { case invalid_request, unreadable, size_limit, unsupported_type, invalid_pdf, encrypted_pdf, active_pdf, resource_limit, validator_unavailable, invalid_video, unsupported_codec, duration_limit, dimensions_limit }

func readFile(_ path: String, maximum: Int) throws -> Data {
    let fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw ValidationFailure.unreadable }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close() }
    var before = stat()
    guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size > 0 else { throw ValidationFailure.unreadable }
    guard before.st_size <= maximum else { throw ValidationFailure.size_limit }
    var bytes = Data()
    while bytes.count <= maximum {
        guard let chunk = try file.read(upToCount: min(65_536, maximum + 1 - bytes.count)), !chunk.isEmpty else { break }
        bytes.append(chunk)
        guard bytes.count <= maximum else { throw ValidationFailure.size_limit }
    }
    var after = stat()
    guard fstat(fd, &after) == 0, after.st_size == before.st_size,
        before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
        before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
        bytes.count == before.st_size else { throw ValidationFailure.unreadable }
    return bytes
}

// Reachable PDF objects are inspected independently of what happens to render.
// Interactive actions/attachments are outside the scouting-document contract.
final class PDFGraph {
    var failure: ValidationFailure?
    var visited: Set<UInt> = []
    var objectCount = 0
    var depth = 0
    let forbidden: Set<String> = ["A", "AA", "OpenAction", "JS", "JavaScript", "EmbeddedFiles", "EF", "XFA", "AcroForm", "RichMedia", "Movie", "Sound"]
    func dictionary(_ value: CGPDFDictionaryRef) {
        guard depth <= 100 else { failure = .resource_limit; return }
        guard visited.insert(UInt(bitPattern: value.rawValue)).inserted else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGPDFDictionaryApplyFunction(value, { key, object, context in
            guard let context else { return }
            let graph = Unmanaged<PDFGraph>.fromOpaque(context).takeUnretainedValue()
            guard graph.failure == nil else { return }
            if graph.forbidden.contains(String(cString: key)) { graph.failure = .active_pdf; return }
            graph.object(object)
        }, context)
    }
    func object(_ object: CGPDFObjectRef) {
        guard failure == nil else { return }
        depth += 1
        defer { depth -= 1 }
        guard depth <= 100 else { failure = .resource_limit; return }
        objectCount += 1
        guard objectCount <= 100_000 else { failure = .resource_limit; return }
        switch CGPDFObjectGetType(object) {
        case .dictionary:
            var value: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(object, .dictionary, &value), let value { dictionary(value) }
            else { failure = .invalid_pdf }
        case .array:
            var value: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &value), let value else { failure = .invalid_pdf; return }
            guard visited.insert(UInt(bitPattern: value.rawValue)).inserted else { return }
            guard CGPDFArrayGetCount(value) <= 100_000 else { failure = .resource_limit; return }
            for index in 0..<CGPDFArrayGetCount(value) {
                var child: CGPDFObjectRef?
                guard CGPDFArrayGetObject(value, index, &child), let child else { failure = .invalid_pdf; return }
                self.object(child)
                if failure != nil { return }
            }
        case .stream:
            var value: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &value), let value else { failure = .invalid_pdf; return }
            guard visited.insert(UInt(bitPattern: value.rawValue)).inserted else { return }
            guard let dictionary = CGPDFStreamGetDictionary(value) else { failure = .invalid_pdf; return }
            self.dictionary(dictionary)
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(value, &format) else { failure = .invalid_pdf; return }
            if CFDataGetLength(data) > 64 * 1024 * 1024 { failure = .resource_limit }
        default: break
        }
    }
}

func trustedRenderer() throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let path = environment["TEAMSTATS_PDF_RENDERER"], path.hasPrefix("/"),
        let expected = environment["TEAMSTATS_PDF_RENDERER_SHA256"], expected.count == 64 else { throw ValidationFailure.validator_unavailable }
    let bytes: Data
    do { bytes = try readFile(path, maximum: 32 * 1024 * 1024) } catch { throw ValidationFailure.validator_unavailable }
    guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == expected else { throw ValidationFailure.validator_unavailable }
    return URL(fileURLWithPath: path)
}

func privateFile(_ bytes: Data, suffix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("teamstats-validation-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let url = directory.appendingPathComponent("payload." + suffix)
    try bytes.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return url
}

func validatePDF(_ bytes: Data) throws -> [String: Int] {
    guard bytes.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: bytes),
        let provider = CGDataProvider(data: bytes as CFData), let cg = CGPDFDocument(provider) else { throw ValidationFailure.invalid_pdf }
    guard !document.isEncrypted, !cg.isEncrypted else { throw ValidationFailure.encrypted_pdf }
    guard document.pageCount > 0, document.pageCount == cg.numberOfPages else { throw ValidationFailure.invalid_pdf }
    guard document.pageCount <= 500 else { throw ValidationFailure.resource_limit }
    let graph = PDFGraph()
    guard let catalog = cg.catalog else { throw ValidationFailure.invalid_pdf }
    graph.dictionary(catalog)
    if let failure = graph.failure { throw failure }
    let renderer = try trustedRenderer()
    let file = try privateFile(bytes, suffix: "pdf")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    for index in 1...cg.numberOfPages {
        guard let page = cg.page(at: index) else { throw ValidationFailure.invalid_pdf }
        let box = page.getBoxRect(.mediaBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { throw ValidationFailure.invalid_pdf }
        let process = Process(), output = Pipe(), diagnostics = Pipe()
        process.executableURL = renderer
        process.arguments = ["-f", String(index), "-l", String(index), "-scale-to", "512", "-png", file.path]
        process.standardOutput = output
        process.standardError = diagnostics
        do { try process.run() } catch { throw ValidationFailure.validator_unavailable }
        // At512px raster output is bounded; diagnostics are drained concurrently.
        let errorBox = DiagnosticBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorBox.data = drain(diagnostics.fileHandleForReading, maximum: 65_536, process: process)
            group.leave()
        }
        let rendered = drain(output.fileHandleForReading, maximum: 4 * 1024 * 1024, process: process)
        process.waitUntilExit(); group.wait()
        guard process.terminationStatus == 0, !rendered.isEmpty, rendered.count <= 4 * 1024 * 1024,
            errorBox.data.isEmpty else { throw ValidationFailure.invalid_pdf }
    }
    return ["page_count": document.pageCount]
}
// Untrusted decoder diagnostics never reach the public response or grow without a limit.
func drain(_ file: FileHandle, maximum: Int, process: Process) -> Data {
    var data = Data()
    while let chunk = try? file.read(upToCount: min(16_384, maximum + 1 - data.count)), !chunk.isEmpty {
        data.append(chunk)
        if data.count > maximum { if process.isRunning { process.terminate() }; break }
    }
    return data
}
final class DiagnosticBox: @unchecked Sendable { var data = Data() }

func validateMP4Container(_ bytes: Data) throws {
    var offset = 0, boxes = 0
    var foundType = false, foundMetadata = false, foundMedia = false
    while offset < bytes.count {
        guard bytes.count - offset >= 8 else { throw ValidationFailure.invalid_video }
        let size32 = bytes[offset..<offset+4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let type = String(decoding: bytes[offset+4..<offset+8], as: UTF8.self)
        var header = 8
        let size: UInt64
        if size32 == 1 {
            guard bytes.count - offset >= 16 else { throw ValidationFailure.invalid_video }
            size = bytes[offset+8..<offset+16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            header = 16
        } else { size = size32 == 0 ? UInt64(bytes.count - offset) : size32 }
        guard size >= header, size <= UInt64(bytes.count - offset) else { throw ValidationFailure.invalid_video }
        if type == "ftyp" {
            guard !foundType, size >= header + 8 else { throw ValidationFailure.invalid_video }
            let brand = String(decoding: bytes[offset+header..<offset+header+4], as: UTF8.self)
            guard ["isom", "iso2", "mp41", "mp42", "avc1", "M4V "].contains(brand) else { throw ValidationFailure.unsupported_type }
            foundType = true
        }
        if type == "moov" { foundMetadata = true }
        if type == "mdat" { foundMedia = true }
        offset += Int(size); boxes += 1
        guard boxes <= 10_000 else { throw ValidationFailure.resource_limit }
    }
    guard foundType, foundMetadata, foundMedia else { throw ValidationFailure.invalid_video }
}

func validateVideo(_ bytes: Data) async throws -> [String: Int] {
    try validateMP4Container(bytes)
    let file = try privateFile(bytes, suffix: "mp4")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let asset = AVURLAsset(url: file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard try await !asset.load(.hasProtectedContent) else { throw ValidationFailure.unsupported_type }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw ValidationFailure.invalid_video }
    guard duration <= 30 else { throw ValidationFailure.duration_limit }
    let tracks = try await asset.load(.tracks)
    guard tracks.count == 1 || tracks.count == 2 else { throw ValidationFailure.unsupported_codec }
    var videos = 0, audios = 0, frames = 0, audioBuffers = 0, width = 0, height = 0
    for track in tracks {
        let type = track.mediaType
        guard type == .video || type == .audio else { throw ValidationFailure.unsupported_codec }
        let descriptions = try await track.load(.formatDescriptions)
        guard !descriptions.isEmpty else { throw ValidationFailure.invalid_video }
        for description in descriptions {
            let codec = CMFormatDescriptionGetMediaSubType(description)
            if type == .video {
                guard codec == kCMVideoCodecType_H264 else { throw ValidationFailure.unsupported_codec }
                let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                let w = Int(dimensions.width), h = Int(dimensions.height)
                guard w > 0, h > 0, max(w,h) <= 1920, min(w,h) <= 1080 else { throw ValidationFailure.dimensions_limit }
                width = max(width, w); height = max(height, h)
            } else {
                guard codec == kAudioFormatMPEG4AAC else { throw ValidationFailure.unsupported_codec }
                guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                    format.pointee.mChannelsPerFrame <= 8, format.pointee.mSampleRate <= 192_000 else { throw ValidationFailure.resource_limit }
            }
        }
        if type == .video { videos += 1 } else { audios += 1 }
        guard videos <= 1, audios <= 1 else { throw ValidationFailure.unsupported_codec }
        let settings: [String: Any] = type == .video ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : [AVFormatIDKey: kAudioFormatLinearPCM]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ValidationFailure.invalid_video }
        reader.add(output)
        guard reader.startReading() else { throw ValidationFailure.invalid_video }
        var decoded = 0
        while let sample = autoreleasepool(invoking: { output.copyNextSampleBuffer() }) {
            guard CMSampleBufferIsValid(sample), CMSampleBufferGetNumSamples(sample) > 0 else { throw ValidationFailure.invalid_video }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time.isFinite, time >= 0, time <= 30 else { throw ValidationFailure.invalid_video }
            if type == .video {
                guard let image = CMSampleBufferGetImageBuffer(sample), CVPixelBufferGetDataSize(image) > 0 else { throw ValidationFailure.invalid_video }
                let decodedWidth = CVPixelBufferGetWidth(image), decodedHeight = CVPixelBufferGetHeight(image)
                guard decodedWidth > 0, decodedHeight > 0, max(decodedWidth, decodedHeight) <= 1920,
                    min(decodedWidth, decodedHeight) <= 1080 else { throw ValidationFailure.dimensions_limit }
            } else {
                guard let block = CMSampleBufferGetDataBuffer(sample), CMBlockBufferGetDataLength(block) > 0 else { throw ValidationFailure.invalid_video }
            }
            decoded += 1
            guard decoded <= 10_000 else { reader.cancelReading(); throw ValidationFailure.resource_limit }
        }
        guard reader.status == .completed, decoded > 0 else { throw ValidationFailure.invalid_video }
        if type == .video { frames = decoded } else { audioBuffers = decoded }
    }
    guard videos == 1 else { throw ValidationFailure.unsupported_codec }
    return ["width": width, "height": height, "duration_milliseconds": Int((duration * 1000).rounded(.up)), "decoded_video_frames": frames, "decoded_audio_buffers": audioBuffers]
}

let reply: ValidationReply
do {
    let requestBytes = try FileHandle.standardInput.read(upToCount: 16_385) ?? Data()
    guard requestBytes.count <= 16_384 else { throw ValidationFailure.invalid_request }
    let request = try JSONDecoder().decode(ValidationRequest.self, from: requestBytes)
    guard request.path.hasPrefix("/"), !request.path.contains("\0"), request.path.utf8.count <= 4096 else { throw ValidationFailure.invalid_request }
    guard request.kind == "scouting" || request.kind == "practice" else { throw ValidationFailure.unsupported_type }
    let bytes = try readFile(request.path, maximum: (request.kind == "scouting" ? 5 : 10) * 1024 * 1024)
    let details: [String: Int]
    do { details = request.kind == "scouting" ? try validatePDF(bytes) : try await validateVideo(bytes) }
    catch let failure as ValidationFailure { throw failure }
    catch { throw request.kind == "scouting" ? ValidationFailure.invalid_pdf : ValidationFailure.invalid_video }
    reply = ValidationReply(valid: true, media_type: request.kind == "scouting" ? "application/pdf" : "video/mp4", byte_count: bytes.count,
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), details: details, failure_reason: nil)
} catch {
    reply = ValidationReply(valid: false, media_type: nil, byte_count: nil, sha256: nil, details: [:],
        failure_reason: (error as? ValidationFailure)?.rawValue ?? "invalid_request")
}
FileHandle.standardOutput.write(try JSONEncoder().encode(reply))
FileHandle.standardOutput.write(Data([10]))
