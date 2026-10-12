import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import AudioToolbox
import PDFKit

// Synthetic codec files only; no real team/student video is read.
func writeClip(_ url: URL, codec: AVVideoCodecType, width: Int, height: Int, seconds: Double, audio: Bool = false) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
    input.expectsMediaDataInRealTime = false
    let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    guard writer.canAdd(input) else { throw NSError(domain: "SyntheticFixture", code: 1) }
    writer.add(input)
    var audioInput: AVAssetWriterInput?
    if audio {
        let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
        guard writer.canAdd(sound) else { throw NSError(domain: "SyntheticFixture", code: 6) }
        writer.add(sound); audioInput = sound
    }
    guard writer.startWriting() else { throw NSError(domain: "SyntheticFixture", code: 2) }
    writer.startSession(atSourceTime: .zero)
    for index in 0..<3 {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess, let buffer else { throw NSError(domain: "SyntheticFixture", code: 3) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, Int32(index * 50), CVPixelBufferGetDataSize(buffer)) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
        guard adapter.append(buffer, withPresentationTime: CMTime(seconds: Double(index) * seconds / 2, preferredTimescale: 600)) else { throw NSError(domain: "SyntheticFixture", code: 4) }
    }
    input.markAsFinished()
    if let audioInput {
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr,
            let description else { throw NSError(domain: "SyntheticFixture", code: 7) }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: 96000, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: 96000, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
            let block else { throw NSError(domain: "SyntheticFixture", code: 8) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: 96000)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleSize = 2
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: description,
            sampleCount: 48000, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr,
            let sample else { throw NSError(domain: "SyntheticFixture", code: 9) }
        while !audioInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
        guard audioInput.append(sample) else { throw NSError(domain: "SyntheticFixture", code: 10) }
        audioInput.markAsFinished()
    }
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    guard done.wait(timeout: .now()+10) == .success, writer.status == .completed else { throw NSError(domain: "SyntheticFixture", code: 5) }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try writeClip(directory.appendingPathComponent("h264.mp4"), codec: .h264, width: 32, height: 32, seconds: 1)
try writeClip(directory.appendingPathComponent("hevc.mp4"), codec: .hevc, width: 32, height: 32, seconds: 1)
try writeClip(directory.appendingPathComponent("too-long.mp4"), codec: .h264, width: 32, height: 32, seconds: 31)
try writeClip(directory.appendingPathComponent("too-wide.mp4"), codec: .h264, width: 1936, height: 16, seconds: 1)
try writeClip(directory.appendingPathComponent("h264-aac.mp4"), codec: .h264, width: 32, height: 32, seconds: 1, audio: true)
if let pdf = PDFDocument(url: directory.appendingPathComponent("synthetic.pdf")) {
    guard pdf.write(to: directory.appendingPathComponent("encrypted.pdf"), withOptions: [.userPasswordOption: "synthetic-password", .ownerPasswordOption: "synthetic-owner-password"]) else { throw NSError(domain: "SyntheticFixture", code: 11) }
}
print("Synthetic native clips generated")
