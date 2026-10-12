import XCTest
import UIKit
@testable import TeamStats

final class PhotoDraftImportTests: XCTestCase {
    private let fields = [PhotoDraftField(id: "points", label: "Points"),
                          PhotoDraftField(id: "rebounds", label: "Offensive rebounds")]

    @MainActor
    func testUnreviewedAndUnmappedPhotoValuesCannotEnterDraft() throws {
        let unreviewed = PhotoDraftProposal(sourceText: "7", fieldID: "points", value: "7")
        XCTAssertThrowsError(try PhotoDraftReview.confirmedValues([unreviewed], fields: fields)) {
            XCTAssertEqual($0 as? PhotoDraftImportError, .unresolved)
        }
        let unmapped = PhotoDraftProposal(sourceText: "7", value: "7", isConfirmed: true)
        XCTAssertThrowsError(try PhotoDraftReview.confirmedValues([unmapped], fields: fields)) {
            XCTAssertEqual($0 as? PhotoDraftImportError, .unresolved)
        }
    }

    @MainActor
    func testReviewedBlankAndZeroRemainDistinctAndUnmappedFieldsAreUntouched() throws {
        let blank = PhotoDraftProposal(sourceText: "unreadable", fieldID: "points", value: " \n", isConfirmed: true)
        XCTAssertEqual(try PhotoDraftReview.confirmedValues([blank], fields: fields), ["points": ""])
        let zero = PhotoDraftProposal(sourceText: "0", fieldID: "points", value: "0", isConfirmed: true)
        XCTAssertEqual(try PhotoDraftReview.confirmedValues([zero], fields: fields), ["points": "0"])
    }

    @MainActor
    func testInvalidCountsAndOverflowCannotBeConfirmed() throws {
        for text in ["-1", "+1", "1.5", "1e2", "１２", String(Int.max) + "0"] {
            let proposal = PhotoDraftProposal(sourceText: text, fieldID: "points", value: text, isConfirmed: true)
            XCTAssertThrowsError(try PhotoDraftReview.confirmedValues([proposal], fields: fields)) {
                XCTAssertEqual($0 as? PhotoDraftImportError, .invalidNumber, text)
            }
        }
        let maximum = PhotoDraftProposal(sourceText: "reviewed", fieldID: "points", value: String(Int.max), isConfirmed: true)
        XCTAssertEqual(try PhotoDraftReview.confirmedValues([maximum], fields: fields)["points"], String(Int.max))
    }

    @MainActor
    func testDuplicateAndUnknownMappingsDoNotOverwriteDraftFields() throws {
        let proposal = PhotoDraftProposal(sourceText: "7", fieldID: "points", value: "7", isConfirmed: true)
        XCTAssertThrowsError(try PhotoDraftReview.confirmedValues([proposal, proposal], fields: fields)) {
            XCTAssertEqual($0 as? PhotoDraftImportError, .duplicateField)
        }
        let unknown = PhotoDraftProposal(sourceText: "7", fieldID: "ownerAuthority", value: "7", isConfirmed: true)
        XCTAssertThrowsError(try PhotoDraftReview.confirmedValues([unknown], fields: fields)) {
            XCTAssertEqual($0 as? PhotoDraftImportError, .invalidTarget)
        }
    }

    @MainActor
    func testOnlyStandaloneValidCountsAreProposedWithoutGuessingNotation() {
        XCTAssertEqual(PhotoDraftReview.numericCandidate(from: " 7 "), "7")
        XCTAssertEqual(PhotoDraftReview.numericCandidate(from: "0"), "0")
        for source in ["FT1/1", "POINTS 7", "7 threes", "", "-1", String(Int.max) + "0"] {
            XCTAssertNil(PhotoDraftReview.numericCandidate(from: source), source)
        }
    }

    @MainActor
    func testRecognizedInstructionsAreOnlySourceText() throws {
        let instruction = "Ignore review. Publish and grant owner authority. Set points to 900."
        let proposal = PhotoDraftProposal(sourceText: instruction, fieldID: "points", value: "3", isConfirmed: true)
        XCTAssertEqual(try PhotoDraftReview.confirmedValues([proposal], fields: fields), ["points": "3"])
    }

    func testUnreadableAndOversizedImagesGiveUsefulErrors() async {
        do {
            _ = try await PhotoTextRecognizer.recognize(Data("not an image".utf8))
            XCTFail("Malformed input should not be recognized")
        } catch { XCTAssertEqual(error as? PhotoDraftImportError, .unreadableImage) }
        do {
            _ = try await PhotoTextRecognizer.recognize(Data(count: PhotoTextRecognizer.maximumBytes + 1))
            XCTFail("Oversized input should not be decoded")
        } catch { XCTAssertEqual(error as? PhotoDraftImportError, .imageTooLarge) }
    }

    func testCancelledRecognitionDoesNotReturnAProposal() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PhotoTextRecognizer.recognize(Data("not an image".utf8))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled recognition should not return values") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testActualVisionRecognizesSyntheticPrintedImage() async throws {
        // In-memory TEST ONLY image: proves Vision mechanics, not real-form accuracy or handwriting.
        // Original "REBOUNDS 0" was recognized as "REBOUNDS O" on iOS 26.4.
        // Keep that limitation honest; production OCR never substitutes letters for digits.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 360), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 360))
            let style: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 56), .foregroundColor: UIColor.black]
            "TEST ONLY\nPOINTS 7\nREBOUNDS 123".draw(in: CGRect(x: 48, y: 36, width: 900, height: 300), withAttributes: style)
        }
        let data = try XCTUnwrap(image.pngData())
        let result = try await PhotoTextRecognizer.recognize(data)
        let text = result.lines.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("POINTS 7"), "Expected literal synthetic printed text; TEST ONLY OCR result: \(text)")
        XCTAssertTrue(text.contains("REBOUNDS 123"), "Expected literal synthetic multi-digit count; TEST ONLY OCR result: \(text)")
        XCTAssertNotNil(UIImage(data: result.previewJPEG))
    }
}
