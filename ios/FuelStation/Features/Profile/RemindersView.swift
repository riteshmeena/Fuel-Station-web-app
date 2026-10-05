import SwiftUI
import UserNotifications

struct RemindersView: View {
    @State private var items: [Reminder] = []
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if items.isEmpty {
                EmptyState(symbol: "bell", title: "No reminders", message: "Never miss a PUC, insurance renewal or service again.").listRowBackground(Color.clear)
            }
            ForEach(items) { r in
                HStack(spacing: 12) {
                    Button { Task { await toggle(r) } } label: {
                        Image(systemName: r.done ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(r.done ? Theme.accent : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    Image(systemName: r.type.symbol).foregroundStyle(.white).frame(width: 36, height: 36)
                        .background(Color(hex: 0xC04BFF).gradient, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).strikethrough(r.done)
                        Text("\(r.dueDate.formatted(date: .abbreviated, time: .omitted))\(r.vehicleReg.map { " • \($0)" } ?? "")").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    if !r.done { DueBadge(days: r.daysLeft) }
                }
                .listRowBackground(Color.white.opacity(0.06))
                .swipeActions { Button("Delete", role: .destructive) { Task { await delete(r) } } }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Reminders")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") } }
        .sheet(isPresented: $showAdd) { AddReminderView { _ in Task { await load() } } }
        .task { await load() }
    }

    private func load() async {
        do { items = try await APIClient.shared.get("/me/reminders"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func toggle(_ r: Reminder) async {
        do { let _: Reminder = try await APIClient.shared.patch("/me/reminders/\(r.id)", ["done": !r.done]); await load() } catch { self.error = error.localizedDescription }
    }
    private func delete(_ r: Reminder) async {
        do {
            try await APIClient.shared.send("DELETE", "/me/reminders/\(r.id)")
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [r.id + "-7", r.id + "-0"])
            items.removeAll { $0.id == r.id }
        } catch { self.error = error.localizedDescription }
    }
}

struct AddReminderView: View {
    var onAdd: (Reminder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: ReminderType = .PUC
    @State private var title = ReminderType.PUC.title
    @State private var date = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
    @State private var reg = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) { ForEach(ReminderType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                    .onChange(of: type) { _, t in title = t.title }
                TextField("Title", text: $title)
                DatePicker("Due date", selection: $date, in: Date.now..., displayedComponents: .date)
                TextField("Vehicle number (optional)", text: $reg).textInputAutocapitalization(.characters)
                if let error { Text(error).foregroundStyle(Theme.danger) }
                Section(footer: Text("We'll also remind you on this iPhone 7 days before and on the due date — free, no SMS.")) { EmptyView() }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(title.count < 2 || saving) }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            var body: [String: Any] = ["type": type.rawValue, "title": title, "dueDate": date.iso]
            if !reg.isEmpty { body["vehicleReg"] = reg.uppercased() }
            let r: Reminder = try await APIClient.shared.post("/me/reminders", body)
            await LocalReminders.schedule(r)
            onAdd(r)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Free on-device reminders via local notifications (no push server or SMS needed).
enum LocalReminders {
    static func schedule(_ r: Reminder) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        for (suffix, offset) in [("-7", -7), ("-0", 0)] {
            guard let fire = Calendar.current.date(byAdding: .day, value: offset, to: r.dueDate), fire > .now else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: fire)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = offset == 0 ? "\(r.title) is due today" : "\(r.title) due in 7 days"
            content.body = r.vehicleReg.map { "Vehicle \($0) — tap to view reminders." } ?? "Tap to view your reminders."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: r.id + suffix, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
