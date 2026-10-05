import SwiftUI
import Charts

struct AdminHomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var stats: Analytics?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error { ErrorBanner(message: error) { Task { await load() } } }
                    if let s = stats {
                        if s.pendingVerifications > 0 {
                            NavigationLink { ApprovalsView() } label: {
                                HStack {
                                    Image(systemName: "person.badge.clock.fill").font(.title2)
                                    VStack(alignment: .leading) {
                                        Text("\(s.pendingVerifications) customers waiting").font(.headline)
                                        Text("Tap to review & verify").font(.caption).opacity(0.85)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .foregroundStyle(.white)
                                .padding(18)
                                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            StatPill(title: "Today's sales", value: Fmt.rupeesShort(s.today.sales), symbol: "indianrupeesign.circle.fill")
                            StatPill(title: "Today's fill-ups", value: "\(s.today.count)", symbol: "fuelpump.fill", tint: Color(hex: 0x2E9BFF))
                            StatPill(title: "Members", value: "\(s.members)", symbol: "person.3.fill", tint: Theme.accent)
                            StatPill(title: "New (30d)", value: "+\(s.newMembers)", symbol: "person.badge.plus", tint: Color(hex: 0xC04BFF))
                        }
                        if !s.dailySales.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sales • last \(s.period.days) days").font(.headline).foregroundStyle(.white)
                                Text(Fmt.rupees(s.period.sales)).font(.title.weight(.heavy)).foregroundStyle(.white)
                                Chart(s.dailySales) { d in
                                    AreaMark(x: .value("Day", d.date), y: .value("Sales", d.sales))
                                        .foregroundStyle(LinearGradient(colors: [Theme.brand.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                                        .interpolationMethod(.catmullRom)
                                    LineMark(x: .value("Day", d.date), y: .value("Sales", d.sales))
                                        .foregroundStyle(Theme.brand)
                                        .interpolationMethod(.catmullRom)
                                }
                                .chartXAxis(.hidden)
                                .chartYAxis {
                                    AxisMarks { v in
                                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                                        AxisValueLabel { Text(Fmt.rupeesShort(v.as(Double.self) ?? 0)).foregroundStyle(.white.opacity(0.6)) }
                                    }
                                }
                                .frame(height: 160)
                            }
                            .glassCard()
                        }
                        manage(s)
                        if !s.topCustomers.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Top customers").font(.headline).foregroundStyle(.white)
                                ForEach(Array(s.topCustomers.enumerated()), id: \.offset) { i, c in
                                    HStack {
                                        Text("#\(i + 1)").font(.caption.weight(.heavy)).foregroundStyle(Theme.brand).frame(width: 28)
                                        VStack(alignment: .leading) {
                                            Text(c.name ?? "—").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                            Text("\(c.visits) visits").font(.caption).foregroundStyle(.white.opacity(0.5))
                                        }
                                        Spacer()
                                        Text(Fmt.rupeesShort(c.spend)).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                            }
                            .glassCard()
                        }
                    } else if error == nil {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Admin")
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func manage(_ s: Analytics) -> some View {
        VStack(spacing: 0) {
            navRow("Verify customers", "person.badge.shield.checkmark.fill", badge: s.pendingVerifications) { ApprovalsView() }
            navRow("Update fuel prices", "indianrupeesign.square.fill") { UpdatePricesView() }
            navRow("Customers", "person.3.fill") { CustomersView() }
            navRow("Bookings", "calendar", badge: s.upcomingBookings) { AdminBookingsView() }
            navRow("Feedback", "star.bubble.fill", badge: s.openFeedback) { AdminFeedbackView() }
            navRow("Send announcement", "megaphone.fill") { BroadcastView() }
        }
        .glassCard(padding: 6)
    }

    private func navRow<D: View>(_ title: String, _ symbol: String, badge: Int = 0, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.brand).frame(width: 28)
                Text(title).foregroundStyle(.white)
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.caption.weight(.heavy)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Theme.brand, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
        }
    }

    private func load() async {
        do { stats = try await APIClient.shared.get("/admin/analytics"); error = nil } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Approvals (super admin verifies sign-ups)

struct ApprovalsView: View {
    @Environment(SessionStore.self) private var session
    @State private var users: [User] = []
    @State private var selected: Set<String> = []
    @State private var toast: String?
    @State private var busy = false

    private var isSuper: Bool { session.user?.role == .SUPERADMIN }

    var body: some View {
        List(selection: $selected) {
            if !isSuper {
                Text("Only the super admin can verify accounts.").foregroundStyle(.orange).listRowBackground(Color.clear)
            }
            if users.isEmpty {
                EmptyState(symbol: "checkmark.seal", title: "All verified", message: "No pending sign-ups right now.").listRowBackground(Color.clear)
            }
            ForEach(users) { u in
                VStack(alignment: .leading, spacing: 4) {
                    Text(u.name).font(.headline)
                    Text(Fmt.phone(u.phone)).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    if let v = u.vehicles, !v.isEmpty {
                        Text(v.map(\.regNumber).joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(Theme.brand)
                    }
                    Text("Signed up \(u.createdAt.relative)").font(.caption2).foregroundStyle(.tertiary)
                }
                .tag(u.id)
                .swipeActions(edge: .leading) {
                    if isSuper { Button("Verify") { Task { await verify([u.id]) } }.tint(Theme.accent) }
                }
                .swipeActions {
                    if isSuper { Button("Block", role: .destructive) { Task { await block(u) } } }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .environment(\.editMode, .constant(isSuper && !users.isEmpty ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Pending (\(users.count))")
        .safeAreaInset(edge: .bottom) {
            if isSuper && !users.isEmpty {
                Button(selected.isEmpty ? "Verify all \(users.count)" : "Verify \(selected.count) selected") {
                    Task { await verify(selected.isEmpty ? users.map(\.id) : Array(selected)) }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: busy))
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .toast($toast)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let p: Paged<User> = try? await APIClient.shared.get("/admin/users", query: ["status": "PENDING", "role": "CUSTOMER", "limit": "100"]) { users = p.items }
    }

    private func verify(_ ids: [String]) async {
        busy = true
        defer { busy = false }
        do {
            let r: BulkResult = try await APIClient.shared.post("/admin/users/verify-bulk", ["ids": ids])
            let ok = r.results.filter(\.ok).count
            toast = "Verified \(ok) customer\(ok == 1 ? "" : "s") ✅"
            selected.removeAll()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            toast = error.localizedDescription
        }
    }

    private func block(_ u: User) async {
        do {
            let _: User = try await APIClient.shared.post("/admin/users/\(u.id)/block", ["blocked": true])
            await load()
        } catch { toast = error.localizedDescription }
    }
}

// MARK: - Prices

struct UpdatePricesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var values: [FuelType: String] = [:]
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("New prices apply immediately in the app and on receipts.").font(.footnote).foregroundStyle(.white.opacity(0.6))
                ForEach(session.station?.availableFuels ?? session.prices.map(\.fuelType)) { f in
                    let current = session.prices.first { $0.fuelType == f }
                    HStack(spacing: 12) {
                        Image(systemName: f.symbol).foregroundStyle(.white).frame(width: 40, height: 40).background(Theme.fuelColor(f).gradient, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading) {
                            Text(f.title).font(.headline).foregroundStyle(.white)
                            if let c = current { Text("Now \(Fmt.rupees(c.price))/\(f.unit)").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                        }
                        Spacer()
                        TextField("0.00", text: Binding(get: { values[f] ?? "" }, set: { values[f] = $0 }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 110)
                            .padding(10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .glassCard(padding: 12, radius: 18)
                }
                if let error { ErrorBanner(message: error) }
                Button("Publish prices") { Task { await save() } }.buttonStyle(PrimaryButtonStyle(isLoading: saving))
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Fuel prices")
        .onAppear {
            for p in session.prices { values[p.fuelType] = String(format: "%.2f", p.price) }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let changed: [[String: Any]] = values.compactMap { f, s in
            guard let v = Double(s), v > 0, v != session.prices.first(where: { $0.fuelType == f })?.price else { return nil }
            return ["fuelType": f.rawValue, "price": v]
        }
        guard !changed.isEmpty else { error = "No prices changed"; return }
        do {
            try await APIClient.shared.send("POST", "/admin/prices", ["prices": changed])
            await session.loadPublic()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Customers

struct CustomersView: View {
    @State private var query = ""
    @State private var users: [User] = []

    var body: some View {
        List(users) { u in
            NavigationLink { CustomerDetailView(userId: u.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.name).font(.headline)
                        Text("\(Fmt.phone(u.phone)) • \(u.points) pts").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusChip(status: u.status.rawValue)
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Customers")
        .searchable(text: $query, prompt: "Name, mobile, card or vehicle")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            if let p: Paged<User> = try? await APIClient.shared.get("/admin/users", query: ["q": query, "limit": "50"]) { users = p.items }
        }
    }
}

struct CustomerDetailView: View {
    let userId: String
    @Environment(SessionStore.self) private var session
    @State private var user: User?
    @State private var points = ""
    @State private var note = ""
    @State private var newPin = ""
    @State private var toast: String?

    var body: some View {
        Form {
            if let u = user {
                Section {
                    LabeledContent("Name", value: u.name)
                    LabeledContent("Mobile", value: Fmt.phone(u.phone))
                    LabeledContent("Card", value: u.cardNumber)
                    LabeledContent("Tier", value: u.tier.title)
                    LabeledContent("Points", value: "\(u.points)")
                    LabeledContent("Lifetime spend", value: Fmt.rupees(u.lifetimeSpend))
                    LabeledContent("Status", value: u.status.rawValue.capitalized)
                    LabeledContent("Role", value: u.role.rawValue.capitalized)
                }
                Section("Adjust points") {
                    TextField("e.g. 50 or -20", text: $points).keyboardType(.numbersAndPunctuation)
                    TextField("Reason", text: $note)
                    Button("Apply") { Task { await adjust() } }.disabled(Int(points) == nil || note.count < 2)
                }
                Section(footer: Text("Use when the customer forgot their PIN — verify their identity at the counter first.")) {
                    TextField("New 4-digit PIN", text: $newPin).keyboardType(.numberPad)
                    Button("Reset PIN") { Task { await resetPin() } }.disabled(newPin.count != 4)
                }
                if session.user?.role == .SUPERADMIN {
                    Section("Super admin") {
                        if u.status == .PENDING { Button("Verify account") { Task { await act("/admin/users/\(u.id)/verify", [:]) } } }
                        Button(u.status == .BLOCKED ? "Unblock" : "Block", role: .destructive) { Task { await act("/admin/users/\(u.id)/block", ["blocked": u.status != .BLOCKED]) } }
                        Menu("Change role") {
                            ForEach(["CUSTOMER", "STAFF", "ADMIN"], id: \.self) { r in
                                Button(r.capitalized) { Task { await act("/admin/users/\(u.id)/role", ["role": r]) } }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(user?.name ?? "Customer")
        .toast($toast)
        .task { await load() }
    }

    private func load() async { user = try? await APIClient.shared.get("/admin/users/\(userId)") }

    private func adjust() async {
        do {
            let _: User = try await APIClient.shared.post("/admin/users/\(userId)/points", ["points": Int(points) ?? 0, "note": note])
            points = ""; note = ""
            toast = "Points updated"
            await load()
        } catch { toast = error.localizedDescription }
    }

    private func resetPin() async {
        do {
            try await APIClient.shared.send("POST", "/admin/users/\(userId)/reset-pin", ["pin": newPin])
            newPin = ""
            toast = "PIN reset — tell the customer their new PIN"
        } catch { toast = error.localizedDescription }
    }

    private func act(_ path: String, _ body: [String: Any]) async {
        do {
            try await APIClient.shared.send("POST", path, body)
            toast = "Done"
            await load()
        } catch { toast = error.localizedDescription }
    }
}

// MARK: - Bookings, feedback, broadcast

struct AdminBookingsView: View {
    @State private var items: [Booking] = []
    var body: some View {
        List(items) { b in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(b.service.title, systemImage: b.service.symbol).font(.headline)
                    Spacer()
                    StatusChip(status: b.status)
                }
                Text(b.slot.formatted(.dateTime.weekday().day().month().hour().minute())).font(.subheadline)
                Text([b.user?.name, b.user.map { Fmt.phone($0.phone) }, b.vehicleReg].compactMap { $0 }.joined(separator: " • ")).font(.caption).foregroundStyle(.secondary)
                if let n = b.notes { Text(n).font(.caption).italic() }
            }
            .swipeActions {
                if b.status == "REQUESTED" { Button("Confirm") { Task { await set(b, "CONFIRMED") } }.tint(Theme.accent) }
                if b.status == "CONFIRMED" { Button("Done") { Task { await set(b, "COMPLETED") } }.tint(.blue) }
                if ["REQUESTED", "CONFIRMED"].contains(b.status) { Button("Cancel", role: .destructive) { Task { await set(b, "CANCELLED") } } }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Bookings")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async { items = (try? await APIClient.shared.get("/admin/bookings")) ?? [] }
    private func set(_ b: Booking, _ status: String) async {
        let _: Booking? = try? await APIClient.shared.patch("/admin/bookings/\(b.id)", ["status": status])
        await load()
    }
}

struct AdminFeedbackView: View {
    @State private var items: [Feedback] = []
    @State private var replying: Feedback?
    @State private var reply = ""

    var body: some View {
        List(items) { f in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(repeating: "★", count: f.rating)).foregroundStyle(Theme.tierColor(.GOLD))
                    Text(f.category).font(.caption.weight(.semibold))
                    Spacer()
                    StatusChip(status: f.status)
                }
                Text(f.message)
                Text("\(f.user?.name ?? "") • \(f.createdAt.relative)").font(.caption).foregroundStyle(.secondary)
                if let r = f.reply { Label(r, systemImage: "arrowshape.turn.up.left.fill").font(.caption).foregroundStyle(Theme.accent) }
            }
            .swipeActions { if f.reply == nil { Button("Reply") { replying = f }.tint(Theme.brand) } }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Feedback")
        .task { await load() }
        .alert("Reply", isPresented: Binding(get: { replying != nil }, set: { if !$0 { replying = nil } })) {
            TextField("Your reply", text: $reply)
            Button("Send") { Task { await send() } }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func load() async { items = (try? await APIClient.shared.get("/admin/feedback")) ?? [] }
    private func send() async {
        guard let f = replying else { return }
        let _: Feedback? = try? await APIClient.shared.post("/admin/feedback/\(f.id)/reply", ["reply": reply])
        reply = ""
        await load()
    }
}

struct BroadcastView: View {
    @State private var title = ""
    @State private var message = ""
    @State private var tier = "ALL"
    @State private var sending = false
    @State private var toast: String?

    var body: some View {
        Form {
            Section(footer: Text("Delivered to every verified member's in-app inbox — free, no SMS.")) {
                TextField("Title (e.g. Diwali Double Points!)", text: $title)
                TextField("Message", text: $message, axis: .vertical).lineLimit(3...6)
                Picker("Audience", selection: $tier) {
                    Text("All members").tag("ALL")
                    ForEach(Tier.allCases, id: \.self) { Text("\($0.title) only").tag($0.rawValue) }
                }
            }
            Button("Send to members") { Task { await send() } }.disabled(title.count < 2 || message.count < 2 || sending)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Announcement")
        .toast($toast)
    }

    private func send() async {
        sending = true
        defer { sending = false }
        struct R: Decodable { let sent: Int }
        var body: [String: Any] = ["title": title, "body": message]
        if tier != "ALL" { body["tier"] = tier }
        do {
            let r: R = try await APIClient.shared.post("/admin/broadcast", body)
            toast = "Sent to \(r.sent) members 📣"
            title = ""; message = ""
        } catch { toast = error.localizedDescription }
    }
}
