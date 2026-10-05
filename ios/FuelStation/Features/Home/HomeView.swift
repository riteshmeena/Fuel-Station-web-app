import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var dash: Dashboard?
    @State private var error: String?
    @State private var showCard = false
    @State private var route: Route?

    enum Route: Hashable { case station, bookings, reminders, vehicles, notifications, feedback, referral, offers }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let user = session.user {
                        FuelCardView(user: dash?.user ?? user, stationName: session.station?.name ?? "Fuel Station", brand: session.station?.brand ?? "")
                            .onLongPressGesture { showCard = true }
                        if let tp = dash?.tierProgress ?? session.tierProgress { TierProgressCard(progress: tp) }
                    }
                    if let error { ErrorBanner(message: error) { Task { await load() } } }
                    quickActions
                    prices
                    if let d = dash { monthStats(d.month) }
                    if let d = dash, !d.offers.isEmpty { offers(d.offers) }
                    if let d = dash, !d.upcomingReminders.isEmpty { reminders(d.upcomingReminders) }
                    if let d = dash { recent(d.recentTransactions) }
                    stationStrip
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showCard) { if let u = session.user { CardDetailView(user: u) } }
            .navigationDestination(for: Transaction.self) { TransactionDetailView(tx: $0) }
            .navigationDestination(item: $route) { r in
                switch r {
                case .station: StationView()
                case .bookings: BookingsView()
                case .reminders: RemindersView()
                case .vehicles: VehiclesView()
                case .notifications: NotificationsView()
                case .feedback: FeedbackView()
                case .referral: ReferralView()
                case .offers: RewardsView(initialTab: .offers, embedded: true)
                }
            }
        }
    }

    private func load() async {
        async let pub: Void = session.loadPublic()
        do {
            let d: Dashboard = try await APIClient.shared.get("/me/dashboard")
            withAnimation(.spring) { dash = d }
            session.user = d.user
            session.tierProgress = d.tierProgress
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await pub
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting()).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                Text(session.user?.firstName ?? "").font(.title.weight(.heavy)).foregroundStyle(.white)
            }
            Spacer()
            Button { route = .notifications } label: {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.1), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if let n = dash?.unreadNotifications, n > 0 {
                            Text("\(min(n, 99))").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(5).background(Theme.brand, in: Circle()).offset(x: 4, y: -4)
                        }
                    }
            }
        }
        .padding(.top, 8)
    }

    private var quickActions: some View {
        HStack(alignment: .top) {
            Button { showCard = true } label: { QuickAction(title: "Scan Card", symbol: "qrcode", tint: Theme.brand) }
            Button { route = .bookings } label: { QuickAction(title: "Book", symbol: "calendar.badge.plus", tint: Color(hex: 0x2E9BFF)) }
            Button { route = .reminders } label: { QuickAction(title: "Reminders", symbol: "bell.badge.fill", tint: Color(hex: 0xC04BFF)) }
            Button { route = .station } label: { QuickAction(title: "Station", symbol: "map.fill", tint: Theme.accent) }
        }
        .buttonStyle(.plain)
    }

    private var prices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today's prices")
            if let date = session.prices.map(\.updatedAt).max() {
                Text("Updated \(date.relative)").font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.top, -8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { ForEach(session.prices) { PriceTile(price: $0) } }
            }
            .scrollClipDisabled()
        }
    }

    private func monthStats(_ m: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This month")
            HStack(spacing: 10) {
                StatPill(title: "Spent", value: Fmt.rupeesShort(m.spend), symbol: "indianrupeesign.circle.fill")
                StatPill(title: "Fuel", value: "\(Fmt.number(m.quantity.rounded()))", symbol: "drop.fill", tint: Color(hex: 0x2E9BFF))
                StatPill(title: "Points", value: "+\(m.points)", symbol: "star.fill", tint: Theme.tierColor(.GOLD))
            }
        }
    }

    private func offers(_ list: [Offer]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Offers for you", action: "See all") { route = .offers }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(list) { OfferBanner(offer: $0).frame(width: 290) }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func reminders(_ list: [Reminder]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Coming up", action: "All") { route = .reminders }
            VStack(spacing: 10) {
                ForEach(list) { r in
                    HStack(spacing: 12) {
                        Image(systemName: r.type.symbol).foregroundStyle(.white).frame(width: 38, height: 38)
                            .background(Color(hex: 0xC04BFF).gradient, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(r.vehicleReg ?? r.type.title).font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        DueBadge(days: r.daysLeft)
                    }
                }
            }
            .glassCard()
        }
    }

    private func recent(_ txs: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent fill-ups")
            if txs.isEmpty {
                EmptyState(symbol: "fuelpump", title: "No fill-ups yet", message: "Show your card QR at the pump to start earning points.").glassCard()
            } else {
                VStack(spacing: 14) {
                    ForEach(txs) { tx in
                        NavigationLink(value: tx) { TransactionRow(tx: tx) }.buttonStyle(.plain)
                        if tx.id != txs.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }
                .glassCard()
            }
        }
    }

    private var stationStrip: some View {
        HStack(spacing: 10) {
            Button { route = .referral } label: { Label("Refer & earn", systemImage: "person.2.fill") }
            Button { route = .feedback } label: { Label("Feedback", systemImage: "star.bubble.fill") }
            Button { route = .vehicles } label: { Label("Vehicles", systemImage: "car.fill") }
        }
        .buttonStyle(SecondaryButtonStyle())
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity)
    }
}

