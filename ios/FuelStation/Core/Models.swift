import Foundation

enum Role: String, Codable { case CUSTOMER, STAFF, ADMIN, SUPERADMIN
    var isStaff: Bool { self != .CUSTOMER }
    var isAdmin: Bool { self == .ADMIN || self == .SUPERADMIN }
}
enum AccountStatus: String, Codable { case PENDING, VERIFIED, BLOCKED }
enum Tier: String, Codable, CaseIterable { case SILVER, GOLD, PLATINUM
    var title: String { rawValue.capitalized }
}

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case PETROL, DIESEL, PREMIUM_PETROL, CNG, EV
    var id: String { rawValue }
    var title: String {
        switch self {
        case .PETROL: "Petrol"
        case .DIESEL: "Diesel"
        case .PREMIUM_PETROL: "Premium"
        case .CNG: "CNG"
        case .EV: "EV"
        }
    }
    var unit: String { self == .CNG ? "kg" : self == .EV ? "kWh" : "L" }
    var symbol: String {
        switch self {
        case .PETROL, .PREMIUM_PETROL: "fuelpump.fill"
        case .DIESEL: "drop.fill"
        case .CNG: "flame.fill"
        case .EV: "bolt.car.fill"
        }
    }
}

struct User: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var phone: String
    var email: String?
    var role: Role
    var status: AccountStatus
    var cardNumber: String
    var points: Int
    var tier: Tier
    var lifetimeSpend: Double
    var referralCode: String
    var avatarUrl: String?
    var googleLinked: Bool?
    var verifiedAt: Date?
    var createdAt: Date
    var vehicles: [Vehicle]?

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var qrPayload: String { "FS:" + cardNumber.replacingOccurrences(of: " ", with: "") }
}

struct AuthResponse: Decodable { let token: String; let user: User }

struct TierProgress: Codable {
    let tier: Tier
    let nextTier: Tier?
    let lifetimeSpend: Double
    let nextTierAt: Double?
    let remaining: Double
    let progress: Double
    let multiplier: Double
    let pointValueInr: Double
}

struct MeResponse: Decodable { let user: User; let tierProgress: TierProgress }

struct Vehicle: Codable, Identifiable, Hashable {
    let id: String
    var regNumber: String
    var nickname: String?
    var make: String?
    var model: String?
    var fuelType: FuelType
    var isDefault: Bool

    var displayName: String { nickname?.isEmpty == false ? nickname! : [make, model].compactMap { $0 }.joined(separator: " ").ifEmpty(regNumber) }
}

struct FuelPrice: Codable, Identifiable {
    var id: String { fuelType.rawValue }
    let fuelType: FuelType
    let unit: String
    let price: Double
    let previousPrice: Double
    let change: Double
    let updatedAt: Date
}

struct Transaction: Codable, Identifiable, Hashable {
    let id: String
    let invoiceNo: String
    let fuelType: FuelType
    let quantity: Double
    let pricePerUnit: Double
    let amount: Double
    let odometerKm: Int?
    let pointsEarned: Int
    let createdAt: Date
    let vehicle: Vehicle?
    let user: MiniUser?
}

struct MiniUser: Codable, Hashable { let name: String; let phone: String }

struct Paged<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?
    let page: Int
    let limit: Int
}

struct LedgerEntry: Codable, Identifiable {
    let id: String
    let type: String
    let points: Int
    let note: String?
    let createdAt: Date
}

struct PointsPage: Decodable { let balance: Int; let items: [LedgerEntry]; let total: Int }

struct Reward: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let pointsCost: Int
    let imageUrl: String?
    let category: String
    let stock: Int?
    let active: Bool?

    var symbol: String {
        switch category {
        case "Fuel": "fuelpump.fill"
        case "Services": "sparkles"
        case "Lubricants": "drop.triangle.fill"
        case "Store": "bag.fill"
        default: "gift.fill"
        }
    }
}

struct Redemption: Codable, Identifiable {
    let id: String
    let code: String
    let pointsUsed: Int
    let status: String
    let usedAt: Date?
    let createdAt: Date
    let reward: Reward
}

struct Offer: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let imageUrl: String?
    let couponCode: String?
    let bonusPoints: Int
    let minTier: Tier
    let startsAt: Date
    let endsAt: Date
}

struct UserCoupon: Codable, Identifiable { let id: String; let usedAt: Date?; let createdAt: Date; let offer: Offer }

enum ServiceType: String, Codable, CaseIterable, Identifiable {
    case CAR_WASH, OIL_CHANGE, PUC_TEST, TYRE_CHECK, GENERAL_SERVICE
    var id: String { rawValue }
    var title: String {
        switch self {
        case .CAR_WASH: "Car Wash"
        case .OIL_CHANGE: "Oil Change"
        case .PUC_TEST: "PUC Test"
        case .TYRE_CHECK: "Tyre Check"
        case .GENERAL_SERVICE: "General Service"
        }
    }
    var symbol: String {
        switch self {
        case .CAR_WASH: "car.side.rear.and.collision.and.car.side.front"
        case .OIL_CHANGE: "oilcan.fill"
        case .PUC_TEST: "aqi.medium"
        case .TYRE_CHECK: "tirepressure"
        case .GENERAL_SERVICE: "wrench.and.screwdriver.fill"
        }
    }
}

