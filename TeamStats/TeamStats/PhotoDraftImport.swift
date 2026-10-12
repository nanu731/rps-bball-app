import Foundation
import Darwin

nonisolated enum PhotoDraftFileReader {
    static let maximumBytes = 25 * 1_024 * 1_024

    static func read(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL else { throw PhotoDraftImportError.unreadableImage }
        // Nonblocking/no-follow prevents special files or a swapped symlink from bypassing the bound.
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw PhotoDraftImportError.unreadableImage }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size > 0 else {
            throw PhotoDraftImportError.unreadableImage
        }
        guard before.st_size <= maximumBytes else { throw PhotoDraftImportError.imageTooLarge }
        var data = Data()
        while data.count <= maximumBytes {
            try Task.checkCancellation()
            let remaining = maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maximumBytes else { throw PhotoDraftImportError.imageTooLarge }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw PhotoDraftImportError.unreadableImage }
        guard after.st_size <= maximumBytes else { throw PhotoDraftImportError.imageTooLarge }
        guard after.st_size == before.st_size, data.count == before.st_size else {
            throw PhotoDraftImportError.unreadableImage
        }
        try Task.checkCancellation()
        return data
    }
}

enum PhotoDraftFieldKind: Equatable, Sendable {
    case count, turnover
}

struct PhotoDraftField: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let kind: PhotoDraftFieldKind

    init(id: String, label: String, kind: PhotoDraftFieldKind = .count) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

struct PhotoDraftProposal: Identifiable, Equatable, Sendable {
    let id = UUID()
    let sourceText: String
    var fieldID: String? {
        didSet { if fieldID != oldValue { isConfirmed = false } }
    }
    var value = "" {
        didSet { if value != oldValue { isConfirmed = false } }
    }
    var isConfirmed = false
}

enum PhotoDraftImportError: LocalizedError, Equatable {
    case unresolved, invalidNumber, invalidTurnover, duplicateField, invalidTarget
    case unsupportedImage, imageTooLarge, unreadableImage, noText, tooMuchText, recognitionFailed, timedOut

    var errorDescription: String? {
        switch self {
        case .unresolved: "Choose each field and confirm every value before applying."
        case .invalidNumber: "Enter a nonnegative whole number within the supported integer range, or leave blank."
        case .invalidTurnover: "Choose Unanswered, Yes or No. A number or recognized notation is not a turnover answer."
        case .duplicateField: "Choose each field only once. Review the duplicate mappings."
        case .invalidTarget: "The available fields changed. Close photo review and reopen the entry screen."
        case .unsupportedImage: "Choose a single JPEG, PNG, HEIC or HEIF image. Other formats are not supported."
        case .imageTooLarge: "Choose a photo under 25 MB and 36 million pixels. The original is unchanged."
        case .unreadableImage: "The selected photo could not be read. Try another photo."
        case .noText: "No readable text was found. Try a clearer photo or enter the values manually."
        case .tooMuchText: "This photo contains too much text to review safely. Choose a closer crop."
        case .recognitionFailed: "Text recognition failed. Try another photo or enter the values manually."
        case .timedOut: "Text recognition took too long. Try a closer crop or a clearer photo."
        }
    }
}

enum PhotoDraftReview {
    static func numericCandidate(from sourceText: String) -> String? {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), Int(text) != nil else { return nil }
        return text
    }

    static func validationIssue(value: String, kind: PhotoDraftFieldKind) -> PhotoDraftImportError? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .count:
            return text.isEmpty || (text.utf8.allSatisfy { (48...57).contains($0) } && Int(text) != nil) ? nil : .invalidNumber
        case .turnover:
            return ["", "yes", "no"].contains(text) ? nil : .invalidTurnover
        }
    }

    // No notation or identity inference: only explicitly mapped, reviewed fields cross this seam.
    static func confirmedValues(_ proposals: [PhotoDraftProposal], fields: [PhotoDraftField]) throws -> [String: String] {
        let known = Set(fields.map(\.id))
        guard !fields.isEmpty, known.count == fields.count, !known.contains("") else {
            throw PhotoDraftImportError.invalidTarget
        }
        guard !proposals.isEmpty else { throw PhotoDraftImportError.unresolved }
        var values: [String: String] = [:]
        for proposal in proposals {
            guard proposal.isConfirmed, let field = proposal.fieldID else { throw PhotoDraftImportError.unresolved }
            guard let target = fields.first(where: { $0.id == field }) else { throw PhotoDraftImportError.invalidTarget }
            guard values[field] == nil else { throw PhotoDraftImportError.duplicateField }
            let text = proposal.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let issue = validationIssue(value: text, kind: target.kind) { throw issue }
            values[field] = text
        }
        return values
    }
}

#if canImport(UIKit)
import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct PhotoRecognizedLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let confidence: Float
}

struct PhotoRecognitionResult: Sendable {
    let lines: [PhotoRecognizedLine]
    let previewJPEG: Data
}

