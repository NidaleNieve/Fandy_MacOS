import SwiftUI
import AppKit
import FandyCore

/// Fixed content width bounds long user names and diagnostics without truncating them.
enum MenuLayout { static let width: CGFloat = 330; static let textWidth: CGFloat = 294 }
struct WrappedMenuText: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).frame(width: MenuLayout.textWidth, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 5) }
}
struct ProfileMenuRow: View {
    @Bindable var model: AppModel
    let profile: Profile
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark").opacity(model.menuSelectionID == profile.id ? 1 : 0).frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.frame(width: 294, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(MenuActionStyle()).disabled(!model.canActivate(profile) || model.activationDefaultUnavailableReason(profile) != nil).help(model.activationDefaultUnavailableReason(profile) ?? model.eligibility(profile).reason ?? profile.name)
    }
}
struct MenuActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { MenuActionLabel(configuration: configuration) }
    private struct MenuActionLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 13)).background(hovered || configuration.isPressed ? Color.accentColor.opacity(0.16) : .clear).onHover { hovered = $0 }
        }
    }
}
struct FanMenuStatus: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fans = model.snapshot?.fans, !fans.isEmpty, model.ownership != .unknown {
                let percentage = StatusPresentation.observedFanPercent(fans)
                ProgressView(value: percentage, total: 100).progressViewStyle(.linear).tint(.secondary)
                    .accessibilityLabel("Observed fan speed").accessibilityValue("\(Int(percentage.rounded())) percent")
                Text("\(Int(percentage.rounded()))% · " + fans.map { "\(Int($0.actualRPM.rounded()))" }.joined(separator: " / ") + " RPM").font(.caption).monospacedDigit()
            } else { Text("Fan speed unavailable").font(.caption).foregroundStyle(.secondary) }
            Text(model.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(width: MenuLayout.textWidth, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 8)
    }
}

struct TimeDial: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let editingMinutes: Bool
    let use24HourTime: Bool
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = min(size.width, size.height) / 2 - 3
            context.fill(Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)), with: .color(Color(nsColor: .controlBackgroundColor)))
            for n in 0..<12 {
                let angle = Double(n) * .pi / 6 - .pi / 2
                let label = editingMinutes ? String(format: "%02d", n*5) : use24HourTime ? String(n*2) : String(n == 0 ? 12 : n)
                context.draw(Text(label).font(.system(size: 12)), at: CGPoint(x: center.x + cos(angle)*(radius-17), y: center.y + sin(angle)*(radius-17)))
            }
            func hand(_ fraction: Double, length: Double, width: CGFloat, color: Color) {
                let angle = fraction * 2 * .pi - .pi / 2
                var p = Path(); p.move(to: center); p.addLine(to: CGPoint(x: center.x + cos(angle)*length, y: center.y + sin(angle)*length))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(Double(hour) / (use24HourTime ? 24 : 12) + Double(minute) / (use24HourTime ? 1440 : 720), length: radius*0.5, width: 3, color: editingMinutes ? .primary : .accentColor)
            hand(Double(minute)/60, length: radius*0.74, width: 2, color: editingMinutes ? .accentColor : .primary)
        }.frame(width: 155, height: 155).contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
            let angle = atan2(event.location.x - 77.5, 77.5 - event.location.y)
            let fraction = (angle + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi)
            if editingMinutes { minute = Int((fraction*60).rounded()) % 60 }
            else if use24HourTime { hour = Int((fraction*24).rounded()) % 24 }
            else { hour = (hour / 12)*12 + Int((fraction*12).rounded()) % 12 }
        }).accessibilityLabel("Clock; select a time by dragging the highlighted hand")
    }
}