struct Booking: Codable, Identifiable {
    let id: String
    let service: ServiceType
    let slot: Date
    let vehicleReg: String?
    let notes: String?
    let status: String
    let user: MiniUser?
}

enum ReminderType: String, Codable, CaseIterable, Identifiable {
    case PUC, INSURANCE, SERVICE, TYRE, CUSTOM
    var id: String { rawValue }
    var title: String {
        switch self {
        case .PUC: "PUC Expiry"
        case .INSURANCE: "Insurance Renewal"
        case .SERVICE: "Vehicle Service"
        case .TYRE: "Tyre Check"
        case .CUSTOM: "Custom"
        }
    }
    var symbol: String {
        switch self {
        case .PUC: "leaf.fill"
        case .INSURANCE: "shield.lefthalf.filled"
        case .SERVICE: "wrench.adjustable.fill"
        case .TYRE: "tirepressure"
        case .CUSTOM: "bell.fill"
        }
    }
}

struct Reminder: Codable, Identifiable {
    let id: String
    var type: ReminderType
    var title: String
    var dueDate: Date
    var vehicleReg: String?
    var done: Bool

    var daysLeft: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0 }
}

struct AppNotification: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let kind: String
    var read: Bool
    let createdAt: Date

    var symbol: String {
        switch kind {
        case "POINTS": "star.circle.fill"
        case "REWARD": "gift.fill"
        case "TIER": "crown.fill"
        case "BOOKING": "calendar"
        case "ACCOUNT": "checkmark.seal.fill"
        case "FEEDBACK": "bubble.left.and.bubble.right.fill"
        default: "megaphone.fill"
        }
    }
}

struct NotificationsPage: Decodable { let items: [AppNotification] }

struct Feedback: Codable, Identifiable {
    let id: String
    let rating: Int
    let category: String
    let message: String
    let reply: String?
    let status: String
    let createdAt: Date
    let user: MiniUser?
}

struct Station: Codable {
    var name: String
    var brand: String
    var tagline: String
    var address: String
    var city: String
    var state: String
    var pincode: String
    var phone: String
    var whatsapp: String
    var email: String
    var latitude: Double
    var longitude: Double
    var openHours: String
    var services: [String]
    var availableFuels: [FuelType]
}

struct Announcement: Codable, Identifiable { let id: String; let title: String; let body: String; let createdAt: Date }

struct MonthSummary: Codable { let spend: Double; let quantity: Double; let points: Int; let visits: Int }

struct Dashboard: Decodable {
    let user: User
    let tierProgress: TierProgress
    let month: MonthSummary
    let recentTransactions: [Transaction]
    let unreadNotifications: Int
    let offers: [Offer]
    let upcomingReminders: [Reminder]
    let vehicles: [Vehicle]
}

struct Insights: Decodable {
    struct Month: Decodable, Identifiable { var id: String { month }; let month: String; let spend: Double; let quantity: Double; let visits: Int; let points: Int }
    struct FuelSpend: Decodable, Identifiable { var id: FuelType { fuelType }; let fuelType: FuelType; let spend: Double }
    struct Mileage: Decodable, Identifiable { var id: String { vehicleId }; let vehicleId: String; let regNumber: String?; let km: Int; let quantity: Double; let kmPerUnit: Double? }
    let monthly: [Month]
    let byFuel: [FuelSpend]
    let mileage: [Mileage]
}

struct Referrals: Decodable {
    struct Friend: Decodable, Identifiable { var id: String { name + createdAt.description }; let name: String; let status: AccountStatus; let createdAt: Date }
    let code: String
    let referred: [Friend]
}

// Staff
struct LookupResult: Decodable { let user: User; let vehicles: [Vehicle] }
struct FillResult: Decodable { let transaction: Transaction; let pointsEarned: Int; let tierUpgrade: Tier? }
struct ShiftSummary: Decodable { let count: Int; let total: Double; let items: [Transaction] }
struct UseRedemptionResult: Decodable { let redemption: Redemption; let customer: MiniUser }

// Admin
struct Analytics: Decodable {
    struct Today: Decodable { let sales: Double; let quantity: Double; let count: Int }
    struct Period: Decodable { let days: Int; let sales: Double; let quantity: Double; let count: Int; let pointsIssued: Int; let redemptions: Int }
    struct FuelRow: Decodable, Identifiable { var id: FuelType { fuelType }; let fuelType: FuelType; let sales: Double; let quantity: Double }
    struct Day: Decodable, Identifiable { var id: String { date }; let date: String; let sales: Double }
    struct TopCustomer: Decodable, Identifiable { let id: String?; let name: String?; let phone: String?; let tier: Tier?; let spend: Double; let visits: Int }
    let pendingVerifications: Int
    let members: Int
    let newMembers: Int
    let today: Today
    let period: Period
    let byFuel: [FuelRow]
    let topCustomers: [TopCustomer]
    let dailySales: [Day]
    let openFeedback: Int
    let upcomingBookings: Int
}

struct BulkResult: Decodable { struct Row: Decodable { let id: String; let ok: Bool; let error: String? }; let results: [Row] }

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
