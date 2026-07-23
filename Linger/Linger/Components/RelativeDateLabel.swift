import Foundation

/// 将拍摄日期格式化为「N 年前 / N 个月前 / 今天」等相对文案
enum RelativeDateLabel {
    static func text(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "未知日期" }

        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        if let years = components.year, years >= 1 {
            return "\(years) 年前"
        }
        if let months = components.month, months >= 1 {
            return "\(months) 个月前"
        }
        if let days = components.day {
            if days >= 1 {
                return "\(days) 天前"
            }
            return "今天"
        }
        return "今天"
    }
}
