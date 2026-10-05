import SwiftUI

struct RewardsView: View {
    enum Tab: String, CaseIterable { case catalog = "Rewards", offers = "Offers", mine = "My Codes" }

    var initialTab: Tab = .catalog
    var embedded = false

    @Environment(SessionStore.self) private var session
    @State private var tab: Tab = .catalog
    @State private var rewards: [Reward] = []
    @State private var offers: [Offer] = []
    @State private var claimed: Set<String> = []
    @State private var redemptions: [Redemption] = []
    @State private var confirm: Reward?
    @State private var showCode: Redemption?
    @State private var toast: String?
    @State private var error: String?
    @State private var category = "All"

    private var verified: Bool { session.user?.status == .VERIFIED }
    private var categories: [String] { ["All"] + Array(Set(rewards.map(\.category))).sorted() }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                balanceHeader
                Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented)
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                switch tab {
                case .catalog: catalog
                case .offers: offerList
                case .mine: myCodes
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Rewards")
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task {
            tab = initialTab
            await load()
        }
        .toast($toast)
        .confirmationDialog("Redeem reward?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible, presenting: confirm) { r in
            Button("Redeem for \(r.pointsCost) points") { Task { await redeem(r) } }
        } message: { r in
            Text("\(r.title) — you'll get a code to show at the counter.")
        }
        .sheet(item: $showCode) { RedemptionCodeSheet(redemption: $0) }
    }

    private var balanceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your balance").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.points(session.user?.points ?? 0)).font(.system(size: 40, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    Text("pts").font(.headline).opacity(0.7)
                }
                if let v = session.tierProgress?.pointValueInr, let p = session.user?.points {
                    Text("≈ \(Fmt.rupees(Double(p) * v)) value").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
            Spacer()
            Image(systemName: "star.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.tierColor(.GOLD).gradient)
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding(20)
        .background(Theme.tierGradient(session.user?.tier ?? .SILVER), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { c in
                        Button(c) { withAnimation { category = c } }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(category == c ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(rewards.filter { category == "All" || $0.category == category }) { r in
                    RewardTile(reward: r, balance: session.user?.points ?? 0) { confirm = r }
                }
            }
        }
    }

    private var offerList: some View {
        VStack(spacing: 14) {
            if offers.isEmpty { EmptyState(symbol: "tag", title: "No offers right now", message: "Check back soon — we run festival offers often!") }
            ForEach(offers) { o in
                OfferBanner(offer: o, claimed: claimed.contains(o.id)) { Task { await claim(o) } }
            }
        }
    }

    private var myCodes: some View {
        VStack(spacing: 12) {
            if redemptions.isEmpty { EmptyState(symbol: "ticket", title: "No redeemed rewards", message: "Redeem a reward and its code will appear here.") }
            ForEach(redemptions) { r in
                Button { if r.status == "PENDING" { showCode = r } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: r.reward.symbol).foregroundStyle(.white).frame(width: 42, height: 42)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.reward.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text("\(r.code) • \(r.createdAt.dayMonth)").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Text(r.status == "PENDING" ? "Show" : r.status.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(r.status == "PENDING" ? Theme.brand : .white.opacity(0.5))
                    }
                    .glassCard(padding: 12, radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        let api = APIClient.shared
        do {
            async let r: [Reward] = api.get("/public/rewards")
            async let o: [Offer] = api.get("/public/offers")
            rewards = try await r
            offers = try await o
            if verified {
                async let red: [Redemption] = api.get("/loyalty/redemptions")
                async let c: [UserCoupon] = api.get("/loyalty/coupons")
                redemptions = try await red
                claimed = Set((try await c).map(\.offer.id))
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func redeem(_ r: Reward) async {
        do {
            let res: Redemption = try await APIClient.shared.post("/loyalty/rewards/\(r.id)/redeem")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await session.refreshMe()
            redemptions.insert(res, at: 0)
            showCode = res
        } catch {
            toast = error.localizedDescription
        }
    }

    private func claim(_ o: Offer) async {
        do {
            let _: UserCoupon = try await APIClient.shared.post("/loyalty/offers/\(o.id)/claim")
            claimed.insert(o.id)
            try? await session.refreshMe()
            toast = o.bonusPoints > 0 ? "+\(o.bonusPoints) points added 🎉" : "Offer saved to your account"
        } catch {
            toast = error.localizedDescription
        }
    }
}

struct RewardTile: View {
    let reward: Reward
    let balance: Int
    let onRedeem: () -> Void

    private var affordable: Bool { balance >= reward.pointsCost }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Theme.brandGradient.opacity(0.85))
                Image(systemName: reward.symbol).font(.system(size: 34)).foregroundStyle(.white)
            }
            .frame(height: 90)
            Text(reward.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(2, reservesSpace: true)
            Text(reward.description).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2, reservesSpace: true)
            if let stock = reward.stock, stock < 10 {
                Text(stock == 0 ? "Out of stock" : "Only \(stock) left").font(.caption2.weight(.bold)).foregroundStyle(.orange)
            }
            Button(action: onRedeem) {
                Text("\(Fmt.points(reward.pointsCost)) pts").font(.caption.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 34)
                    .background(affordable ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
                    .foregroundStyle(affordable ? Theme.brandDeep : .white.opacity(0.5))
            }
            .disabled(!affordable || reward.stock == 0)
        }
        .glassCard(padding: 12, radius: 20)
    }
}

struct RedemptionCodeSheet: View {
    let redemption: Redemption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gift.fill").font(.system(size: 48)).foregroundStyle(Theme.brandGradient).padding(.top, 30)
            Text(redemption.reward.title).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            Text("Show this code at the counter").foregroundStyle(.white.opacity(0.65))
            VStack(spacing: 14) {
                QRCodeView(text: redemption.code).frame(width: 200, height: 200)
                Text(redemption.code).font(.system(.title, design: .monospaced).weight(.heavy)).tracking(2)
            }
            .foregroundStyle(.black)
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(24)
        .screenBackground()
        .presentationDetents([.large])
    }
}
