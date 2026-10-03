import Foundation
import FandyCore

/// Editor-only state. Invalid drafts stay visible, but only validated curves leave it.
struct CurveDraft {
    private(set) var curve: FanCurve
    private(set) var selectedID: UUID?
    var temperatureText = ""
    var percentText = ""
    private(set) var validation: String?

    init(_ curve: FanCurve) { self.curve = curve }
    var selectedPoint: CurvePoint? { curve.points.first { $0.id == selectedID } }
    var canAdd: Bool { curve.points.count < 32 && (try? curve.validate()) != nil }
    var canRemove: Bool { selectedPoint != nil && curve.points.count > 2 }
    var range: ClosedRange<Double> {
        let baseline: ClosedRange<Double> = curve.input == .chip ? 30...95 : curve.input == .airflow ? 25...65 : 20...45
        let temperatures = curve.points.map(\.temperature).filter(\.isFinite).map { min(125, max(0, $0)) }
        return min(baseline.lowerBound, temperatures.min() ?? baseline.lowerBound)...max(baseline.upperBound, temperatures.max() ?? baseline.upperBound)
    }
    mutating func select(_ id: UUID?) {
        selectedID = curve.points.contains { $0.id == id } ? id : nil
        refreshFields()
    }
    mutating func replace(with curve: FanCurve) {
        self.curve = curve; validation = nil
        select(selectedID)
    }
    mutating func applyNumbers(locale: Locale = .current) -> FanCurve? {
        guard let index = selectedIndex,
              let temperature = Self.number(temperatureText, locale: locale),
              let percent = Self.number(percentText, locale: locale) else {
            validation = "Enter finite numerical values."; return nil
        }
        curve.points[index].temperature = temperature; curve.points[index].percent = percent
        return validated()
    }
    mutating func move(temperature: Double, percent: Double, in range: ClosedRange<Double>) -> FanCurve? {
        guard let index = selectedIndex, temperature.isFinite, percent.isFinite,
              range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        let previous = index > 0 ? curve.points[index - 1] : nil
        let next = index + 1 < curve.points.count ? curve.points[index + 1] : nil
        guard previous.map({ $0.temperature.isFinite && $0.percent.isFinite }) ?? true,
              next.map({ $0.temperature.isFinite && $0.percent.isFinite }) ?? true else { return nil }
        let gap = (next?.temperature ?? range.upperBound) - (previous?.temperature ?? range.lowerBound)
        guard gap > 0 else { return nil }
        // Small numerical gaps remain draggable without crossing or duplicating a neighbour.
        let spacing = min(0.1, gap / 3)
        let lower = previous.map { $0.temperature + spacing } ?? max(0, range.lowerBound)
        let upper = next.map { $0.temperature - spacing } ?? min(125, range.upperBound)
        let lowPercent = previous?.percent ?? 0, highPercent = next?.percent ?? 100
        guard lower <= upper, lowPercent <= highPercent else { return nil }
        curve.points[index].temperature = min(upper, max(lower, (temperature * 10).rounded() / 10))
        curve.points[index].percent = min(highPercent, max(lowPercent, percent.rounded()))
        refreshFields()
        return validated()
    }
    mutating func nudge(temperature: Double = 0, percent: Double = 0) -> FanCurve? {
        guard let point = selectedPoint else { return nil }
        temperatureText = Self.text(point.temperature + temperature)
        percentText = Self.text(point.percent + percent)
        return applyNumbers()
    }
    mutating func add() -> FanCurve? {
        guard canAdd, let index = (1..<curve.points.count).max(by: {
            curve.points[$0].temperature - curve.points[$0 - 1].temperature < curve.points[$1].temperature - curve.points[$1 - 1].temperature
        }) else { return nil }
        let a = curve.points[index - 1], b = curve.points[index]
        let node = CurvePoint((a.temperature + b.temperature) / 2, (a.percent + b.percent) / 2)
        curve.points.insert(node, at: index); select(node.id)
        return validated()
    }
    mutating func remove() -> FanCurve? {
        guard canRemove, let index = selectedIndex else { return nil }
        curve.points.remove(at: index)
        select(curve.points[min(index, curve.points.count - 1)].id)
        return validated()
    }
    private var selectedIndex: Int? { curve.points.firstIndex { $0.id == selectedID } }
    private mutating func refreshFields() {
        temperatureText = selectedPoint.map { Self.text($0.temperature) } ?? ""
        percentText = selectedPoint.map { Self.text($0.percent) } ?? ""
    }
    private mutating func validated() -> FanCurve? {
        do { try curve.validate(); validation = nil; return curve }
        catch { validation = error.localizedDescription; return nil }
    }
    private static func text(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }
    private static func number(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = locale.decimalSeparator.map { trimmed.replacingOccurrences(of: $0, with: ".") } ?? trimmed
        return Double(normalized).flatMap { $0.isFinite ? $0 : nil }
    }
}
