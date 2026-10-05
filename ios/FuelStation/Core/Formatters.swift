import Foundation

enum Fmt {
    private static let inr: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 2
        return f
    }()

    private static let inrWhole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 0
        return f
    }()

    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 2
        return f
    }()

    static func rupees(_ v: Double) -> String { inr.string(from: v as NSNumber) ?? "₹\(v)" }
    static func rupeesShort(_ v: Double) -> String {
        if v >= 1_00_00_000 { return String(format: "₹%.1fCr", v / 1_00_00_000) }
        if v >= 1_00_000 { return String(format: "₹%.1fL", v / 1_00_000) }
        if v >= 10_000 { return String(format: "₹%.1fK", v / 1000) }
        return inrWhole.string(from: v as NSNumber) ?? "₹\(v)"
    }
    static func number(_ v: Double) -> String { grouped.string(from: v as NSNumber) ?? "\(v)" }
    static func points(_ v: Int) -> String { grouped.string(from: v as NSNumber) ?? "\(v)" }

    static func phone(_ p: String) -> String {
        guard p.count == 10 else { return p }
        return "+91 \(p.prefix(5)) \(p.suffix(5))"
    }

    static func monthLabel(_ ym: String) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return ym }
        return Calendar.current.shortMonthSymbols[m - 1]
    }
}

extension Date {
    var relative: String { formatted(.relative(presentation: .named)) }
    var dayMonth: String { formatted(.dateTime.day().month(.abbreviated)) }
    var dayMonthYearTime: String { formatted(.dateTime.day().month(.abbreviated).year().hour().minute()) }
}

func greeting() -> String {
    switch Calendar.current.component(.hour, from: .now) {
    case 5..<12: "Good morning"
    case 12..<17: "Good afternoon"
    default: "Good evening"
    }
}
