import SwiftUI

/// Full-screen scannable card: big QR + barcode, screen brightness boosted for pump scanners.
struct CardDetailView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Text("Show at the pump").font(.title2.weight(.heavy)).foregroundStyle(.white)
            if user.status != .VERIFIED {
                Label("Card activates after admin verification", systemImage: "hourglass").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
            }
            VStack(spacing: 18) {
                QRCodeView(text: user.qrPayload).frame(width: 230, height: 230)
                BarcodeView(text: user.qrPayload).frame(height: 70)
                Text(user.cardNumber).font(.system(.title3, design: .monospaced).weight(.bold)).tracking(3)
                Text(user.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.black)
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Theme.tierColor(user.tier).opacity(0.5), radius: 30)
            HStack(spacing: 24) {
                Label("\(Fmt.points(user.points)) pts", systemImage: "star.fill")
                Label(user.tier.title, systemImage: "crown.fill").foregroundStyle(Theme.tierColor(user.tier))
            }
            .font(.headline).foregroundStyle(.white)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .screenBackground()
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear { UIScreen.main.brightness = previousBrightness }
        .presentationDragIndicator(.hidden)
    }
}
