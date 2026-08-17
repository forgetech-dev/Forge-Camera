import ForgeCore
import Foundation

/// Assigns stable identities to per-frame detections.
///
/// Vision reports what it sees in one frame; it does not say that this person is the
/// same person as last frame. Without that continuity, guidance flips between people
/// as detection order changes, which is worse than no guidance at all.
///
/// Deliberately simple: nearest-centre matching with a gate. Anything cleverer needs
/// evidence from recorded sessions that this is insufficient.
actor SubjectTracker {
    /// How far a subject may move between frames and still be considered the same
    /// person, as a fraction of the frame diagonal.
    private let matchDistanceThreshold = 0.2
    /// How many consecutive frames a subject may go missing before its identity is
    /// retired, so a brief detection dropout does not renumber everyone.
    private let missingFrameTolerance = 5

    private var nextIdentityNumber = 0
    private var missingFrameCounts: [SubjectID: Int] = [:]

    func track(
        _ observations: [SubjectObservation],
        previous: [DetectedSubject],
        minimumConfidence: Float
    ) -> [DetectedSubject] {
        let candidates = observations
            .filter { $0.confidence >= Double(minimumConfidence) }
            .sorted { $0.bounds.area > $1.bounds.area }

        var unmatched = previous
        var tracked: [DetectedSubject] = []

        for candidate in candidates {
            let matchIndex = unmatched.enumerated().min { lhs, rhs in
                distance(candidate.bounds, lhs.element.bounds)
                    < distance(candidate.bounds, rhs.element.bounds)
            }.flatMap { index, subject -> Int? in
                distance(candidate.bounds, subject.bounds) <= matchDistanceThreshold ? index : nil
            }

            let id: SubjectID
            if let matchIndex {
                id = unmatched[matchIndex].id
                unmatched.remove(at: matchIndex)
                missingFrameCounts[id] = 0
            } else {
                id = makeIdentity()
            }

            tracked.append(DetectedSubject(
                id: id,
                bounds: candidate.bounds,
                kind: .person,
                pose: candidate.pose,
                faceOrientation: nil,
                distance: nil,
                // Larger subjects are treated as more salient: guidance is about the
                // person being photographed, not whoever happens to be furthest away.
                salience: salience(for: candidate, among: candidates)
            ))
        }

        retire(unmatched)
        return tracked
    }

    private func makeIdentity() -> SubjectID {
        nextIdentityNumber += 1
        return SubjectID("subject-\(nextIdentityNumber)")
    }

    /// Ages out identities that were not seen this frame.
    private func retire(_ missing: [DetectedSubject]) {
        for subject in missing {
            let count = (missingFrameCounts[subject.id] ?? 0) + 1
            if count > missingFrameTolerance {
                missingFrameCounts.removeValue(forKey: subject.id)
            } else {
                missingFrameCounts[subject.id] = count
            }
        }
    }

    private func salience(
        for candidate: SubjectObservation,
        among candidates: [SubjectObservation]
    ) -> Double {
        guard let largest = candidates.first?.bounds.area, largest > 0 else { return 0 }
        return (candidate.bounds.area / largest).clampedToUnit
    }

    private func distance(
        _ lhs: ForgeCore.NormalizedRect,
        _ rhs: ForgeCore.NormalizedRect
    ) -> Double {
        let dx = lhs.center.x - rhs.center.x
        let dy = lhs.center.y - rhs.center.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private extension Double {
    var clampedToUnit: Double {
        Swift.min(1, Swift.max(0, self))
    }
}
