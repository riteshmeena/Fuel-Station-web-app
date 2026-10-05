import SwiftUI

struct StaffHomeView: View {
    @State private var shift: ShiftSummary?
    @State private var scanCard = false
    @State private var scanReward = false
    @State private var customer: LookupResult?
    @State private var cardCode = ""
    @State private var toast: String?
    @State private var rewardResult: UseRedemptionResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { scanCard = true } label: {
                        VStack(spacing: 14) {
                            Image(systemName: "qrcode.viewfinder").font(.system(size: 64))
                            Text("Scan customer card").font(.title2.weight(.heavy))
                            Text("Record fill-up & award points").font(.subheadline).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: Theme.brand.opacity(0.5), radius: 20, y: 10)
                    }
                    Button { scanReward = true } label: {
                        Label("Scan reward code", systemImage: "gift.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if let s = shift {
                        HStack(spacing: 10) {
                            StatPill(title: "Today's entries", value: "\(s.count)", symbol: "list.bullet.rectangle.fill")
                            StatPill(title: "Today's amount", value: Fmt.rupeesShort(s.total), symbol: "indianrupeesign.circle.fill", tint: Theme.accent)
                        }
                        SectionHeader(title: "My entries today")
                        if s.items.isEmpty {
                            EmptyState(symbol: "tray", title: "No entries yet", message: "Scanned fill-ups will appear here.")
                        } else {
                            VStack(spacing: 14) { ForEach(s.items) { TransactionRow(tx: $0, showCustomer: true) } }.glassCard()
                        }
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Pump")
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await loadShift() }
            .task { await loadShift() }
            .toast($toast)
            .sheet(isPresented: $scanCard) { ScanSheet(title: "Scan card") { code in Task { await lookup(code) } } }
            .sheet(isPresented: $scanReward) { ScanSheet(title: "Scan reward", manualPlaceholder: "RW-XXXXXXXX") { code in Task { await useReward(code) } } }
            .sheet(item: Binding(get: { customer.map { IdentifiedLookup(result: $0) } }, set: { if $0 == nil { customer = nil } })) { item in
                RecordFillView(result: item.result, code: cardCode) { msg in
                    toast = msg
                    Task { await loadShift() }
                }
            }
            .alert("Reward handed over ✅", isPresented: Binding(get: { rewardResult != nil }, set: { if !$0 { rewardResult = nil } })) {
                Button("OK") {}
            } message: {
                if let r = rewardResult { Text("\(r.redemption.reward.title) for \(r.customer.name)") }
            }
        }
    }

    private func loadShift() async { shift = try? await APIClient.shared.get("/staff/my-shift") }

    private func lookup(_ code: String) async {
        do {
            let r: LookupResult = try await APIClient.shared.get("/staff/lookup", query: ["code": code])
            cardCode = code
            customer = r
        } catch {
            toast = error.localizedDescription
        }
    }

    private func useReward(_ code: String) async {
        do {
            rewardResult = try await APIClient.shared.post("/staff/redemptions/use", ["code": code])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            toast = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct IdentifiedLookup: Identifiable { let result: LookupResult; var id: String { result.user.id } }

struct RecordFillView: View {
    let result: LookupResult
    let code: String
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var fuel: FuelType = .PETROL
    @State private var byAmount = true
    @State private var value = ""
    @State private var odometer = ""
    @State private var vehicleId: String?
    @State private var saving = false
    @State private var error: String?
    @State private var success: FillResult?

    private var price: Double? { session.prices.first { $0.fuelType == fuel }?.price }
    private var numeric: Double? { Double(value.replacingOccurrences(of: ",", with: "")) }
    private var preview: String {
        guard let n = numeric, let p = price, n > 0 else { return " " }
        return byAmount ? "≈ \(Fmt.number((n / p * 100).rounded() / 100)) \(fuel.unit)" : "= \(Fmt.rupees(n * p))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = success {
                    successView(s)
                } else {
                    form
                }
            }
            .screenBackground()
            .navigationTitle(success == nil ? "Record fill-up" : "Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                let v = result.vehicles.first
                vehicleId = v?.id
                if let f = v?.fuelType { fuel = f }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(String(result.user.name.prefix(1))).font(.title2.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 54, height: 54).background(Theme.tierGradient(result.user.tier), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.user.name).font(.headline).foregroundStyle(.white)
                    Text("\(Fmt.phone(result.user.phone)) • \(result.user.tier.title) • \(result.user.points) pts").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                StatusChip(status: result.user.status.rawValue)
            }
            .glassCard(padding: 14, radius: 18)

            if result.user.status != .VERIFIED {
                ErrorBanner(message: "Customer not verified yet. Ask the owner to verify before recording.")
            }

            if !result.vehicles.isEmpty {
                Text("Vehicle").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(result.vehicles) { v in
                            Button {
                                vehicleId = v.id
                                fuel = v.fuelType
                            } label: {
                                Text(v.regNumber).font(.subheadline.monospaced().weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(vehicleId == v.id ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                            }
                        }
                    }
                }
            }

            Text("Fuel").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Picker("Fuel", selection: $fuel) { ForEach(session.prices.map(\.fuelType)) { Text($0.title).tag($0) } }.pickerStyle(.segmented)

            Picker("Mode", selection: $byAmount) {
                Text("By amount (₹)").tag(true)
                Text("By quantity").tag(false)
            }.pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(byAmount ? "₹" : fuel.unit).font(.title.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
                    TextField("0", text: $value).keyboardType(.decimalPad).font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                Text(preview).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                if let p = price { Text("Rate \(Fmt.rupees(p))/\(fuel.unit)").font(.caption).foregroundStyle(.white.opacity(0.5)) }
            }
            .glassCard()

            HStack(spacing: 8) {
                ForEach(byAmount ? ["100", "200", "500", "1000", "2000"] : ["1", "2", "5", "10", "20"], id: \.self) { q in
                    Button(byAmount ? "₹\(q)" : q) { value = q }.buttonStyle(SecondaryButtonStyle())
                }
            }

            FormField(label: "Odometer km (optional — for mileage)", text: $odometer, symbol: "gauge.with.dots.needle.33percent", keyboard: .numberPad)

            if let error { ErrorBanner(message: error) }
            Button("Save & award points") { Task { await save() } }
                .buttonStyle(PrimaryButtonStyle(isLoading: saving))
                .disabled((numeric ?? 0) <= 0 || saving || result.user.status != .VERIFIED)
        }
        .padding(20)
    }

    private func successView(_ s: FillResult) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.accent).symbolEffect(.bounce, value: s.pointsEarned)
                .padding(.top, 40)
            Text("+\(s.pointsEarned) points").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("\(Fmt.rupees(s.transaction.amount)) • \(Fmt.number(s.transaction.quantity)) \(s.transaction.fuelType.unit) \(s.transaction.fuelType.title)").foregroundStyle(.white.opacity(0.7))
            if let t = s.tierUpgrade {
                Label("Upgraded to \(t.title)!", systemImage: "crown.fill").font(.headline).foregroundStyle(Theme.tierColor(t))
                    .padding(12).background(Theme.tierColor(t).opacity(0.15), in: Capsule())
            }
            Text(s.transaction.invoiceNo).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.5))
            Button("Next customer") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 20)
        }
        .padding(24)
    }

    private func save() async {
        guard let n = numeric else { return }
        saving = true
        defer { saving = false }
        error = nil
        var body: [String: Any] = ["code": code, "fuelType": fuel.rawValue, byAmount ? "amount" : "quantity": n]
        if let vehicleId { body["vehicleId"] = vehicleId }
        if let km = Int(odometer) { body["odometerKm"] = km }
        do {
            let r: FillResult = try await APIClient.shared.post("/staff/transactions", body)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring) { success = r }
            onDone("Saved • +\(r.pointsEarned) pts to \(result.user.firstName)")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
