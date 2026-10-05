import SwiftUI
import MapKit

struct NotificationsView: View {
    @State private var items: [AppNotification] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && items.isEmpty {
                EmptyState(symbol: "bell.slash", title: "All caught up", message: "Points, offers and booking updates will show here.").listRowBackground(Color.clear)
            }
            ForEach(items) { n in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: n.symbol).foregroundStyle(.white).frame(width: 38, height: 38)
                        .background(Theme.brandGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(n.title).font(.subheadline.weight(.bold))
                            Spacer()
                            if !n.read { Circle().fill(Theme.brand).frame(width: 8) }
                        }
                        Text(n.body).font(.subheadline).foregroundStyle(.secondary)
                        Text(n.createdAt.relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(n.read ? 0.03 : 0.08))
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Notifications")
        .toolbar { if items.contains(where: { !$0.read }) { Button("Mark all read") { Task { await readAll() } } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let p: NotificationsPage = try? await APIClient.shared.get("/me/notifications", query: ["limit": "50"]) { items = p.items }
        loaded = true
    }
    private func readAll() async {
        try? await APIClient.shared.send("POST", "/me/notifications/read-all")
        for i in items.indices { items[i].read = true }
    }
}

struct StationView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            if let s = session.station {
                let coord = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
                VStack(alignment: .leading, spacing: 18) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                        Annotation(s.name, coordinate: coord) {
                            Image(systemName: "fuelpump.circle.fill").font(.system(size: 40)).foregroundStyle(.white, Theme.brand).shadow(radius: 6)
                        }
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.name).font(.title.weight(.heavy))
                        Text("\(s.brand) • \(s.openHours)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                        Text("\(s.address), \(s.city), \(s.state) \(s.pincode)").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        actionButton("Directions", "arrow.triangle.turn.up.right.diamond.fill") {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            item.name = s.name
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                        }
                        actionButton("Call", "phone.fill") { open("tel:\(s.phone)") }
                        actionButton("WhatsApp", "message.fill") { open("https://wa.me/\(s.whatsapp.filter(\.isNumber))") }
                    }

                    if !session.prices.isEmpty {
                        SectionHeader(title: "Fuel prices")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(session.prices) { PriceTile(price: $0).frame(maxWidth: .infinity) }
                        }
                    }

                    SectionHeader(title: "Services")
                    FlowLayout(spacing: 8) {
                        ForEach(s.services, id: \.self) { svc in
                            Label(svc, systemImage: serviceSymbol(svc)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
                .padding(20)
            } else {
                ProgressView().tint(.white).padding(60)
            }
        }
        .screenBackground()
        .navigationTitle("Station")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func open(_ s: String) { if let url = URL(string: s) { UIApplication.shared.open(url) } }

    private func serviceSymbol(_ s: String) -> String {
        let l = s.lowercased()
        if l.contains("air") || l.contains("nitrogen") { return "tirepressure" }
        if l.contains("puc") { return "leaf.fill" }
        if l.contains("wash") { return "drop.circle.fill" }
        if l.contains("lubric") || l.contains("oil") { return "oilcan.fill" }
        if l.contains("store") { return "bag.fill" }
        if l.contains("restroom") { return "figure.dress.line.vertical.figure" }
        if l.contains("water") { return "waterbottle.fill" }
        if l.contains("ev") { return "bolt.fill" }
        return "checkmark.circle.fill"
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct FeedbackView: View {
    @State private var rating = 5
    @State private var category = "General"
    @State private var message = ""
    @State private var history: [Feedback] = []
    @State private var sending = false
    @State private var toast: String?
    private let categories = ["General", "Fuel Quality", "Quantity", "Staff Behaviour", "Cleanliness", "App", "Other"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How was your visit?").font(.title2.weight(.heavy)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= rating ? "star.fill" : "star")
                            .font(.system(size: 34))
                            .foregroundStyle(i <= rating ? Theme.tierColor(.GOLD) : .white.opacity(0.3))
                            .scaleEffect(i == rating ? 1.15 : 1)
                            .onTapGesture { withAnimation(.spring) { rating = i }; UISelectionFeedbackGenerator().selectionChanged() }
                    }
                }
                .frame(maxWidth: .infinity)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c) { category = c }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(category == c ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                        }
                    }
                }
                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty { Text("Tell us more…").foregroundStyle(.white.opacity(0.4)).padding(16).allowsHitTesting(false) }
                    }
                    .foregroundStyle(.white)
                Button("Send feedback") { Task { await send() } }
                    .buttonStyle(PrimaryButtonStyle(isLoading: sending))
                    .disabled(message.trimmingCharacters(in: .whitespaces).count < 3)

                if !history.isEmpty {
                    SectionHeader(title: "Your feedback")
                    ForEach(history) { f in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(repeating: "★", count: f.rating)).foregroundStyle(Theme.tierColor(.GOLD))
                                Text(f.category).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                StatusChip(status: f.status)
                            }
                            Text(f.message).font(.subheadline).foregroundStyle(.white)
                            if let reply = f.reply {
                                Label(reply, systemImage: "arrowshape.turn.up.left.fill").font(.footnote).foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(padding: 14, radius: 16)
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Feedback")
        .toast($toast)
        .task { history = (try? await APIClient.shared.get("/me/feedback")) ?? [] }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let f: Feedback = try await APIClient.shared.post("/me/feedback", ["rating": rating, "category": category, "message": message])
            history.insert(f, at: 0)
            message = ""
            toast = "Thanks! The owner reads every message 🙏"
        } catch {
            toast = error.localizedDescription
        }
    }
}

struct ReferralView: View {
    @State private var data: Referrals?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "person.2.wave.2.fill").font(.system(size: 60)).foregroundStyle(Theme.brandGradient).padding(.top, 20)
                Text("Invite friends, earn points").font(.title.weight(.heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("You get bonus points when a friend signs up with your code and gets verified.")
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
                if let code = data?.code {
                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                    } label: {
                        HStack {
                            Text(code).font(.system(.title, design: .monospaced).weight(.heavy)).tracking(4)
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])).foregroundStyle(Theme.brand))
                    }
                    ShareLink(item: "Join me at our fuel station's rewards club! Use my code \(code) when you sign up in the app to start earning points on every fill-up ⛽") {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if let friends = data?.referred, !friends.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Friends joined (\(friends.count))").font(.headline).foregroundStyle(.white)
                        ForEach(friends) { f in
                            HStack {
                                Text(f.name).foregroundStyle(.white)
                                Spacer()
                                StatusChip(status: f.status.rawValue)
                            }
                        }
                    }
                    .glassCard()
                }
            }
            .padding(24)
        }
        .screenBackground()
        .navigationTitle("Refer & earn")
        .navigationBarTitleDisplayMode(.inline)
        .task { data = try? await APIClient.shared.get("/me/referrals") }
    }
}
