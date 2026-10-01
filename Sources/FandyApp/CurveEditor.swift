import SwiftUI
import FandyCore

struct CurveEditor: View {
    let curve: FanCurve
    let onChange: (FanCurve) -> Void
    @State private var draft: FanCurve
    @State private var selected: UUID?
    @State private var dragging: UUID?
    @State private var temperatureText = ""
    @State private var percentText = ""
    @State private var validation: String?
    init(curve: FanCurve, onChange: @escaping (FanCurve) -> Void) {
        self.curve = curve; self.onChange = onChange; _draft = State(initialValue: curve)
    }
    var range: ClosedRange<Double> {
        let baseline: ClosedRange<Double> = curve.input == .chip ? 30...95 : curve.input == .airflow ? 25...65 : 20...45
        let first = draft.points.first?.temperature ?? baseline.lowerBound
        let last = draft.points.last?.temperature ?? baseline.upperBound
        return min(baseline.lowerBound, max(0, min(125, first)))...max(baseline.upperBound, max(0, min(125, last)))
    }
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
                    var line = Path()
                    for (index, point) in draft.points.enumerated() {
                        let location = coordinate(point, plot: plot)
                        if index == 0 { line.move(to: location) } else { line.addLine(to: location) }
                    }
                    let color = validation == nil ? Color.accentColor : .red
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    for point in draft.points {
                        let position = coordinate(point, plot: plot), radius: CGFloat = point.id == selected ? 5.5 : 4
                        let rect = CGRect(x: position.x-radius,y:position.y-radius,width:radius*2,height:radius*2)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if dragging == nil {
                        let nearest = draft.points.min { distance(coordinate($0,plot:plot),value.startLocation) < distance(coordinate($1,plot:plot),value.startLocation) }
                        if let nearest, distance(coordinate(nearest,plot:plot),value.startLocation) < 16 { dragging = nearest.id; select(nearest) }
                    }
                    guard let id = dragging, let index = draft.points.firstIndex(where: { $0.id == id }) else { return }
                    let lower = index > 0 ? draft.points[index-1].temperature + 0.1 : range.lowerBound
                    let upper = index+1 < draft.points.count ? draft.points[index+1].temperature - 0.1 : range.upperBound
                    let rawTemperature = range.lowerBound + (value.location.x - plot.minX) / plot.width * (range.upperBound-range.lowerBound)
                    let lowPercent = index > 0 ? draft.points[index-1].percent : 0
                    let highPercent = index+1 < draft.points.count ? draft.points[index+1].percent : 100
                    draft.points[index].temperature = min(upper,max(lower,(rawTemperature*10).rounded()/10))
                    draft.points[index].percent = min(highPercent,max(lowPercent,((plot.maxY-value.location.y)/plot.height*100).rounded()))
                    select(draft.points[index]); commit()
                }.onEnded { _ in dragging = nil })
                .accessibilityLabel("\(curve.input.label) fan curve")
                .accessibilityIdentifier("curve.\(curve.input.rawValue).graph")
            }.frame(height: 170)
            HStack(spacing: 8) {
                Button { addNode() } label: { Image(systemName: "plus") }.disabled(draft.points.count >= 32).help("Add node")
                Button { removeNode() } label: { Image(systemName: "minus") }.disabled(selected == nil || draft.points.count <= 2).help("Remove selected node")
                Spacer()
                TextField("°C", text: $temperatureText).frame(width: 55).disabled(selected == nil).onSubmit { numericChange() }
                    .accessibilityIdentifier("curve.\(curve.input.rawValue).temperature")
                Text("°C").foregroundStyle(.secondary)
                TextField("%", text: $percentText).frame(width: 45).disabled(selected == nil).onSubmit { numericChange() }
                    .accessibilityIdentifier("curve.\(curve.input.rawValue).percent")
                Text("%").foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: curve) { _, new in if dragging == nil {
            draft = new; validation = nil
            if let selected, !new.points.contains(where: { $0.id == selected }) { self.selected = nil; temperatureText = ""; percentText = "" }
        } }
    }
    func coordinate(_ point: CurvePoint, plot: CGRect) -> CGPoint {
        guard point.temperature.isFinite, point.percent.isFinite else { return CGPoint(x:plot.minX,y:plot.maxY) }
        return CGPoint(x: plot.minX + min(1,max(0,(point.temperature-range.lowerBound)/(range.upperBound-range.lowerBound)))*plot.width, y:plot.maxY-min(100,max(0,point.percent))/100*plot.height)
    }
    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x,a.y-b.y) }
    func select(_ point: CurvePoint) { selected = point.id; temperatureText = String(format:"%.1f",point.temperature); percentText = String(format:"%.0f",point.percent) }
    func commit() {
        do { try draft.validate(); validation = nil; onChange(draft) } catch { validation = error.localizedDescription }
    }
    func numericChange() {
        guard let selected, let index = draft.points.firstIndex(where: { $0.id == selected }),
              let temperature = Double(temperatureText), let percent = Double(percentText), temperature.isFinite, percent.isFinite else { validation = "Enter finite numerical values."; return }
        draft.points[index].temperature = temperature; draft.points[index].percent = percent; commit()
    }
    func addNode() {
        guard draft.points.count < 32, (try? draft.validate()) != nil else { return }
        let index = (1..<draft.points.count).max { draft.points[$0].temperature-draft.points[$0-1].temperature < draft.points[$1].temperature-draft.points[$1-1].temperature }!
        let a=draft.points[index-1], b=draft.points[index]
        let node=CurvePoint((a.temperature+b.temperature)/2,(a.percent+b.percent)/2)
        draft.points.insert(node,at:index); select(node); commit()
    }
    func removeNode() { guard let selected, draft.points.count > 2 else { return }; draft.points.removeAll { $0.id == selected }; self.selected=nil; temperatureText=""; percentText=""; commit() }
}
