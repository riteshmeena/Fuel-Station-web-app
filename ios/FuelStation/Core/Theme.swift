import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum Theme {
    static let brand = Color(hex: 0xFF5B29)        // saffron-orange
    static let brandDeep = Color(hex: 0xE0311B)
    static let accent = Color(hex: 0x1FB57A)       // green for "up"/success
    static let danger = Color(hex: 0xE5484D)
    static let ink = Color(hex: 0x0E1324)
    static let night = Color(hex: 0x151B33)

    static let brandGradient = LinearGradient(colors: [Color(hex: 0xFF8A3D), brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let backdrop = LinearGradient(colors: [Color(hex: 0x0B1022), Color(hex: 0x1A1F3D), Color(hex: 0x2A1630)], startPoint: .top, endPoint: .bottom)

    static func tierGradient(_ tier: Tier) -> LinearGradient {
        switch tier {
        case .SILVER: LinearGradient(colors: [Color(hex: 0x3A4150), Color(hex: 0x8A93A6), Color(hex: 0x2B303B)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .GOLD: LinearGradient(colors: [Color(hex: 0x6B4A12), Color(hex: 0xE9B949), Color(hex: 0x8A5A12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .PLATINUM: LinearGradient(colors: [Color(hex: 0x10153A), Color(hex: 0x4B3FA8), Color(hex: 0x0E7C86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .SILVER: Color(hex: 0xA9B1C2)
        case .GOLD: Color(hex: 0xF2C14E)
        case .PLATINUM: Color(hex: 0x8C7CF0)
        }
    }

    static func fuelColor(_ f: FuelType) -> Color {
        switch f {
        case .PETROL: Color(hex: 0xFF7A2F)
        case .DIESEL: Color(hex: 0x2E9BFF)
        case .PREMIUM_PETROL: Color(hex: 0xC04BFF)
        case .CNG: Color(hex: 0x1FB57A)
        case .EV: Color(hex: 0x21C7D9)
        }
    }
}

/// Rounded "glass" surface used across the app.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, radius: CGFloat = 22) -> some View { modifier(GlassCard(padding: padding, radius: radius)) }

    /// Standard screen background: deep night gradient with soft brand glows.
    func screenBackground() -> some View {
        background {
            ZStack {
                Theme.backdrop
                Circle().fill(Theme.brand.opacity(0.35)).frame(width: 340).blur(radius: 120).offset(x: 160, y: -320)
                Circle().fill(Color(hex: 0x4B3FA8).opacity(0.35)).frame(width: 300).blur(radius: 120).offset(x: -170, y: 260)
            }
            .ignoresSafeArea()
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label.opacity(isLoading ? 0 : 1)
            if isLoading { ProgressView().tint(.white) }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Theme.brandGradient.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.brand.opacity(isEnabled ? 0.45 : 0), radius: 16, y: 8)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
    }
}
