import SwiftUI

enum Design {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let n = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
        })
    }
    static let primary = adaptive(0xB4553F, 0xD8735C)
    static let light = adaptive(0xD9937F, 0xB96F5B)
    static let pale = adaptive(0xF1DCD3, 0x624039)
    static let faint = adaptive(0xF8ECE6, 0x3A2B26)
    static let background = adaptive(0xF7F3EE, 0x1C1917)
    static let card = adaptive(0xFFFFFF, 0x26221F)
    static let line = adaptive(0xE8E1D9, 0x493F38)
    static let ink = adaptive(0x24201D, 0xF3EDE7)
    static let secondary = adaptive(0x6E6660, 0xC0B6AC)
    static let tertiary = adaptive(0xA39A92, 0xA49A91)
    static let baseRing = adaptive(0xEFE9E2, 0x3F3731)
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, design: .default).weight(.semibold)).foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54).background(Design.primary.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium)).foregroundStyle(Design.ink).frame(maxWidth: .infinity, minHeight: 50)
            .background(Design.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Design.line, lineWidth: 1)).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View { content.padding(18).background(Design.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Design.line, lineWidth: 1)) }
}
extension View { func card() -> some View { modifier(CardModifier()) } }
struct Disclaimer: View {
    var body: some View { Text(L.disclaimer).font(.system(size: 11)).foregroundStyle(Design.tertiary).multilineTextAlignment(.center).padding(.vertical, 12).accessibilityIdentifier("disclaimer") }
}
struct Chip: View {
    let title: String
    let selected: Bool
    let id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.subheadline).padding(.horizontal, 11).padding(.vertical, 7).foregroundStyle(selected ? Design.primary : Design.secondary).background(selected ? Design.faint : Design.card, in: Capsule()).overlay(Capsule().stroke(selected ? Design.primary : Design.line, lineWidth: 1)) }
            .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct SheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { content().background(Design.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("完成")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
        }.tint(Design.primary).presentationDragIndicator(.visible).overlay { PrivacyShield() }
    }
}
struct PrivacyShield: View {
    @EnvironmentObject private var lock: LockManager
    var body: some View {
        if lock.covered || lock.locked {
            ZStack {
                Design.background.ignoresSafeArea()
                if lock.locked {
                    Button(L.t("解锁")) { Task { await lock.unlock() } }.buttonStyle(PrimaryButtonStyle()).padding(40).accessibilityIdentifier("unlockSheet")
                }
            }
        }
    }
}
struct Legend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { entries }
            VStack(alignment: .leading, spacing: 8) { entries }
        }.font(.caption).foregroundStyle(Design.secondary)
    }
    @ViewBuilder private var entries: some View {
        Label { Text(L.t("经期")) } icon: { Circle().fill(Design.primary).frame(width: 9, height: 9) }
        Label { Text(L.t("预测")) } icon: { Circle().stroke(Design.primary, style: StrokeStyle(lineWidth: 1, dash: [2])).frame(width: 9, height: 9) }
        Label { Text(L.t("易孕期")) } icon: { Circle().fill(Design.pale).frame(width: 9, height: 9) }
    }
}
struct CycleRing: View {
    var cycleDays: Int
    var periodDays: Int
    var currentDay: Int
    var ovulationDay: Int
    var body: some View {
        Canvas { context, size in
            let count = max(15, min(90, cycleDays))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 12
            let step = 360.0 / Double(count)
            for i in 0..<count {
                let day = i + 1
                var color = Design.baseRing
                if day <= periodDays { color = Design.primary }
                else if (ovulationDay - 5...ovulationDay + 1).contains(day) { color = Design.pale }
                if day == ovulationDay { color = Design.light }
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .degrees(-90 + Double(i) * step + 1.1), endAngle: .degrees(-90 + Double(i + 1) * step - 1.1), clockwise: false)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            }
            let angle = (Double((max(1, currentDay) - 1) % count) + 0.5) * step * .pi / 180 - .pi / 2
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            let marker = Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
            context.fill(marker, with: .color(Design.card)); context.stroke(marker, with: .color(Design.ink), lineWidth: 3)
        }.accessibilityHidden(true)
    }
}