struct TierProgressCard: View {
    let progress: TierProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(progress.tier.title) • \(String(format: "%g", progress.multiplier))× points", systemImage: "crown.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.tierColor(progress.tier))
                Spacer()
                if let next = progress.nextTier {
                    Text(next.title).font(.caption.weight(.bold)).foregroundStyle(Theme.tierColor(next))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [Theme.tierColor(progress.tier), Theme.tierColor(progress.nextTier ?? progress.tier)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * progress.progress))
                }
            }
            .frame(height: 10)
            Text(progress.nextTier == nil ? "You're at the top tier. Enjoy maximum rewards! 🏆" : "Spend \(Fmt.rupeesShort(progress.remaining)) more to unlock \(progress.nextTier!.title)")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .glassCard(padding: 14, radius: 18)
    }
}

struct DueBadge: View {
    let days: Int
    var body: some View {
        let color: Color = days < 0 ? Theme.danger : days <= 7 ? .orange : Theme.accent
        Text(days < 0 ? "Overdue" : days == 0 ? "Today" : "\(days)d left")
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct OfferBanner: View {
    let offer: Offer
    var claimed = false
    var onClaim: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(offer.minTier == .SILVER ? "FOR ALL" : "\(offer.minTier.rawValue)+")
                    .font(.caption2.weight(.heavy)).tracking(1.5)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.25), in: Capsule())
                Spacer()
                Text("Ends \(offer.endsAt.dayMonth)").font(.caption2.weight(.semibold)).opacity(0.8)
            }
            Text(offer.title).font(.title3.weight(.heavy)).lineLimit(2)
            Text(offer.description).font(.footnote).opacity(0.85).lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                if offer.bonusPoints > 0 { Label("+\(offer.bonusPoints) pts", systemImage: "star.fill").font(.caption.weight(.bold)) }
                if let code = offer.couponCode { Label(code, systemImage: "ticket.fill").font(.caption.weight(.bold)) }
                Spacer()
                if let onClaim {
                    Button(claimed ? "Claimed" : "Claim", action: onClaim)
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.white, in: Capsule())
                        .foregroundStyle(Theme.brandDeep)
                        .disabled(claimed)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(minHeight: 170, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.brandGradient)
                Image(systemName: "gift.fill").font(.system(size: 90)).foregroundStyle(.white.opacity(0.12)).rotationEffect(.degrees(-15)).offset(x: 10, y: 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
