import SwiftUI

struct PendingVerificationView: View {
    @Environment(SessionStore.self) private var session
    @State private var checking = false
    @State private var spin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let user = session.user {
                    FuelCardView(user: user, stationName: session.station?.name ?? "Fuel Station", brand: session.station?.brand ?? "")
                        .padding(.top, 24)
                        .saturation(0.4)
                }
                ZStack {
                    Circle().stroke(Theme.brand.opacity(0.2), lineWidth: 6).frame(width: 90)
                    Circle().trim(from: 0, to: 0.3).stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 90)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                    Image(systemName: "hourglass").font(.title).foregroundStyle(.white)
                }
                .onAppear { spin = true }

                VStack(spacing: 10) {
                    Text("Verification pending").font(.title.weight(.heavy)).foregroundStyle(.white)
                    Text("Hi \(session.user?.firstName ?? "there")! Your account is created. The station admin will verify it shortly — or show this screen at the counter on your next visit.")
                        .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 14) {
                    step("checkmark.circle.fill", "Account created", done: true)
                    step("person.badge.shield.checkmark.fill", "Admin verifies your details", done: false)
                    step("star.circle.fill", "Card activates + welcome bonus", done: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                Button("Check status") { Task { await check() } }
                    .buttonStyle(PrimaryButtonStyle(isLoading: checking))
                if let phone = session.station?.phone, let url = URL(string: "tel:\(phone)") {
                    Link(destination: url) { Label("Call station", systemImage: "phone.fill") }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Log out", role: .destructive) { session.logout() }.font(.footnote)
            }
            .padding(24)
        }
        .screenBackground()
        .refreshable { await check() }
        .task {
            // Gentle background polling while the user waits on this screen.
            while !Task.isCancelled, session.user?.status == .PENDING {
                try? await Task.sleep(for: .seconds(30))
                try? await session.refreshMe()
            }
        }
    }

    private func step(_ symbol: String, _ text: String, done: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done ? Theme.accent : .white.opacity(0.6))
    }

    private func check() async {
        checking = true
        try? await session.refreshMe()
        checking = false
    }
}
