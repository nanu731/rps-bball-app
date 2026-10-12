import XCTest
import UIKit
import PDFKit
import Darwin
@testable import TeamStats

final class ScoutingReportDocumentTests: XCTestCase {
    @MainActor
    func testReadablePDFReturnsOriginalBytesAndPageCountWithoutChangingSource() throws {
        let bytes = samplePDF()
        let url = try fixture(bytes)
        let result = try ScoutingReportDocument.read(url)
        XCTAssertEqual(result.bytes, bytes)
        XCTAssertEqual(result.pageCount, 1)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    private func samplePDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
            .pdfData { context in
                context.beginPage()
                "TEST ONLY scouting validation".draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            }
    }

    private func fixture(_ bytes: Data) throws -> URL {
        // Retain only clearly synthetic, uniquely named test artifacts; never touch existing files.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TEST_ONLY_scouting_\(UUID().uuidString).pdf")
        try bytes.write(to: url, options: .atomic)
        return url
    }

    func testOversizedFileIsRejectedWithoutChangingSource() throws {
        let url = try fixture(Data("%PDF-1.7\nTEST ONLY".utf8))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 5_242_881)
        try handle.close()
        XCTAssertThrowsError(try ScoutingReportDocument.read(url)) {
            XCTAssertEqual($0 as? ScoutingReportDocumentError, .tooLarge)
        }
        XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, 5_242_881)
    }

    @MainActor
    func testEncryptedPDFIsRejectedEvenWhenItOpensWithoutAUserPassword() throws {
        let document = try XCTUnwrap(PDFDocument(data: samplePDF()))
        let bytes = try XCTUnwrap(document.dataRepresentation(options: [
            PDFDocumentWriteOption.ownerPasswordOption: "TEST_ONLY_synthetic_owner_password"
        ]))
        let encrypted = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue(encrypted.isEncrypted)
        XCTAssertFalse(encrypted.isLocked)
        let url = try fixture(bytes)
        XCTAssertThrowsError(try ScoutingReportDocument.read(url)) {
            XCTAssertEqual($0 as? ScoutingReportDocumentError, .encrypted)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testPasswordLockedPDFIsRejectedWithoutRequestingOrChangingPasswords() throws {
        let document = try XCTUnwrap(PDFDocument(data: samplePDF()))
        let bytes = try XCTUnwrap(document.dataRepresentation(options: [
            PDFDocumentWriteOption.ownerPasswordOption: "TEST_ONLY_synthetic_owner_password",
            PDFDocumentWriteOption.userPasswordOption: "TEST_ONLY_synthetic_reader_password"
        ]))
        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: bytes)).isLocked)
        let url = try fixture(bytes)
        XCTAssertThrowsError(try ScoutingReportDocument.read(url)) {
            XCTAssertEqual($0 as? ScoutingReportDocumentError, .encrypted)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testReadablePDFAtExactlyFiveMiBIsAccepted() throws {
        var bytes = samplePDF()
        let trailer = try XCTUnwrap(String(decoding: bytes, as: UTF8.self)
            .components(separatedBy: "startxref").last)
        let end = Data(("\nstartxref" + trailer).utf8)
        bytes.append(Data(repeating: 0x20, count: 5_242_880 - bytes.count - end.count))
        bytes.append(end)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: bytes)).pageCount, 1)
        let result = try ScoutingReportDocument.read(fixture(bytes))
        XCTAssertEqual(result.bytes.count, 5_242_880)
        XCTAssertEqual(result.pageCount, 1)
    }

    func testEmptyMalformedAndNonPDFBytesAreRejected() throws {
        for bytes in [Data(), Data("TEST ONLY not a PDF".utf8), Data("%PDF-1.7\nTEST ONLY truncated".utf8)] {
            let url = try fixture(bytes)
            XCTAssertThrowsError(try ScoutingReportDocument.read(url)) {
                XCTAssertEqual($0 as? ScoutingReportDocumentError, .unreadable)
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testMissingRemoteDirectorySymlinkAndPipeInputsAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TEST_ONLY_scouting_access_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let original = try fixture(Data("TEST ONLY".utf8))
        let link = directory.appendingPathComponent("symlink.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let pipe = directory.appendingPathComponent("pipe.pdf")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        for url in [directory.appendingPathComponent("missing.pdf"),
                    try XCTUnwrap(URL(string: "https://example.invalid/test-only.pdf")), directory, link, pipe] {
            XCTAssertThrowsError(try ScoutingReportDocument.read(url)) {
                XCTAssertEqual($0 as? ScoutingReportDocumentError, .unreadable)
            }
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("TEST ONLY".utf8))
    }

    @MainActor
    func testCancelledReadReturnsNoDocument() async throws {
        let url = try fixture(samplePDF())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ScoutingReportDocument.read(url)
        }
        do { _ = try await task.value; XCTFail("Cancelled selection must not return report bytes") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
