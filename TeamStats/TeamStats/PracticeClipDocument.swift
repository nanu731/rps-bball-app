import Foundation
import AVFoundation
import Darwin

/// Bounded local preparation, never a trusted upload/approval receipt. The server
/// decodes the exact uploaded bytes independently before publication.
nonisolated struct PracticeClipDocument: Sendable {
    static let maximumBytes = 10 * 1_024 * 1_024
    let bytes: Data

    static func read(_ url: URL) async throws -> PracticeClipDocument {
        try Task.checkCancellation()
        guard url.isFileURL else { throw PracticeClipDocumentError.unreadable }
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw PracticeClipDocumentError.unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0 else { throw PracticeClipDocumentError.unreadable }
        guard before.st_size <= maximumBytes else { throw PracticeClipDocumentError.tooLarge }
        var bytes = Data()
        while bytes.count <= maximumBytes {
            try Task.checkCancellation()
            let remaining = maximumBytes + 1 - bytes.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
            bytes.append(chunk)
            guard bytes.count <= maximumBytes else { throw PracticeClipDocumentError.tooLarge }
        }
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
        ])
        guard try await asset.load(.isPlayable) else { throw PracticeClipDocumentError.unsupported }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 0 && duration <= 30 else { throw PracticeClipDocumentError.unsupported }
        let tracks = try await asset.load(.tracks)
        let video = tracks.filter { $0.mediaType == .video }
        let audio = tracks.filter { $0.mediaType == .audio }
        guard video.count == 1, audio.count <= 1, tracks.count == video.count + audio.count else {
            throw PracticeClipDocumentError.unsupported
        }
        for track in tracks {
            let descriptions = try await track.load(.formatDescriptions)
            guard !descriptions.isEmpty else { throw PracticeClipDocumentError.unsupported }
            for description in descriptions {
                let subtype = CMFormatDescriptionGetMediaSubType(description)
                if track.mediaType == .video {
                    let size = CMVideoFormatDescriptionGetDimensions(description)
                    guard subtype == kCMVideoCodecType_H264, min(size.width, size.height) > 0,
                          max(size.width, size.height) <= 1920, min(size.width, size.height) <= 1080 else {
                        throw PracticeClipDocumentError.unsupported
                    }
                } else if subtype != kAudioFormatMPEG4AAC { throw PracticeClipDocumentError.unsupported }
            }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, after.st_size == before.st_size,
              bytes.count == before.st_size else { throw PracticeClipDocumentError.unreadable }
        try Task.checkCancellation()
        return PracticeClipDocument(bytes: bytes)
    }
}

nonisolated enum PracticeClipDocumentError: LocalizedError {
    case unreadable, tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .unreadable: "The clip could not be read. Choose a local MP4; the original is unchanged."
        case .tooLarge: "Choose a clip of 10 MiB or less. TeamStats does not compress the original."
        case .unsupported: "Choose an MP4 with H.264 video and optional AAC audio, at most 30 seconds and 1920 × 1080 (either orientation). Trusted validation still runs after upload."
        }
    }
}
