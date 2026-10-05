import SwiftUI

struct RegisterView: View {
    @Environment(SessionStore.self) private var session
    @State private var step = 0
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var regNumber = ""
    @State private var fuel: FuelType = .PETROL
    @State private var referral = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var loading = false
    @State private var error: String?

    private var stepValid: Bool {
        switch step {
        case 0: name.trimmingCharacters(in: .whitespaces).count >= 2 && phone.filter(\.isNumber).count == 10
        case 1: true
        default: pin.count == 4 && pin == confirmPin
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.horizontal, 24).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Group {
                        switch step {
                        case 0: details
                        case 1: vehicle
                        default: security
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    if let error { ErrorBanner(message: error) }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: 12) {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }.buttonStyle(SecondaryButtonStyle())
                }
                Button(step == 2 ? "Create account" : "Continue") {
                    if step < 2 { withAnimation(.spring) { step += 1 } } else { Task { await submit() } }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: loading))
                .disabled(!stepValid || loading)
            }
            .padding(24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule().fill(i <= step ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.15))).frame(height: 5)
            }
        }
        .animation(.spring, value: step)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(["About you", "Your vehicle", "Secure your card"][step]).font(.largeTitle.weight(.heavy))
            Text(["No OTP needed — the station will verify you.", "Add it now for faster fill-ups (optional).", "Choose a 4-digit PIN to log in."][step])
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
    }

    private var details: some View {
        VStack(spacing: 16) {
            FormField(label: "Full name", text: $name, symbol: "person.fill")
            FormField(label: "Mobile number", text: $phone, symbol: "phone.fill", keyboard: .phonePad, prefix: "+91")
            FormField(label: "Email (optional)", text: $email, symbol: "envelope.fill", keyboard: .emailAddress, capitalization: .never)
            FormField(label: "Referral code (optional)", text: $referral, symbol: "gift.fill", capitalization: .characters)
        }
    }

    private var vehicle: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormField(label: "Vehicle number", text: $regNumber, symbol: "car.fill", capitalization: .characters)
            Text("Fuel type").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                ForEach(FuelType.allCases) { f in
                    Button { fuel = f } label: {
                        VStack(spacing: 6) {
                            Image(systemName: f.symbol).font(.title3)
                            Text(f.title).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(fuel == f ? AnyShapeStyle(Theme.fuelColor(f).gradient) : AnyShapeStyle(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var security: some View {
        VStack(spacing: 20) {
            PinField(pin: $pin, label: "Create PIN")
            PinField(pin: $confirmPin, label: "Confirm PIN")
            if confirmPin.count == 4 && pin != confirmPin {
                Text("PINs don't match").font(.footnote.weight(.semibold)).foregroundStyle(Theme.danger)
            }
            Label("After sign-up, the station admin verifies your account. Your card activates once verified.", systemImage: "checkmark.shield.fill")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                .glassCard(padding: 14, radius: 14)
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            try await session.register(
                name: name.trimmingCharacters(in: .whitespaces), phone: phone, pin: pin,
                email: email.trimmingCharacters(in: .whitespaces), referral: referral,
                vehicle: regNumber.isEmpty ? nil : (regNumber, fuel)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let e as APIError {
            error = e.message
            if ["PHONE_TAKEN", "EMAIL_TAKEN", "BAD_REFERRAL"].contains(e.code) { withAnimation { step = 0 } }
            if e.message.hasPrefix("vehicle") { withAnimation { step = 1 } }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
