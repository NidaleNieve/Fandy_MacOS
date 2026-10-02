import Foundation
import Testing
import FandyCore
@testable import FandyApp

@Test func curveResetRefreshesSelectedValuesEvenWhenNodeIdentityIsUnchanged() {
    let original = FanCurve(.chip, [(45, 10), (65, 30), (85, 100)])
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    var replacement = original
    replacement.points[1].temperature = 62.125; replacement.points[1].percent = 31.75
    editor.replace(with: replacement)
    #expect(editor.selectedID == replacement.points[1].id)
    #expect(Double(editor.temperatureText) == 62.125)
    #expect(Double(editor.percentText) == 31.75)
    editor.temperatureText = "45"
    #expect(editor.applyNumbers() == nil)
    // Explicit Reset must discard an invalid local draft even when the parent
    // retained its original value and therefore emits no curve-value change.
    editor.replace(with: original)
    #expect(editor.validation == nil); #expect(Double(editor.temperatureText) == 65)
    #expect(Double(editor.percentText) == 30)
    editor.replace(with: FanCurve(.chip, [(40, 0), (90, 100)]))
    #expect(editor.selectedID == nil); #expect(editor.temperatureText.isEmpty)
}

@Test func invalidNumericalDraftCannotPublishAndCanBeRepaired() throws {
    let original = FanCurve(.chip, [(45, 10), (65, 30), (85, 100)])
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    editor.temperatureText = "45"; editor.percentText = "25.5"
    #expect(editor.applyNumbers() == nil); #expect(editor.validation != nil)
    #expect(editor.curve.points[1].temperature == 45) // Invalid node remains visible.
    editor.temperatureText = " 55.25 "; editor.percentText = "25.5"
    let applied = editor.applyNumbers()
    let repaired = try #require(applied)
    try repaired.validate(); #expect(editor.validation == nil)
    #expect(repaired.points[1].temperature == 55.25); #expect(repaired.points[1].percent == 25.5)
}

@Test func numericalInputRejectsNonfinitePartialAndDescendingDemand() {
    let original = FanCurve(.chip, [(45, 10), (65, 30), (85, 100)])
    for text in ["NaN", "Infinity", "-inf", "1e999", "55abc", ""] {
        var editor = CurveDraft(original); editor.select(original.points[1].id)
        editor.temperatureText = text
        #expect(editor.applyNumbers() == nil); #expect(editor.curve == original)
    }
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    editor.percentText = "5"
    #expect(editor.applyNumbers() == nil)
    #expect(editor.validation != nil)
}

@Test func numericalEditorAcceptsDecimalCommaWithoutAcceptingTrailingJunk() throws {
    let original = FanCurve(.trackpad, [(25, 10), (30, 50), (40, 100)])
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    editor.temperatureText = "29,5"; editor.percentText = "45,25"
    let applied = editor.applyNumbers(locale: Locale(identifier: "de_DE"))
    let result = try #require(applied)
    #expect(result.points[1].temperature == 29.5); #expect(result.points[1].percent == 45.25)
    editor.percentText = "45,25%"
    #expect(editor.applyNumbers(locale: Locale(identifier: "de_DE")) == nil)
}

@Test func draggingCloselySpacedNodesPreservesOrderAndExactRoundTrip() throws {
    let original = FanCurve(.chip, [(55, 20), (55.04, 21), (55.08, 22)])
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    let dragged = editor.move(temperature: 100, percent: 100, in: editor.range)
    let moved = try #require(dragged)
    try moved.validate()
    #expect(moved.points[1].temperature > 55 && moved.points[1].temperature < 55.08)
    #expect(moved.points[1].percent == 22)
    #expect(editor.applyNumbers(locale: Locale(identifier: "en_US_POSIX")) == moved)
    let before = editor.curve
    #expect(editor.move(temperature: .nan, percent: 50, in: editor.range) == nil)
    #expect(editor.curve == before)
}

@Test func addingANodePreservesTheInterpolatedPolicy() throws {
    let original = FanCurve(.chip, [(40, 0), (50, 15), (80, 90), (85, 100)])
    var editor = CurveDraft(original)
    let inserted = editor.add()
    let augmented = try #require(inserted)
    #expect(augmented.points.count == original.points.count + 1)
    #expect(editor.selectedPoint != nil)
    for temperature in stride(from: 30.0, through: 100, by: 0.5) {
        #expect(abs(try augmented.evaluate(temperature) - original.evaluate(temperature)) < 0.000_001)
    }
}

@Test func nodeRemovalCanRepairAnInvalidDraftAndRetainsAUsefulSelection() throws {
    let original = FanCurve(.chip, [(45, 10), (65, 30), (85, 100)])
    var editor = CurveDraft(original); editor.select(original.points[1].id)
    editor.temperatureText = "45"
    #expect(editor.applyNumbers() == nil); #expect(!editor.canAdd)
    let removed = editor.remove()
    let repaired = try #require(removed)
    try repaired.validate(); #expect(editor.selectedPoint?.id == original.points[2].id)
    #expect(!editor.canRemove); #expect(editor.remove() == nil)
    var full = CurveDraft(FanCurve(.chip, (0..<32).map { (Double($0), Double($0)) }))
    #expect(full.add() == nil)
}

@Test func plotRangeIncludesAllFiniteDraftNodesAndNeverContractsBelowBaseline() {
    var curve = FanCurve(.trackpad, [(27, 20), (31, 40), (42, 100)])
    curve.points[1].temperature = 120
    let editor = CurveDraft(curve)
    #expect(editor.range == 20...120)
    #expect(CurveDraft(FanCurve(.chip, [(55, 20), (65, 40)])).range == 30...95)
}

@Test func displayedCandidateDoesNotBecomeControlQualifiedAndStaleValuesDisappear() {
    var reading = SensorReading(.cpuAverage, 48.25, at: 10, health: .unverified)
    #expect(StatusPresentation.temperature(reading, now: 11, estimate: true).contains("estimate"))
    #expect(throws: ControlError.sensorUnavailable(.cpuAverage)) { try reading.value(now: 11) }
    #expect(StatusPresentation.temperature(reading, now: 14) == "Unavailable")
    #expect(StatusPresentation.temperature(reading, now: 9) == "Unavailable")
    reading.health = .corrupt
    #expect(StatusPresentation.temperature(reading, now: 11) == "Unavailable")
    reading.health = .valid; reading.celsius = .nan
    #expect(StatusPresentation.temperature(reading, now: 11) == "Unavailable")
}

@Test func demandTextDistinguishesAcknowledgedActivationFromPreview() throws {
    let snapshot = HardwareSnapshot(at: 10, sensors: [SensorReading(.socPeak, 50, at: 10)],
        fans: [Fan(id: 0, min: 2000, max: 8000, actual: 0)])
    let preview = try ShadowProfileEngine.evaluate(BuiltInProfiles.systemPlus, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope)
    #expect(StatusPresentation.demand(preview, active: false).contains("no fan commands"))
    #expect(!StatusPresentation.demand(preview, active: true).contains("no fan commands"))
}
