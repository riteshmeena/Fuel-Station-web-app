import SwiftUI

/// The hero loyalty card: tier-coloured, with a moving sheen, tilt and tap-to-flip to the QR side.
struct FuelCardView: View {
    let user: User
    var stationName: String = "Fuel Station"
    var brand: String = ""
    @State private var flipped = false
    @State private var sheen = false

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: Theme.tierColor(user.tier).opacity(0.35), radius: 24, y: 14)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { flipped.toggle() }
        }
        .onAppear { withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) { sheen = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.tier.title) fuel card, \(user.points) points. Double tap to show QR code.")
    }

    private var shape: some InsettableShape { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    private var cardBase: some View {
        shape
            .fill(Theme.tierGradient(user.tier))
            .overlay {
                // Decorative fuel-drop pattern + light sweep.
                GeometryReader { geo in
                    ZStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: geo.size.width * 0.75))
                            .foregroundStyle(.white.opacity(0.06))
                            .rotationEffect(.degrees(-18))
                            .offset(x: geo.size.width * 0.38, y: geo.size.height * 0.1)
                        LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.35)
                            .rotationEffect(.degrees(20))
                            .offset(x: sheen ? geo.size.width * 1.2 : -geo.size.width * 0.8)
                            .blendMode(.plusLighter)
                    }
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }

    private var front: some View {
        cardBase.overlay {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stationName).font(.headline.weight(.heavy))
                        if !brand.isEmpty { Text(brand.uppercased()).font(.caption2.weight(.bold)).opacity(0.75).tracking(2) }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                        Text(user.tier.title.uppercased()).tracking(1.5)
                    }
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.25), in: Capsule())
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.points(user.points)).font(.system(size: 40, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    Text("pts").font(.headline).opacity(0.8)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.cardNumber).font(.system(.callout, design: .monospaced).weight(.semibold)).tracking(2)
                        Text(user.name.uppercased()).font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    Spacer()
                    if user.status == .VERIFIED {
                        Image(systemName: "qrcode").font(.title2)
                    } else {
                        Label("Pending", systemImage: "hourglass").font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.3), in: Capsule())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
    }

    private var back: some View {
        cardBase.overlay {
            HStack(spacing: 16) {
                QRCodeView(text: user.qrPayload)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan at pump").font(.headline)
                    Text("Show this to the attendant to earn points on every fill-up.").font(.caption).opacity(0.85)
                    Spacer()
                    Text(user.cardNumber).font(.system(.caption, design: .monospaced).weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .padding(18)
        }
    }
}
