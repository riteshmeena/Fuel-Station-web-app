import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var phone = ""
    @State private var pin = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showForgot = false

    private var valid: Bool { phone.filter(\.isNumber).count == 10 && pin.count == 4 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome back 👋").font(.largeTitle.weight(.heavy))
                    Text("Log in with your mobile number and PIN.").foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)

                FormField(label: "Mobile number", text: $phone, symbol: "phone.fill", keyboard: .phonePad, prefix: "+91")
                PinField(pin: $pin)

                if let error { ErrorBanner(message: error) }

                Button("Log in") { Task { await submit() } }
                    .buttonStyle(PrimaryButtonStyle(isLoading: loading))
                    .disabled(!valid || loading)

                Button("Forgot PIN?") { showForgot = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .alert("Forgot your PIN?", isPresented: $showForgot) {
            if let phone = session.station?.phone, let url = URL(string: "tel:\(phone)") {
                Button("Call station") { UIApplication.shared.open(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Visit the station counter with your mobile. The manager will verify you and set a new PIN — no SMS charges, no hassle.")
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        do {
            try await session.login(phone: phone, pin: pin)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            pin = ""
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
