import SwiftUI
import Charts

struct ActivityView: View {
    enum Tab: String, CaseIterable { case insights = "Insights", fillups = "Fill-ups", points = "Points" }
    @State private var tab: Tab = .insights
    @State private var insights: Insights?
    @State private var txs: [Transaction] = []
    @State private var txTotal = 0
    @State private var page = 1
    @State private var ledger: [LedgerEntry] = []
    @State private var error: String?
    @State private var months = 6
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    if let error { ErrorBanner(message: error) { Task { await load() } } }
                    switch tab {
                    case .insights: insightsView
                    case .fillups: fillups
                    case .points: pointsView
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Activity")
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Transaction.self) { TransactionDetailView(tx: $0) }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: months) { Task { await loadInsights() } }
        }
    }

    // MARK: Insights

    @ViewBuilder private var insightsView: some View {
        if let ins = insights {
            let total = ins.monthly.reduce(0) { $0 + $1.spend }
            let litres = ins.monthly.reduce(0) { $0 + $1.quantity }
            let visits = ins.monthly.reduce(0) { $0 + $1.visits }
            HStack(spacing: 10) {
                StatPill(title: "\(months)-mo spend", value: Fmt.rupeesShort(total), symbol: "indianrupeesign.circle.fill")
                StatPill(title: "Fuel", value: Fmt.number(litres.rounded()), symbol: "drop.fill", tint: Color(hex: 0x2E9BFF))
                StatPill(title: "Visits", value: "\(visits)", symbol: "mappin.circle.fill", tint: Theme.accent)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Monthly spend").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Picker("", selection: $months) {
                        Text("3M").tag(3)
                        Text("6M").tag(6)
                        Text("12M").tag(12)
                    }
                    .pickerStyle(.segmented).frame(width: 150)
                }
                Chart(ins.monthly) { m in
                    BarMark(x: .value("Month", Fmt.monthLabel(m.month)), y: .value("Spend", m.spend))
                        .foregroundStyle(Theme.brandGradient)
                        .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel { Text(Fmt.rupeesShort(v.as(Double.self) ?? 0)).foregroundStyle(.white.opacity(0.6)) }
                    }
                }
                .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(.white.opacity(0.7)) } }
                .frame(height: 200)
            }
            .glassCard()

            if !ins.byFuel.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spend by fuel").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 20) {
                        Chart(ins.byFuel) { f in
                            SectorMark(angle: .value("Spend", f.spend), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(Theme.fuelColor(f.fuelType))
                                .cornerRadius(4)
                        }
                        .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ins.byFuel) { f in
                                HStack {
                                    Circle().fill(Theme.fuelColor(f.fuelType)).frame(width: 10)
                                    Text(f.fuelType.title).font(.subheadline).foregroundStyle(.white)
                                    Spacer()
                                    Text(Fmt.rupeesShort(f.spend)).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .glassCard()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Mileage").font(.headline).foregroundStyle(.white)
                if ins.mileage.isEmpty {
                    Text("Ask the attendant to enter your odometer reading at fill-up — we'll calculate your km/l automatically.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                ForEach(ins.mileage) { m in
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.67percent").font(.title2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(m.regNumber ?? "Vehicle").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text("\(m.km) km tracked").font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Text(m.kmPerUnit.map { String(format: "%.1f km/l", $0) } ?? "—").font(.title3.weight(.heavy)).foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    // MARK: Fill-ups

    @ViewBuilder private var fillups: some View {
        if txs.isEmpty {
            EmptyState(symbol: "fuelpump", title: "No fill-ups yet", message: "Your fuel history and receipts will appear here.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(txs) { tx in
                    NavigationLink(value: tx) { TransactionRow(tx: tx).glassCard(padding: 12, radius: 16) }.buttonStyle(.plain)
                        .onAppear { if tx.id == txs.last?.id, txs.count < txTotal { Task { await loadMoreTx() } } }
                }
            }
        }
    }

    // MARK: Points

    @ViewBuilder private var pointsView: some View {
        if session.user?.status != .VERIFIED {
            EmptyState(symbol: "hourglass", title: "Awaiting verification", message: "Points history unlocks once your account is verified.")
        } else if ledger.isEmpty {
            EmptyState(symbol: "star", title: "No points yet", message: "Earn points on every fill-up.")
        } else {
            VStack(spacing: 0) {
                ForEach(ledger) { e in
                    HStack(spacing: 12) {
                        Image(systemName: e.points >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                            .font(.title3).foregroundStyle(e.points >= 0 ? Theme.accent : Theme.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.note ?? e.type.capitalized).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text("\(e.type.capitalized) • \(e.createdAt.dayMonthYearTime)").font(.caption).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text(e.points >= 0 ? "+\(e.points)" : "\(e.points)").font(.headline.weight(.heavy))
                            .foregroundStyle(e.points >= 0 ? Theme.accent : Theme.danger)
                    }
                    .padding(.vertical, 10)
                    if e.id != ledger.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }
            .glassCard()
        }
    }

    private func load() async {
        error = nil
        await loadInsights()
        do {
            let p: Paged<Transaction> = try await APIClient.shared.get("/me/transactions", query: ["page": "1", "limit": "20"])
            txs = p.items
            txTotal = p.total ?? p.items.count
            page = 1
            if session.user?.status == .VERIFIED {
                let pts: PointsPage = try await APIClient.shared.get("/me/points", query: ["limit": "50"])
                ledger = pts.items
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadInsights() async {
        do {
            let i: Insights = try await APIClient.shared.get("/me/insights", query: ["months": "\(months)"])
            withAnimation { insights = i }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMoreTx() async {
        guard let p: Paged<Transaction> = try? await APIClient.shared.get("/me/transactions", query: ["page": "\(page + 1)", "limit": "20"]) else { return }
        page += 1
        txs += p.items.filter { n in !txs.contains { $0.id == n.id } }
    }
}

struct TransactionDetailView: View {
    let tx: Transaction
    @State private var pdfURL: URL?
    @State private var loadingPDF = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: tx.fuelType.symbol).font(.system(size: 34)).foregroundStyle(.white)
                        .frame(width: 76, height: 76).background(Theme.fuelColor(tx.fuelType).gradient, in: Circle())
                    Text(Fmt.rupees(tx.amount)).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    if tx.pointsEarned > 0 {
                        Label("+\(tx.pointsEarned) points earned", systemImage: "star.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 10)

                VStack(spacing: 0) {
                    row("Invoice", tx.invoiceNo)
                    row("Date", tx.createdAt.dayMonthYearTime)
                    row("Fuel", tx.fuelType.title)
                    row("Rate", "\(Fmt.rupees(tx.pricePerUnit)) / \(tx.fuelType.unit)")
                    row("Quantity", "\(Fmt.number(tx.quantity)) \(tx.fuelType.unit)")
                    if let v = tx.vehicle { row("Vehicle", v.regNumber) }
                    if let o = tx.odometerKm { row("Odometer", "\(Fmt.number(Double(o))) km") }
                }
                .glassCard()

                if let error { ErrorBanner(message: error) }
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("Share receipt PDF", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { Task { await fetchPDF() } } label: { Label("Download receipt", systemImage: "doc.text.fill") }
                        .buttonStyle(PrimaryButtonStyle(isLoading: loadingPDF))
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Fill-up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(v).fontWeight(.semibold).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    private func fetchPDF() async {
        loadingPDF = true
        defer { loadingPDF = false }
        do {
            let data = try await APIClient.shared.raw("GET", "/me/transactions/\(tx.id)/invoice.pdf")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(tx.invoiceNo).pdf")
            try data.write(to: url)
            pdfURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }
}
