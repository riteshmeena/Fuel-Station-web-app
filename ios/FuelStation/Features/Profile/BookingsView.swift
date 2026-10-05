import SwiftUI

struct BookingsView: View {
    @State private var items: [Booking] = []
    @State private var showNew = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Button { showNew = true } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus").font(.title2)
                        VStack(alignment: .leading) {
                            Text("Book a service").font(.headline)
                            Text("Car wash, oil change, PUC & more").font(.caption).opacity(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section("Your bookings") {
                if items.isEmpty { Text("No bookings yet").foregroundStyle(.secondary) }
                ForEach(items) { b in
                    HStack(spacing: 12) {
                        Image(systemName: b.service.symbol).foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(Color(hex: 0x2E9BFF).gradient, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.service.title).font(.subheadline.weight(.semibold))
                            Text(b.slot.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusChip(status: b.status)
                    }
                    .swipeActions {
                        if ["REQUESTED", "CONFIRMED"].contains(b.status) {
                            Button("Cancel", role: .destructive) { Task { await cancel(b) } }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Bookings")
        .sheet(isPresented: $showNew) { NewBookingView { Task { await load() } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { items = try await APIClient.shared.get("/me/bookings"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func cancel(_ b: Booking) async {
        do { let _: Booking = try await APIClient.shared.post("/me/bookings/\(b.id)/cancel"); await load() } catch { self.error = error.localizedDescription }
    }
}

struct StatusChip: View {
    let status: String
    private var color: Color {
        switch status {
        case "CONFIRMED", "RESOLVED", "VERIFIED", "USED": Theme.accent
        case "COMPLETED": .blue
        case "CANCELLED", "BLOCKED": Theme.danger
        default: .orange
        }
    }

    var body: some View {
        Text(status.capitalized).font(.caption2.weight(.heavy)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.15), in: Capsule())
    }
}

struct NewBookingView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var service: ServiceType = .CAR_WASH
    @State private var day = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
    @State private var hour = 10
    @State private var vehicles: [Vehicle] = []
    @State private var vehicleReg = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var error: String?

    private let hours = Array(8...20)
    private var slot: Date { Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)! }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Service").font(.headline).foregroundStyle(.white)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                        ForEach(ServiceType.allCases) { s in
                            Button { service = s } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: s.symbol).font(.title3)
                                    Text(s.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .background(service == s ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }

                    Text("Day").font(.headline).foregroundStyle(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<14, id: \.self) { i in
                                let d = Calendar.current.date(byAdding: .day, value: i, to: Calendar.current.startOfDay(for: .now))!
                                Button { day = d } label: {
                                    VStack(spacing: 4) {
                                        Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.bold)).opacity(0.75)
                                        Text(d.formatted(.dateTime.day())).font(.title3.weight(.heavy))
                                        Text(d.formatted(.dateTime.month(.abbreviated))).font(.caption2)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(width: 58, height: 78)
                                    .background(Calendar.current.isDate(day, inSameDayAs: d) ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                    }

                    Text("Time").font(.headline).foregroundStyle(.white)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 8) {
                        ForEach(hours, id: \.self) { h in
                            let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: day)!
                            let past = d <= .now
                            Button { hour = h } label: {
                                Text(d.formatted(.dateTime.hour()))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(past ? .white.opacity(0.3) : .white)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(hour == h ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                            }
                            .disabled(past)
                        }
                    }

                    if !vehicles.isEmpty {
                        Text("Vehicle").font(.headline).foregroundStyle(.white)
                        Picker("Vehicle", selection: $vehicleReg) {
                            ForEach(vehicles) { Text("\($0.regNumber) • \($0.displayName)").tag($0.regNumber) }
                        }
                        .pickerStyle(.menu)
                    }
                    FormField(label: "Notes (optional)", text: $notes, symbol: "text.bubble.fill", capitalization: .sentences)
                    if let error { ErrorBanner(message: error) }
                    Button("Request \(slot.formatted(.dateTime.day().month().hour()))") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isLoading: saving))
                        .disabled(slot <= .now || saving)
                    Text("Booking only — pay at the station after service.").font(.caption).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Book a service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                vehicles = (try? await APIClient.shared.get("/me/vehicles")) ?? []
                vehicleReg = vehicles.first?.regNumber ?? ""
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            var body: [String: Any] = ["service": service.rawValue, "slot": slot.iso]
            if !vehicleReg.isEmpty { body["vehicleReg"] = vehicleReg }
            if !notes.isEmpty { body["notes"] = notes }
            let _: Booking = try await APIClient.shared.post("/me/bookings", body)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
