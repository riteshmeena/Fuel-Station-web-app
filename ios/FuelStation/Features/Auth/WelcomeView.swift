import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showLogin = false
    @State private var showRegister = false
    @State private var appear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                demoCard
                    .padding(.horizontal, 28)
                    .rotation3DEffect(.degrees(appear ? -8 : 25), axis: (x: 1, y: -0.4, z: 0))
                    .offset(y: appear ? 0 : 40)
                    .opacity(appear ? 1 : 0)
                Spacer(minLength: 24)
                VStack(spacing: 10) {
                    Text(session.station?.name ?? "Fuel Station")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("Earn points on every litre. Unlock free washes, fuel vouchers and more.")
                        .font(.body).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)

                if !session.prices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) { ForEach(session.prices) { PriceTile(price: $0) } }.padding(.horizontal, 24)
                    }
                    .padding(.top, 24)
                }

                VStack(spacing: 12) {
                    Button("Create free account") { showRegister = true }.buttonStyle(PrimaryButtonStyle())
                    Button { showLogin = true } label: {
                        Text("I already have an account").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .padding(24)
            }
            .screenBackground()
            .navigationDestination(isPresented: $showLogin) { LoginView() }
            .navigationDestination(isPresented: $showRegister) { RegisterView() }
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1)) { appear = true } }
        }
    }

    private var demoCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.tierGradient(.GOLD))
            .aspectRatio(1.586, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading) {
                    Label("FUEL CARD", systemImage: "fuelpump.fill").font(.caption.weight(.heavy)).tracking(2)
                    Spacer()
                    Text("1,250 pts").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("GOLD MEMBER").font(.caption.weight(.bold)).tracking(2).opacity(0.8)
                }
                .foregroundStyle(.white).padding(22)
            }
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.3)))
            .shadow(color: Theme.tierColor(.GOLD).opacity(0.4), radius: 30, y: 20)
    }
}
