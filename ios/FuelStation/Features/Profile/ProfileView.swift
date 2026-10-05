import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showEdit = false
    @State private var showPin = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(String(session.user?.name.prefix(1) ?? "?"))
                            .font(.title.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Theme.tierGradient(session.user?.tier ?? .SILVER), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.user?.name ?? "").font(.title3.weight(.bold))
                            Text(Fmt.phone(session.user?.phone ?? "")).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Label(session.user?.tier.title ?? "", systemImage: "crown.fill").foregroundStyle(Theme.tierColor(session.user?.tier ?? .SILVER))
                                if session.user?.status == .VERIFIED { Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                                if let role = session.user?.role, role != .CUSTOMER { Text(role.rawValue.capitalized).foregroundStyle(Theme.brand) }
                            }
                            .font(.caption.weight(.bold))
                        }
                        Spacer()
                        Button("Edit") { showEdit = true }.font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }

                Section("My stuff") {
                    link("My vehicles", "car.fill", .orange) { VehiclesView() }
                    link("Reminders", "bell.badge.fill", .purple) { RemindersView() }
                    link("Bookings", "calendar", .blue) { BookingsView() }
                    link("Notifications", "tray.full.fill", .pink) { NotificationsView() }
                    link("Refer & earn", "person.2.fill", .green) { ReferralView() }
                }

                Section("Station") {
                    link("Station info & directions", "map.fill", .teal) { StationView() }
                    link("Feedback & complaints", "star.bubble.fill", .yellow) { FeedbackView() }
                    link("Quality & quantity promise", "checkmark.shield.fill", .mint) { QualityPromiseView() }
                }

                Section("Security") {
                    Button { showPin = true } label: { row("Change PIN", "lock.fill", .gray) }
                }

                #if DEBUG
                Section("Developer") {
                    link("Server address", "server.rack", .gray) { ServerSettingsView() }
                }
                #endif

                Section {
                    Button(role: .destructive) { confirmLogout = true } label: { Label("Log out", systemImage: "rectangle.portrait.and.arrow.right") }
                } footer: {
                    Text("Member since \(session.user?.createdAt.formatted(.dateTime.month(.wide).year()) ?? "")").frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Profile")
            .sheet(isPresented: $showEdit) { EditProfileView() }
            .sheet(isPresented: $showPin) { ChangePinView() }
            .confirmationDialog("Log out?", isPresented: $confirmLogout) { Button("Log out", role: .destructive) { session.logout() } }
        }
    }

    private func row(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        Label {
            Text(title).foregroundStyle(.white)
        } icon: {
            Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ tint: Color, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: { row(title, symbol, tint) }
    }
}

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                FormField(label: "Full name", text: $name, symbol: "person.fill")
                FormField(label: "Email", text: $email, symbol: "envelope.fill", keyboard: .emailAddress, capitalization: .never)
                if let error { ErrorBanner(message: error) }
                Spacer()
                Button("Save") { Task { await save() } }.buttonStyle(PrimaryButtonStyle(isLoading: saving)).disabled(name.count < 2)
            }
            .padding(24)
            .screenBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                name = session.user?.name ?? ""
                email = session.user?.email ?? ""
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            struct R: Decodable { let user: User }
            let r: R = try await APIClient.shared.patch("/me", ["name": name, "email": email.isEmpty ? NSNull() as Any : email as Any])
            session.user = r.user
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ChangePinView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    PinField(pin: $current, label: "Current PIN")
                    PinField(pin: $new, label: "New PIN")
                    PinField(pin: $confirm, label: "Confirm new PIN")
                    if confirm.count == 4 && new != confirm { Text("PINs don't match").foregroundStyle(Theme.danger).font(.footnote) }
                    if let error { ErrorBanner(message: error) }
                    Text("Changing your PIN logs you out on all other devices.").font(.footnote).foregroundStyle(.white.opacity(0.6))
                    Button("Update PIN") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isLoading: saving))
                        .disabled(current.count != 4 || new.count != 4 || new != confirm)
                }
                .padding(24)
            }
            .screenBackground()
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.changePin(current: current, new: new)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ServerSettingsView: View {
    @State private var url = UserDefaults.standard.string(forKey: "apiBaseURL") ?? APIClient.shared.baseURL.absoluteString
    var body: some View {
        Form {
            Section(footer: Text("Use your Mac's LAN IP (e.g. http://192.168.1.5:4000/api/v1) when testing on a real iPhone.")) {
                TextField("API base URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            Button("Save") { UserDefaults.standard.set(url, forKey: "apiBaseURL") }
            Button("Reset to default", role: .destructive) { UserDefaults.standard.removeObject(forKey: "apiBaseURL"); url = APIClient.shared.baseURL.absoluteString }
        }
        .navigationTitle("Server")
    }
}

struct QualityPromiseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                promise("checkmark.seal.fill", "Right quantity, always", "Ask for a 5-litre measure check anytime. Our measures are certified by the Legal Metrology department.")
                promise("flask.fill", "Pure fuel", "Request a density check or a filter-paper test for petrol — it's your right, free of cost.")
                promise("gauge.with.needle.fill", "Zero before you fill", "Always check the dispenser shows 0.00 before fuelling starts.")
                promise("doc.text.fill", "Receipts for every fill", "Get a digital receipt in the app for every transaction linked to your card.")
                promise("phone.fill", "We listen", "Unhappy? Use Feedback in the app — the owner reads every complaint.")
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Our promise")
    }

    private func promise(_ s: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: s).font(.title2).foregroundStyle(Theme.accent).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(t).font(.headline).foregroundStyle(.white)
                Text(d).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
