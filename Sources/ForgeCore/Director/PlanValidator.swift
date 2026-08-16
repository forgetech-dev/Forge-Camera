import Foundation

/// The boundary where untrusted model output becomes application state.
///
/// Validation is **field-level, not all-or-nothing**: an invalid `targetX` drops that
/// one field and keeps the rest of the plan. A good subject placement should not be
/// lost because the model emitted a silly focal length. Only a plan whose identity is
/// unusable is rejected outright.
public struct PlanValidator: Sendable {
    public struct Context: Sendable {
        /// Focal lengths the connected camera and lens can actually deliver, if known.
        public let supportedFocalLengths: ClosedRange<Double>?
        /// Largest fraction of the frame a single avoid-region may cover.
        public let maximumAvoidRegionArea: Double

        public init(
            supportedFocalLengths: ClosedRange<Double>? = nil,
            maximumAvoidRegionArea: Double = 0.6
        ) {
            self.supportedFocalLengths = supportedFocalLengths
            self.maximumAvoidRegionArea = maximumAvoidRegionArea
        }

        public static let unconstrained = Context()
    }

    /// A field that was dropped or altered, kept so the UI and logs can explain why.
    public struct Warning: Sendable, Equatable {
        public let field: String
        public let reason: String

        public init(field: String, reason: String) {
            self.field = field
            self.reason = reason
        }
    }

    public struct Result: Sendable, Equatable {
        public let plan: CompositionPlan
        public let warnings: [Warning]

        public var isClean: Bool {
            warnings.isEmpty
        }
    }

    public enum Failure: Error, Sendable, Equatable {
        case unsupportedSchemaVersion(found: Int, supported: Int)
        case missingPlanId
        case unknownIntent(String)
    }

    public init() {}

    /// Validates a decoded plan, degrading individual fields rather than rejecting
    /// the whole plan wherever that is possible.
    public func validate(
        _ plan: CompositionPlan,
        context: Context = .unconstrained
    ) throws -> Result {
        // Hard rejections: without these the plan has no usable identity.
        guard plan.schemaVersion == CompositionPlan.currentSchemaVersion else {
            throw Failure.unsupportedSchemaVersion(
                found: plan.schemaVersion,
                supported: CompositionPlan.currentSchemaVersion
            )
        }
        guard !plan.planId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingPlanId
        }
        guard plan.intent.isKnown else {
            throw Failure.unknownIntent(plan.intent.rawValue)
        }

        var warnings: [Warning] = []

        let confidence = unitInterval(plan.confidence, field: "confidence", into: &warnings)
        let subject = validateSubject(plan.subject, into: &warnings)
        let scene = validateScene(plan.scene, context: context, into: &warnings)
        let camera = validateCamera(plan.camera, context: context, into: &warnings)
        let exposure = validateExposure(plan.exposure, into: &warnings)
        let capture = validateCapture(plan.capture, into: &warnings)
        let lifetime = positive(
            plan.expiresAfterSeconds,
            field: "expiresAfterSeconds",
            into: &warnings
        )

        let validated = CompositionPlan(
            schemaVersion: plan.schemaVersion,
            planId: plan.planId,
            requestId: plan.requestId,
            intent: plan.intent,
            confidence: confidence,
            rationale: plan.rationale,
            subject: subject,
            scene: scene,
            camera: camera,
            exposure: exposure,
            capture: capture,
            expiresAfterSeconds: lifetime
        )

