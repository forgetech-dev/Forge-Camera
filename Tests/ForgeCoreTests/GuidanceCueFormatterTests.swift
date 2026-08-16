import Testing
@testable import ForgeCore

@Suite("Guidance cue formatting")
struct GuidanceCueFormatterTests {
    let formatter = GuidanceCueFormatter()

    private func cue(
        axis: GuidanceAxis = .left,
        magnitude: GuidanceMagnitude,
        rotation: GuidanceRotation? = nil
    ) -> GuidanceCue {
        GuidanceCue(
            actor: .photographer,
            axis: axis,
            magnitude: magnitude,
            rotation: rotation,
            priority: 1
        )
    }

    // MARK: The honesty rule, as user-visible text

    @Test("A relative cue never renders a number")
    func relativeCueHasNoNumber() {
        for relative in GuidanceMagnitude.Relative.allCases {
            let text = formatter.text(for: cue(magnitude: .relative(relative)))
            // The whole point: no digits can reach the screen for a quantity that was
            // never measured.
            let containsDigit = text.contains { $0.isNumber }
            #expect(!containsDigit, "unexpected number in \"\(text)\"")
        }
    }

    @Test("A relative cue never renders a unit")
    func relativeCueHasNoUnit() {
        // Compared word by word, not by substring: "Move left" contains "ft" inside
        // "left", which would make a naive substring check fail on correct output.
        for relative in GuidanceMagnitude.Relative.allCases {
            let text = formatter.text(for: cue(magnitude: .relative(relative)))
            let words = text.split(separator: " ").map(String.init)
            for unit in ["cm", "m", "in", "ft", "mm"] {
                #expect(!words.contains(unit), "unexpected unit \"\(unit)\" in \"\(text)\"")
            }
        }
    }

    @Test("Relative magnitude changes the wording, not the precision")
    func relativeMagnitudeChangesWording() {
        let slight = formatter.text(for: cue(magnitude: .relative(.slight)))
        let moderate = formatter.text(for: cue(magnitude: .relative(.moderate)))
        let large = formatter.text(for: cue(magnitude: .relative(.large)))

        #expect(slight == "Move left a little")
        #expect(moderate == "Move left")
        #expect(large == "Move left a lot")
    }

    @Test("A relative rotation produces no angle text")
    func relativeRotationHasNoAngle() {
        let text = formatter.rotationText(for: cue(
            magnitude: .relative(.moderate),
            rotation: .relative(.moderate)
        ))

        // The arrow carries direction; inventing a number here is the failure this
        // project exists to avoid.
        #expect(text == nil)
    }

    // MARK: Metric cues

    @Test("A metric cue under a metre renders in centimetres")
    func metricCueUnderOneMetre() {
        let text = formatter.text(for: cue(magnitude: .metric(meters: 0.4, confidence: 0.9)))
        #expect(text == "Move left 40 cm")
    }

    @Test("A metric cue over a metre renders in metres")
    func metricCueOverOneMetre() {
        // 2.4 rather than a value ending in 5: printf rounds half to even, so 1.25
        // renders as "1.2" and would make this test about rounding, not formatting.
        let text = formatter.text(for: cue(magnitude: .metric(meters: 2.4, confidence: 0.9)))
        #expect(text == "Move left 2.4 m")
    }

    @Test("Imperial units convert only at the formatter")
    func imperialConversion() {
        let imperial = GuidanceCueFormatter(units: .imperial)

        #expect(imperial
            .text(for: cue(magnitude: .metric(meters: 0.2, confidence: 1))) == "Move left 8 in")
        #expect(imperial
            .text(for: cue(magnitude: .metric(meters: 1.0, confidence: 1))) == "Move left 3.3 ft")
    }

    @Test("An exact rotation renders in degrees")
    func exactRotationRendersDegrees() {
        let text = formatter.rotationText(for: cue(
            axis: .rollLevel,
            magnitude: .relative(.moderate),
            rotation: .degrees(.degrees(-6), confidence: 0.95)
        ))

        #expect(text == "6°")
    }

    @Test("A rotation below half a degree is not worth saying")
    func negligibleRotationIsSilent() {
        let text = formatter.rotationText(for: cue(
            axis: .rollLevel,
            magnitude: .relative(.slight),
            rotation: .degrees(.degrees(0.2), confidence: 1)
        ))

        #expect(text == nil)
    }

    // MARK: Axis wording

    @Test("Every axis has wording a person can act on")
    func everyAxisHasWording() {
        let axes: [GuidanceAxis] = [
            .left, .right, .up, .down, .forward, .backward,
            .panLeft, .panRight, .tiltUp, .tiltDown, .rollLevel,
            .rotateBodyLeft, .rotateBodyRight, .focalLength,
        ]

        for axis in axes {
            let text = formatter.text(for: cue(axis: axis, magnitude: .relative(.moderate)))
            #expect(!text.isEmpty)
            #expect(text.first?.isUppercase == true, "\"\(text)\" should read as an instruction")
        }
    }

    @Test("Subject cues are phrased as something to say to a person")
    func subjectCuesArePhrasedForAHuman() {
        let text = formatter.text(for: GuidanceCue(
            actor: .subject,
            axis: .rotateBodyLeft,
            magnitude: .relative(.moderate),
            priority: 1
        ))

        #expect(text == "Turn your body left")
    }

    @Test("A focal length cue asks for a lens, not a distance to walk")
    func focalLengthCueIsALensRequest() {
        let text = formatter.text(for: GuidanceCue(
            actor: .camera,
            axis: .focalLength,
            magnitude: .metric(meters: 85, confidence: 1),
            priority: 1,
            manualRequest: true
        ))

        #expect(text == "Switch to 85 mm")
    }

    // MARK: Readiness

    @Test("Readiness reads as a state, and blocked shows the blocking instruction")
    func readinessText() {
        #expect(formatter.text(for: .ready) == "Ready")
        #expect(formatter.text(for: .close) == "Almost")
        #expect(formatter.text(for: .blocked(cue(magnitude: .relative(.moderate)))) == "Move left")
    }

    // MARK: Short form

    @Test("The short form of a relative cue is a symbol with no number")
    func shortRelativeFormHasNoNumber() {
        let text = formatter.shortText(for: cue(magnitude: .relative(.large)))
        let containsDigit = text.contains { $0.isNumber }
        #expect(!containsDigit)
        #expect(text.hasPrefix("←"))
    }
}
