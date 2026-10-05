import SwiftUI

@main
struct FuelStationApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Theme.brand)
                .task { await session.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                SplashView().transition(.opacity)
            case .loggedOut:
                WelcomeView().transition(.move(edge: .bottom).combined(with: .opacity))
            case .loggedIn:
                if let user = session.user, user.status == .PENDING, user.role == .CUSTOMER {
                    PendingVerificationView().transition(.opacity)
                } else {
                    MainTabView().transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        .animation(.easeInOut, value: session.user?.status)
    }
}

struct SplashView: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brandGradient)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulse)
            ProgressView().tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear { pulse = true }
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }
            RewardsView().tabItem { Label("Rewards", systemImage: "gift.fill") }
            if session.user?.role.isStaff == true {
                StaffHomeView().tabItem { Label("Pump", systemImage: "qrcode.viewfinder") }
            }
            if session.user?.role.isAdmin == true {
                AdminHomeView().tabItem { Label("Admin", systemImage: "chart.bar.xaxis") }
            }
            ActivityView().tabItem { Label("Activity", systemImage: "chart.line.uptrend.xyaxis") }
            ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }
}