        return Result(plan: validated, warnings: warnings)
    }

    // MARK: - Sections

    private func validateSubject(
        _ subject: SubjectPlan?,
        into warnings: inout [Warning]
    ) -> SubjectPlan? {
        guard let subject else { return nil }

        let plan = SubjectPlan(
            targetX: unitInterval(subject.targetX, field: "subject.targetX", into: &warnings),
            targetY: unitInterval(subject.targetY, field: "subject.targetY", into: &warnings),
            targetHeight: positiveUnitInterval(
                subject.targetHeight, field: "subject.targetHeight", into: &warnings
            ),
            bodyYaw: angle(subject.bodyYaw, field: "subject.bodyYaw", into: &warnings),
            headYaw: angle(subject.headYaw, field: "subject.headYaw", into: &warnings),
            poseHint: subject.poseHint
        )
        return plan.isEmpty ? nil : plan
    }

    private func validateScene(
        _ scene: ScenePlan?,
        context: Context,
        into warnings: inout [Warning]
    ) -> ScenePlan? {
        guard let scene else { return nil }

        let horizon = unitInterval(
            scene.targetHorizon,
            field: "scene.targetHorizon",
            into: &warnings
        )

        var regions: [NormalizedRect]?
        if let candidates = scene.avoidRegions {
            let kept = candidates.filter { region in
                guard region.x.isUsableNumber, region.y.isUsableNumber,
                      region.width.isUsableNumber, region.height.isUsableNumber
                else {
                    warnings.append(.init(field: "scene.avoidRegions", reason: "non-finite value"))
                    return false
                }
                guard region.isWellFormed else {
                    warnings.append(.init(field: "scene.avoidRegions", reason: "outside the frame"))
                    return false
                }
                // A director that says "avoid everything" has failed; acting on it
                // produces nonsense guidance.
                guard region.area <= context.maximumAvoidRegionArea else {
                    warnings.append(.init(
                        field: "scene.avoidRegions",
                        reason: "covers more than \(context.maximumAvoidRegionArea) of the frame"
                    ))
                    return false
                }
                return true
            }
            regions = kept.isEmpty ? nil : kept
        }

        if horizon == nil, regions == nil {
            return nil
        }
        return ScenePlan(targetHorizon: horizon, avoidRegions: regions)
    }

    private func validateCamera(
        _ camera: CameraPlan?,
        context: Context,
        into warnings: inout [Warning]
    ) -> CameraPlan? {
        guard let camera else { return nil }

        let height = finite(
            camera.heightAdjustment,
            field: "camera.heightAdjustment",
            into: &warnings
        )
        let yaw = angle(camera.yawAdjustment, field: "camera.yawAdjustment", into: &warnings)

        var focalLength = positive(
            camera.recommendedFocalLength, field: "camera.recommendedFocalLength", into: &warnings
        )
        if let value = focalLength {
            if let supported = context.supportedFocalLengths {
                let snapped = Swift.min(
                    Swift.max(value, supported.lowerBound),
                    supported.upperBound
                )
                if snapped != value {
                    warnings.append(.init(
                        field: "camera.recommendedFocalLength",
                        reason: "snapped to the supported range"
                    ))
                }
                focalLength = snapped
            } else {
                // Focal length is unknown and no manual value was supplied, so a
                // recommendation cannot be acted on or even sanity-checked.
                warnings.append(.init(
                    field: "camera.recommendedFocalLength",
                    reason: "dropped: camera focal length range is unknown"
                ))
                focalLength = nil
            }
        }

        let plan = CameraPlan(
            heightAdjustment: height,
            yawAdjustment: yaw,
            recommendedFocalLength: focalLength
        )
        return plan.isEmpty ? nil : plan
    }

    private func validateExposure(
        _ exposure: ExposurePlan?,
        into warnings: inout [Warning]
    ) -> ExposurePlan? {
        guard let exposure else { return nil }

        let plan = ExposurePlan(
            priority: exposure.priority,
            apertureHint: positive(
                exposure.apertureHint,
                field: "exposure.apertureHint",
                into: &warnings
            ),
            minShutterDenominator: positive(
                exposure.minShutterDenominator, field: "exposure.minShutterDenominator",
                into: &warnings
            )
        )
        return plan.isEmpty ? nil : plan
    }

    private func validateCapture(
        _ capture: CapturePlan?,
        into warnings: inout [Warning]
    ) -> CapturePlan? {
        guard let capture else { return nil }

        guard case .bracket = capture.kind else {
            return CapturePlan(kind: capture.kind, stops: nil)
        }
        guard let stops = capture.stops, !stops.isEmpty, stops.allSatisfy(\.isUsableNumber) else {
            warnings.append(.init(field: "capture.stops", reason: "bracket without usable stops"))
            return CapturePlan(kind: .single, stops: nil)
        }
        return CapturePlan(kind: .bracket, stops: stops.sorted())
    }

    // MARK: - Field helpers

    private func finite(
        _ value: Double?,
        field: String,
        into warnings: inout [Warning]
    ) -> Double? {
        guard let value else { return nil }
        guard value.isUsableNumber else {
            warnings.append(.init(field: field, reason: "non-finite value"))
            return nil
        }
        return value
    }

    private func unitInterval(
        _ value: Double?, field: String, into warnings: inout [Warning]
    ) -> Double? {
        guard let value = finite(value, field: field, into: &warnings) else { return nil }
        guard (0 ... 1).contains(value) else {
            warnings.append(.init(field: field, reason: "clamped into [0, 1]"))
            return value.clampedToUnitInterval
        }
        return value
    }

    private func positiveUnitInterval(
        _ value: Double?, field: String, into warnings: inout [Warning]
    ) -> Double? {
        guard let value = unitInterval(value, field: field, into: &warnings) else { return nil }
        guard value > 0 else {
            warnings.append(.init(field: field, reason: "must be greater than zero"))
            return nil
        }
        return value
    }

    private func positive(
        _ value: Double?,
        field: String,
        into warnings: inout [Warning]
    ) -> Double? {
        guard let value = finite(value, field: field, into: &warnings) else { return nil }
        guard value > 0 else {
            warnings.append(.init(field: field, reason: "must be greater than zero"))
            return nil
        }
        return value
    }

    private func angle(_ value: Angle?, field: String, into warnings: inout [Warning]) -> Angle? {
        guard let value else { return nil }
        guard value.degrees.isUsableNumber else {
            warnings.append(.init(field: field, reason: "non-finite value"))
            return nil
        }
        let wrapped = value.wrapped()
        if wrapped != value {
            warnings.append(.init(field: field, reason: "wrapped into (-180, 180]"))
        }
        return wrapped
    }
}

// MARK: - Emptiness

//
// A section whose every field was dropped becomes nil rather than an empty object,
// so downstream code never has to distinguish "present but useless" from "absent".

extension SubjectPlan {
    var isEmpty: Bool {
        targetX == nil && targetY == nil && targetHeight == nil
            && bodyYaw == nil && headYaw == nil && poseHint == nil
    }
}

extension CameraPlan {
    var isEmpty: Bool {
        heightAdjustment == nil && yawAdjustment == nil && recommendedFocalLength == nil
    }
}

extension ExposurePlan {
    var isEmpty: Bool {
        priority == nil && apertureHint == nil && minShutterDenominator == nil
    }
}