// Read inside the provider callback: its temporary URL is not guaranteed after importing returns.
nonisolated private enum PhotoImportedImage: Transferable, Sendable {
    case image(Data)
    case rejected(PhotoDraftImportError)

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: false) { received in
            do { return .image(try PhotoDraftFileReader.read(received.file)) }
            catch let issue as PhotoDraftImportError { return .rejected(issue) }
        }
    }
}

nonisolated enum PhotoTextRecognizer {
    static let maximumBytes = PhotoDraftFileReader.maximumBytes

    static func recognize(_ data: Data) async throws -> PhotoRecognitionResult {
        try Task.checkCancellation()
        let operation = PhotoRecognitionOperation()
        return try await withTaskCancellationHandler {
            let result = try await Task.detached(priority: .userInitiated) {
                try operation.run(data)
            }.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            operation.cancel()
        }
    }
}

// Vision's synchronous request runs off the main actor; only cancellation crosses threads.
nonisolated private final class PhotoRecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRecognizeTextRequest?
    private var cancelled = false
    private var timedOut = false

    func cancel(timeout: Bool = false) {
        lock.lock()
        cancelled = true
        timedOut = timedOut || timeout
        let current = request
        lock.unlock()
        current?.cancel()
    }

    private func checkCancellation() throws {
        lock.lock()
        let isCancelled = cancelled, didTimeOut = timedOut
        lock.unlock()
        if didTimeOut { throw PhotoDraftImportError.timedOut }
        if isCancelled { throw CancellationError() }
    }

    func run(_ data: Data) throws -> PhotoRecognitionResult {
        try checkCancellation()
        guard !data.isEmpty, data.count <= PhotoTextRecognizer.maximumBytes else { throw PhotoDraftImportError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) else { throw PhotoDraftImportError.unreadableImage }
        let allowed = [UTType.jpeg.identifier, UTType.png.identifier, "public.heic", "public.heif"]
        guard allowed.contains(type as String), CGImageSourceGetCount(source) == 1 else {
            throw PhotoDraftImportError.unsupportedImage
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 36_000_000 else { throw PhotoDraftImportError.imageTooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoDraftImportError.unreadableImage
        }
        try checkCancellation()
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.usesLanguageCorrection = false
        lock.lock()
        request = recognition
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { recognition.cancel(); try checkCancellation() }
        let deadline = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: deadline)
        defer { deadline.cancel() }
        do { try VNImageRequestHandler(cgImage: image).perform([recognition]) }
        catch {
            try checkCancellation()
            throw PhotoDraftImportError.recognitionFailed
        }
        try checkCancellation()
        let observations = recognition.results ?? []
        guard observations.count <= 1_000 else { throw PhotoDraftImportError.tooMuchText }
        var lines: [PhotoRecognizedLine] = []
        var characterCount = 0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            characterCount += candidate.string.utf8.count
            guard characterCount <= 65_536 else { throw PhotoDraftImportError.tooMuchText }
            lines.append(PhotoRecognizedLine(text: candidate.string, confidence: candidate.confidence))
        }
        guard !lines.isEmpty else { throw PhotoDraftImportError.noText }
        // This bounded preview is transient; neither the original nor OCR text is saved or uploaded.
        let preview = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(preview, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoDraftImportError.unreadableImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoDraftImportError.unreadableImage }
        return PhotoRecognitionResult(lines: lines, previewJPEG: preview as Data)
    }
}

