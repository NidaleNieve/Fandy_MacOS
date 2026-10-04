import SwiftUI
import AppKit
import FandyCore

struct CurveEditor: View {
    let curve: FanCurve
    let resetRevision: UInt64
    let request: CurveRequestPreview
    let onChange: (FanCurve) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void
    let currentTemperature: Double?
    @State private var editor: CurveDraft
    @State private var dragging: UUID?
    @State private var dragRange: ClosedRange<Double>?
    init(curve: FanCurve, request: CurveRequestPreview = .init(), resetRevision: UInt64 = 0, currentTemperature: Double? = nil, onBegin: @escaping () -> Void = {}, onEnd: @escaping () -> Void = {}, onChange: @escaping (FanCurve) -> Void) {
        self.currentTemperature = currentTemperature; self.onBegin = onBegin; self.onEnd = onEnd;
        self.request = request; self.curve = curve; self.resetRevision = resetRevision; self.onChange = onChange; _editor = State(initialValue: CurveDraft(curve))
    }
    var range: ClosedRange<Double> { dragRange ?? request.range(for: editor.curve) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let plot = CGRect(x: 35, y: 12, width: max(1, geometry.size.width - 50), height: max(1, geometry.size.height - 43))
                Canvas { context, _ in
                    for percent in stride(from: 0, through: 100, by: 25) {
                        let y = plot.maxY - Double(percent) / 100 * plot.height
                        var grid = Path(); grid.move(to: CGPoint(x: plot.minX, y: y)); grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                        context.draw(Text("\(percent)%").font(.system(size: 10)).foregroundStyle(.secondary), at: CGPoint(x: plot.minX-5,y:y), anchor: .trailing)
                    }
                    let firstTick = Int(ceil(range.lowerBound / 10)) * 10
                    for temperature in stride(from: firstTick, through: Int(range.upperBound), by: 10) {
                        let x = coordinate(CurvePoint(Double(temperature),0), plot: plot).x
                        context.draw(Text("\(temperature)°").font(.system(size: 10)).foregroundStyle(.secondary), at: CGPoint(x: x, y: plot.maxY + 12))
                    }
                    if let temperature = currentTemperature, temperature.isFinite, range.contains(temperature) {
                        let x = coordinate(CurvePoint(temperature, 0), plot: plot).x
                        var marker = Path(); marker.move(to: CGPoint(x: x, y: plot.minY)); marker.addLine(to: CGPoint(x: x, y: plot.maxY))
                        context.stroke(marker, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3,3]))
                    }
                    var line = Path()
                    for (index, point) in editor.curve.points.enumerated() {
                        let location = coordinate(point, plot: plot)
                        if index == 0 { line.move(to: CGPoint(x: plot.minX, y: location.y)); line.addLine(to: location) } else { line.addLine(to: location) }
                    }
                    if let last = editor.curve.points.last { line.addLine(to: CGPoint(x: plot.maxX, y: coordinate(last, plot: plot).y)) }
                    let color = editor.validation == nil ? Color.accentColor : .red
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if request.hasOverlay(for: curve.input), editor.validation == nil {
                        var effective = Path()
                        for step in 0...128 {
                            let temperature = range.lowerBound + Double(step) / 128 * (range.upperBound - range.lowerBound)
                            guard let percent = try? request.percent(at: temperature, curve: editor.curve) else { continue }
                            let point = coordinate(CurvePoint(temperature, percent), plot: plot)
                            if step == 0 { effective.move(to: point) } else { effective.addLine(to: point) }
                        }
                        context.stroke(effective, with: .color(.primary), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        if let target = request.target, target.input == curve.input, target.celsius.isFinite {
                            let x = coordinate(CurvePoint(target.celsius, 0), plot: plot).x
                            var marker = Path(); marker.move(to: CGPoint(x: x, y: plot.minY)); marker.addLine(to: CGPoint(x: x, y: plot.maxY))
                            context.stroke(marker, with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            context.draw(Text("Target \(target.celsius, specifier: "%.1f")°").font(.system(size: 10)).foregroundStyle(.orange), at: CGPoint(x: min(plot.maxX - 40, max(plot.minX + 40, x)), y: plot.minY + 8))
                        }
                    }
                    for point in editor.curve.points {
                        let position = coordinate(point, plot: plot), radius: CGFloat = point.id == editor.selectedID ? 5.5 : 4
                        let rect = CGRect(x: position.x-radius,y:position.y-radius,width:radius*2,height:radius*2)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                .overlay {
                    CurveContextSurface { location in
                        let nearest = editor.curve.points.min { distance(coordinate($0, plot: plot), location) < distance(coordinate($1, plot: plot), location) }
                        if let nearest, distance(coordinate(nearest, plot: plot), location) < 16 {
                            return CurveContextAction(enabled: editor.curve.points.count > 2) { editor.select(nearest.id); publish(editor.remove()) }
                        }
                        let temperature = range.lowerBound + (location.x-plot.minX)/plot.width*(range.upperBound-range.lowerBound)
                        let percentage = (plot.maxY-location.y)/plot.height*100
                        return CurveContextAction(enabled: plot.contains(location) && editor.canAdd) { publish(editor.add(at: temperature, percent: percentage)) }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if dragging == nil {
                        let nearest = editor.curve.points.min { distance(coordinate($0,plot:plot),value.startLocation) < distance(coordinate($1,plot:plot),value.startLocation) }
                        if let nearest, distance(coordinate(nearest,plot:plot),value.startLocation) < 16 { onBegin(); dragging = nearest.id; dragRange = range; editor.select(nearest.id) }
                    }
                    guard dragging != nil else { return }
                    let temperature = range.lowerBound + (value.location.x - plot.minX) / plot.width * (range.upperBound - range.lowerBound)
                    let percent = (plot.maxY - value.location.y) / plot.height * 100
                    publish(editor.move(temperature: temperature, percent: percent, in: range))
                }.onEnded { _ in if dragging != nil { onEnd() }; dragging = nil; dragRange = nil })
                .focusable()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { key in
                    let step = key.modifiers.contains(.shift) ? 0.1 : 1.0
                    switch key.key {
                    case .leftArrow: publish(editor.nudge(temperature: -step))
                    case .rightArrow: publish(editor.nudge(temperature: step))
                    case .upArrow: publish(editor.nudge(percent: step))
                    case .downArrow: publish(editor.nudge(percent: -step))
                    default: return .ignored
                    }
                    return .handled
                }
                .accessibilityLabel("\(curve.input.label) fan curve; arrow keys edit the selected point")
                .accessibilityIdentifier("curve.\(curve.input.rawValue).graph")
            }.frame(height: 170)
            if request.hasOverlay(for: curve.input) {
                Text("Dashed: curve + minimum airflow\(request.target?.input == curve.input ? " + temperature target" : ""). Other inputs and chip safety may request more.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { publish(editor.add()) } label: { Image(systemName: "plus").frame(width: 16, height: 16) }
                    .disabled(!editor.canAdd).help("Add node").accessibilityLabel("Add curve point")
                Button { publish(editor.remove()) } label: { Image(systemName: "minus").frame(width: 16, height: 16) }
                    .disabled(!editor.canRemove).help("Remove selected node").accessibilityLabel("Remove curve point")
                Picker("Point", selection: Binding(get: { editor.selectedID }, set: { editor.select($0) })) {
                    Text("Select a point").tag(nil as UUID?)
                    ForEach(editor.curve.points) { point in
                        Text("\(point.temperature, specifier: "%.1f")°C · \(point.percent, specifier: "%.1f")%")
                            .tag(Optional(point.id))
                    }
                }.labelsHidden().frame(maxWidth: 175).accessibilityLabel("Curve point")
                Spacer(minLength: 0)
                TextField("Temperature", text: $editor.temperatureText).frame(width: 60).disabled(editor.selectedID == nil)
                    .onSubmit { publish(editor.applyNumbers()) }.accessibilityLabel("Point temperature in Celsius")
                    .accessibilityIdentifier("curve.\(curve.input.rawValue).temperature")
                Text("°C").foregroundStyle(.secondary)
                TextField("Fan speed", text: $editor.percentText).frame(width: 50).disabled(editor.selectedID == nil)
                    .onSubmit { publish(editor.applyNumbers()) }.accessibilityLabel("Point fan percentage")
                    .accessibilityIdentifier("curve.\(curve.input.rawValue).percent")
                Text("%").foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).buttonStyle(.bordered).controlSize(.small)
            if let validation = editor.validation { Text("Not applied: \(validation)").font(.caption).foregroundStyle(.red) }
        }
        .onDisappear { if dragging != nil { onEnd() }; dragging = nil; dragRange = nil }
        .onChange(of: curve) { _, new in if dragging == nil { editor.replace(with: new) } }
        .onChange(of: resetRevision) { _, _ in
            dragging = nil; dragRange = nil; editor.replace(with: curve)
        }
    }
    func coordinate(_ point: CurvePoint, plot: CGRect) -> CGPoint {
        guard point.temperature.isFinite, point.percent.isFinite else { return CGPoint(x:plot.minX,y:plot.maxY) }
        return CGPoint(x: plot.minX + min(1,max(0,(point.temperature-range.lowerBound)/(range.upperBound-range.lowerBound)))*plot.width, y:plot.maxY-min(100,max(0,point.percent))/100*plot.height)
    }
    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x,a.y-b.y) }
    private func publish(_ curve: FanCurve?) { if let curve { onChange(curve) } }
}
