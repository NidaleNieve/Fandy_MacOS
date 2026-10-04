import SwiftUI
import AppKit
import FandyCore

/// Native action rows size themselves. Only readouts use a bounded custom view.
enum MenuLayout {
    static let width: CGFloat = 224
    static let textWidth: CGFloat = 140
    static let nativeTitleWidth: CGFloat = textWidth
    // AppKit reserves its own state/key-equivalent columns outside custom views.
    static let maximumMenuWidth: CGFloat = 256
    static func titleWidth(_ title: String) -> CGFloat { (title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width }
    /// Native menu rows retain native highlighting. Long names are shortened,
    /// with the complete action retained in the tooltip and accessibility label.
    static func compactTitle(_ title: String) -> String {
        guard titleWidth(title) > nativeTitleWidth else { return title }
        var result = title
        while !result.isEmpty && titleWidth(result + "…") > nativeTitleWidth { result.removeLast() }
        return result + "…"
    }
}
struct WrappedMenuText: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).frame(width: MenuLayout.textWidth, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 3) }
}
struct FanSpeedReadout: View {
    @Bindable var model: AppModel
    var centered = false
    var respectsMenuPreferences = false
    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            if let fans = model.snapshot?.fans, !fans.isEmpty, model.ownership != .unknown {
                let percentage = StatusPresentation.observedFanPercent(fans)
                if !respectsMenuPreferences || model.automation.preferences.showFanSpeedBar {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule().fill(Color.secondary).frame(width: geometry.size.width * percentage / 100)
                    }
                }.frame(width: 120, height: 3)
                .accessibilityLabel("Observed fan speed").accessibilityValue("\(Int(percentage.rounded())) percent")
                }
                if !respectsMenuPreferences || model.automation.preferences.showFanSpeedNumbers {
                Text("\(Int(percentage.rounded()))% · " + fans.map { "\(Int($0.actualRPM.rounded()))" }.joined(separator: " / ") + " RPM").font(.caption).monospacedDigit()
                }
            } else if !respectsMenuPreferences || model.automation.preferences.showFanSpeedBar || model.automation.preferences.showFanSpeedNumbers { Text("Fan speed unavailable").font(.caption).foregroundStyle(.secondary) }
        }.multilineTextAlignment(centered ? .center : .leading)
    }
}
struct FanMenuStatus: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            FanSpeedReadout(model: model, centered: true, respectsMenuPreferences: true)
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ForEach(model.automation.preferences.menuSensors, id: \.self) { id in
                Text(model.sensorMenu.title(for: id) + " · " + model.sensorMenu.valueText(for: id))
                    .font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(width: MenuLayout.textWidth).frame(maxWidth: .infinity)
            .padding(.horizontal, 14).padding(.vertical, 5)
    }
}

struct WrappedMenuAction: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .frame(width: MenuLayout.textWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 5)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(hovered ? Color.white : Color.primary)
            .background(hovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }.padding(.horizontal, 4).padding(.vertical, 2)
            .frame(maxWidth: .infinity).accessibilityLabel(title)
    }
}
