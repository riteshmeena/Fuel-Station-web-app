import SwiftUI

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction).font(.subheadline.weight(.semibold)).tint(Theme.brand)
            }
        }
    }
}

struct PriceTile: View {
    let price: FuelPrice
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: price.fuelType.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.fuelColor(price.fuelType).gradient, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                ChangeBadge(change: price.change)
            }
            Text(price.fuelType.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Fmt.rupees(price.price)).font(.title3.weight(.heavy)).foregroundStyle(.white)
                Text("/\(price.unit)").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 150, alignment: .leading)
        .glassCard(padding: 14, radius: 20)
    }
}

struct ChangeBadge: View {
    let change: Double
    var body: some View {
        if change == 0 {
            Text("—").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.5))
        } else {
            // In fuel, a price *drop* is good news for the customer → green.
            let up = change > 0
            Label(String(format: "%.2f", abs(change)), systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundStyle(up ? Theme.danger : Theme.accent)
                .background((up ? Theme.danger : Theme.accent).opacity(0.15), in: Capsule())
        }
    }
}

struct StatPill: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = Theme.brand
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.headline).foregroundStyle(tint)
            Text(value).font(.headline.weight(.heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14, radius: 18)
    }
}

struct QuickAction: View {
    let title: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: tint.opacity(0.5), radius: 10, y: 6)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Theme.brandGradient)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.footnote).foregroundStyle(.white)
            Spacer()
            if let retry { Button("Retry", action: retry).font(.footnote.weight(.bold)).tint(Theme.brand) }
        }
        .glassCard(padding: 12, radius: 14)
    }
}

struct TransactionRow: View {
    let tx: Transaction
    var showCustomer = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.fuelType.symbol)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.fuelColor(tx.fuelType).gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(showCustomer ? (tx.user?.name ?? tx.fuelType.title) : "\(tx.fuelType.title) • \(Fmt.number(tx.quantity)) \(tx.fuelType.unit)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text([tx.vehicle?.regNumber, tx.createdAt.dayMonthYearTime].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.rupees(tx.amount)).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                if tx.pointsEarned > 0 {
                    Text("+\(tx.pointsEarned) pts").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// Large-digit 4-PIN entry with dots, backed by a hidden number-pad field.
struct PinField: View {
    @Binding var pin: String
    var label: String = "4-digit PIN"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            ZStack {
                TextField("", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .onChange(of: pin) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(4))
                        if digits != new { pin = digits }
                    }
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        let filled = i < pin.count
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused && i == pin.count ? Theme.brand : .white.opacity(0.12), lineWidth: 1.5))
                            .overlay(Circle().fill(.white).frame(width: 14).scaleEffect(filled ? 1 : 0.01).animation(.spring(response: 0.25), value: filled))
                            .frame(height: 56)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }
        }
    }
}

struct FormField: View {
    let label: String
    @Binding var text: String
    var symbol: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .words
    var prefix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.white.opacity(0.5)).frame(width: 20)
                if let prefix { Text(prefix).foregroundStyle(.white.opacity(0.8)).font(.body.weight(.semibold)) }
                TextField("", text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Theme.night.opacity(0.95), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                    .shadow(radius: 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring, value: message.wrappedValue)
    }
}