struct PhotoDraftImportSheet: View {
    let targetLabel: String
    let fields: [PhotoDraftField]
    let onApply: ([String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var isRecognizing = false
    @State private var lines: [PhotoRecognizedLine] = []
    @State private var preview: UIImage?
    @State private var proposals: [PhotoDraftProposal] = []
    @State private var issue: String?
    @FocusState private var numericField: UUID?

    private var reviewedValues: [String: String]? {
        try? PhotoDraftReview.confirmedValues(proposals, fields: fields)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Existing draft target") {
                    Text(targetLabel).font(.headline)
                    Text("Review each field and value before applying. Only this unsaved draft changes; Save and publication stay separate.")
                    Text("Recognition does not interpret shot notation or identify players. Unclear values stay unresolved.")
                        .foregroundStyle(.secondary)
                }
                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("Choose photo", systemImage: "photo")
                            .frame(minHeight: 44)
                    }
                    .disabled(isRecognizing || !proposals.isEmpty)
                    Text("Processed on this device. The app does not persist or upload the image or recognized text. Photos may download an iCloud image or cache a temporary file.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if isRecognizing {
                        ProgressView("Reading photo…")
                        Button("Cancel recognition") { cancelRecognition() }.frame(minHeight: 44)
                    }
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).accessibilityIdentifier("photoReview.error")
                    }
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit()
                            .accessibilityLabel("Selected photo preview. Review the original details before confirming values.")
                    }
                }
                if !lines.isEmpty {
                    Section("Recognized text — check against the photo") {
                        Text("Tap a line to map a value. Text can be wrong even when recognition is confident. A whole form is not automatically mapped.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(lines) { line in
                            Button {
                                proposals.append(PhotoDraftProposal(sourceText: line.text, value: PhotoDraftReview.numericCandidate(from: line.text) ?? ""))
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(line.text).foregroundStyle(.primary)
                                    Label("Review a value from this line", systemImage: "plus")
                                    if line.confidence < 0.5 {
                                        Label("Low-confidence text", systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(.secondary)
                                    }
                                }.frame(minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            .disabled(proposals.count >= fields.count)
                        }
                    }
                }
                ForEach($proposals) { $proposal in
                    Section("Review value") {
                        Text("Source: \(proposal.sourceText)").textSelection(.enabled)
                        Picker("Existing field", selection: $proposal.fieldID) {
                            Text("Unresolved — choose field").tag(String?.none)
                            ForEach(fields) { field in Text(field.label).tag(Optional(field.id)) }
                        }
                        if fields.first(where: { $0.id == proposal.fieldID })?.kind == .turnover {
                            Picker("Reviewed turnover answer", selection: $proposal.value) {
                                if !["", "yes", "no"].contains(proposal.value) {
                                    Text("Unresolved — choose answer").tag(proposal.value)
                                }
                                Text("Unanswered").tag("")
                                Text("Yes").tag("yes")
                                Text("No").tag("no")
                            }
                            Text("Unanswered stays missing. Yes and No are explicit answers; neither is inferred from the photo.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            if PhotoDraftReview.numericCandidate(from: proposal.sourceText) == nil && !proposal.isConfirmed {
                                Label("Value unresolved — review the photo and enter a count, or explicitly confirm blank.", systemImage: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            TextField("Reviewed value; blank = not entered", text: $proposal.value)
                                .keyboardType(.numberPad).focused($numericField, equals: proposal.id)
                                .accessibilityLabel("Reviewed value for \(fields.first { $0.id == proposal.fieldID }?.label ?? "unresolved field")")
                            Text("Confirmed blank replaces this field with Not entered. Explicit 0 remains 0.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let validation = validationIssue(proposal) {
                            Label(validation, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                        Toggle("I checked this field and value against the photo", isOn: $proposal.isConfirmed)
                            .disabled(proposal.fieldID == nil || validationIssue(proposal) != nil)
                    }
                }
                if !proposals.isEmpty {
                    Section {
                        if let error = reviewIssue {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        }
                        Button("Apply reviewed values to draft") { apply() }
                            .frame(minHeight: 44).disabled(reviewedValues == nil || isRecognizing)
                            .accessibilityIdentifier("photoReview.apply")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancelRecognition(); dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numericField = nil }
                }
            }
            .onChange(of: selectedPhoto) { _, item in recognize(item) }
            .onDisappear {
                cancelRecognition()
                lines = []; preview = nil; proposals = []; selectedPhoto = nil
            }
        }
    }

    private var reviewIssue: String? {
        do { _ = try PhotoDraftReview.confirmedValues(proposals, fields: fields); return nil }
        catch { return error.localizedDescription }
    }

    private func validationIssue(_ proposal: PhotoDraftProposal) -> String? {
        if let field = fields.first(where: { $0.id == proposal.fieldID }),
           let issue = PhotoDraftReview.validationIssue(value: proposal.value, kind: field.kind) {
            return issue.localizedDescription
        }
        if let field = proposal.fieldID, proposals.filter({ $0.fieldID == field }).count > 1 {
            return PhotoDraftImportError.duplicateField.localizedDescription
        }
        return nil
    }

    private func recognize(_ item: PhotosPickerItem?) {
        guard let item else { return }
        cancelRecognition()
        let id = UUID()
        requestID = id
        isRecognizing = true
        issue = nil; lines = []; preview = nil
        recognitionTask = Task {
            do {
                guard let imported = try await item.loadTransferable(type: PhotoImportedImage.self) else {
                    throw PhotoDraftImportError.unreadableImage
                }
                let data: Data
                switch imported {
                case .image(let boundedData): data = boundedData
                case .rejected(let issue): throw issue
                }
                try Task.checkCancellation()
                let result = try await PhotoTextRecognizer.recognize(data)
                guard requestID == id, !Task.isCancelled else { return }
                lines = result.lines
                preview = UIImage(data: result.previewJPEG)
                isRecognizing = false
                selectedPhoto = nil
            } catch {
                guard requestID == id else { return }
                isRecognizing = false
                selectedPhoto = nil
                if !(error is CancellationError) {
                    issue = (error as? PhotoDraftImportError)?.localizedDescription ?? PhotoDraftImportError.unreadableImage.localizedDescription
                }
            }
        }
    }

    private func cancelRecognition() {
        requestID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecognizing = false
        selectedPhoto = nil
    }

    private func apply() {
        guard let values = reviewedValues else { return }
        numericField = nil
        onApply(values)
        dismiss()
    }
}
#endif
