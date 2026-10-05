import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    enum Phase { case launching, loggedOut, loggedIn }

    var phase: Phase = .launching
    var user: User?
    var tierProgress: TierProgress?
    var station: Station?
    var prices: [FuelPrice] = []

    private let api = APIClient.shared
    private let tokenKey = "authToken"

    init() {
        api.onUnauthorized = { [weak self] in self?.logout() }
    }

    func bootstrap() async {
        async let s: Void = loadPublic()
        if let token = Keychain.get(tokenKey) {
            api.token = token
            do {
                try await refreshMe()
                phase = .loggedIn
            } catch let e as APIError where e.status == 0 {
                // Offline: keep the user in, screens will show retry states.
                phase = .loggedIn
            } catch {
                logout()
            }
        } else {
            phase = .loggedOut
        }
        await s
    }

    func loadPublic() async {
        async let st: Station? = try? api.get("/public/station")
        async let pr: [FuelPrice]? = try? api.get("/public/prices")
        if let v = await st { station = v }
        if let v = await pr { prices = v }
    }

    func refreshMe() async throws {
        let me: MeResponse = try await api.get("/me")
        user = me.user
        tierProgress = me.tierProgress
    }

    func login(phone: String, pin: String) async throws {
        let res: AuthResponse = try await api.post("/auth/login", ["phone": phone, "pin": pin])
        await signIn(res)
    }

    func register(name: String, phone: String, pin: String, email: String?, referral: String?, vehicle: (String, FuelType)?) async throws {
        var body: [String: Any] = ["name": name, "phone": phone, "pin": pin]
        if let email, !email.isEmpty { body["email"] = email }
        if let referral, !referral.isEmpty { body["referralCode"] = referral }
        if let vehicle, !vehicle.0.isEmpty { body["vehicle"] = ["regNumber": vehicle.0, "fuelType": vehicle.1.rawValue] }
        let res: AuthResponse = try await api.post("/auth/register", body)
        await signIn(res)
    }

    func changePin(current: String, new: String) async throws {
        let res: AuthResponse = try await api.post("/auth/change-pin", ["currentPin": current, "newPin": new])
        api.token = res.token
        Keychain.set(res.token, for: tokenKey)
        user = res.user
    }

    private func signIn(_ res: AuthResponse) async {
        api.token = res.token
        Keychain.set(res.token, for: tokenKey)
        user = res.user
        try? await refreshMe()
        phase = .loggedIn
    }

    func logout() {
        api.token = nil
        Keychain.set(nil, for: tokenKey)
        user = nil
        tierProgress = nil
        phase = .loggedOut
    }
}
