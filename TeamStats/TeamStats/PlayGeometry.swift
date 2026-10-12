import Foundation

/// Coordinates are relative to the displayed half court, never device pixels or roster identities.
struct CourtPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
struct PlayMarker: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var number: Int
    var label: String = ""
    var origin: CourtPoint
}
struct PlayPosition: Codable, Equatable, Sendable {
    var markerID: UUID
    var point: CourtPoint
}
struct PlayStep: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var duration: Double = 1
    var positions: [PlayPosition]
}
struct PlayDiagram: Codable, Equatable, Sendable {
    var markers: [PlayMarker] = []
    var steps: [PlayStep] = []
    var validationMessage: String? {
        guard Set(markers.map(\.id)).count == markers.count,
              Set(markers.map(\.number)).count == markers.count,
              markers.allSatisfy({ $0.number > 0 && $0.label.count <= 80 && $0.origin.isValid }),
              Set(steps.map(\.id)).count == steps.count else { return "Each marker needs a unique positive number and a valid court position. Labels may contain up to 80 characters." }
        let ids = Set(markers.map(\.id))
        guard steps.allSatisfy({ step in
            step.duration.isFinite && (0.1...30).contains(step.duration) &&
            Set(step.positions.map(\.markerID)) == ids && step.positions.count == markers.count &&
            step.positions.allSatisfy { $0.point.isValid }
        }) else { return "Every step needs one valid position per marker and a duration from 0.1 to 30 seconds." }
        return nil
    }
    var canPublish: Bool { validationMessage == nil && !markers.isEmpty && !steps.isEmpty }
    var duration: Double { steps.reduce(0) { $0 + $1.duration } }
    /// Playback computes presentation positions from authored steps, so pause/scrub never jumps to a target.
    func positions(at time: Double, reducedMotion: Bool = false) -> [PlayPosition] {
        guard validationMessage == nil, time.isFinite else { return [] }
        var previous = markers.map { PlayPosition(markerID: $0.id, point: $0.origin) }
        var elapsed = 0.0
        for step in steps {
            if time < elapsed + step.duration {
                let progress = max(0, min(1, (time - elapsed) / step.duration))
                if reducedMotion { return previous }
                return step.positions.compactMap { target in
                    guard let start = previous.first(where: { $0.markerID == target.markerID }) else { return nil }
                    return PlayPosition(markerID: target.markerID, point: CourtPoint(
                        x: start.point.x + (target.point.x - start.point.x) * progress,
                        y: start.point.y + (target.point.y - start.point.y) * progress))
                }
            }
            previous = step.positions; elapsed += step.duration
        }
        return previous
    }
    mutating func addMarker() {
        guard let next = markers.map(\.number).max()?.addingReportingOverflow(1), !next.overflow else {
            if markers.isEmpty { appendMarker(number: 1) }; return
        }
        appendMarker(number: next.partialValue)
    }
    private mutating func appendMarker(number: Int) {
        let marker = PlayMarker(number: number, origin: CourtPoint(x: 0.5, y: 0.5))
        markers.append(marker)
        for index in steps.indices { steps[index].positions.append(PlayPosition(markerID: marker.id, point: marker.origin)) }
    }
    mutating func addStep() {
        steps.append(PlayStep(positions: steps.last?.positions ?? markers.map { PlayPosition(markerID: $0.id, point: $0.origin) }))
    }
    /// Step 0 is the initial placement. Editing is separate from playback interpolation.
    func position(markerID: UUID, step: Int) -> CourtPoint? {
        if step == 0 { return markers.first { $0.id == markerID }?.origin }
        guard steps.indices.contains(step - 1) else { return nil }
        return steps[step - 1].positions.first { $0.markerID == markerID }?.point
    }
    mutating func move(markerID: UUID, step: Int, to point: CourtPoint) {
        guard point.isValid else { return }
        if step == 0, let index = markers.firstIndex(where: { $0.id == markerID }) { markers[index].origin = point }
        else if steps.indices.contains(step - 1), let index = steps[step - 1].positions.firstIndex(where: { $0.markerID == markerID }) {
            steps[step - 1].positions[index].point = point
        }
    }
}
