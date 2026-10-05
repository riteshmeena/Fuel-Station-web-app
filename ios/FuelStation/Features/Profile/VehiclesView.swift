import SwiftUI

struct VehiclesView: View {
    @State private var vehicles: [Vehicle] = []
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if vehicles.isEmpty {
                EmptyState(symbol: "car", title: "No vehicles", message: "Add your vehicles for faster fill-ups and mileage tracking.").listRowBackground(Color.clear)
            }
            ForEach(vehicles) { v in
                HStack(spacing: 14) {
                    Image(systemName: v.fuelType == .EV ? "bolt.car.fill" : "car.fill").font(.title3).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Theme.fuelColor(v.fuelType).gradient, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.regNumber).font(.headline.monospaced()).foregroundStyle(.white)
                        Text("\(v.displayName == v.regNumber ? "" : v.displayName + " • ")\(v.fuelType.title)").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if v.isDefault { Text("DEFAULT").font(.caption2.weight(.heavy)).foregroundStyle(Theme.brand) }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await delete(v) } }
                    if !v.isDefault { Button("Default") { Task { await makeDefault(v) } }.tint(Theme.brand) }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("My vehicles")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") } }
        .sheet(isPresented: $showAdd) { AddVehicleView { vehicles.append($0); Task { await load() } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { vehicles = try await APIClient.shared.get("/me/vehicles"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func delete(_ v: Vehicle) async {
        do { try await APIClient.shared.send("DELETE", "/me/vehicles/\(v.id)"); vehicles.removeAll { $0.id == v.id } } catch { self.error = error.localizedDescription }
    }
    private func makeDefault(_ v: Vehicle) async {
        do { let _: Vehicle = try await APIClient.shared.patch("/me/vehicles/\(v.id)", ["isDefault": true]); await load() } catch { self.error = error.localizedDescription }
    }
}

struct AddVehicleView: View {
    var onAdd: (Vehicle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reg = ""
    @State private var nickname = ""
    @State private var make = ""
    @State private var fuel: FuelType = .PETROL
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormField(label: "Vehicle number", text: $reg, symbol: "car.fill", capitalization: .characters)
                    FormField(label: "Nickname (optional)", text: $nickname, symbol: "tag.fill")
                    FormField(label: "Make & model (optional)", text: $make, symbol: "wrench.fill")
                    Text("Fuel").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Picker("Fuel", selection: $fuel) { ForEach(FuelType.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    if let error { ErrorBanner(message: error) }
                    Button("Add vehicle") { Task { await save() } }.buttonStyle(PrimaryButtonStyle(isLoading: saving)).disabled(reg.count < 6).padding(.top, 8)
                }
                .padding(24)
            }
            .screenBackground()
            .navigationTitle("Add vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            var body: [String: Any] = ["regNumber": reg, "fuelType": fuel.rawValue]
            if !nickname.isEmpty { body["nickname"] = nickname }
            if !make.isEmpty { body["make"] = make }
            let v: Vehicle = try await APIClient.shared.post("/me/vehicles", body)
            onAdd(v)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
