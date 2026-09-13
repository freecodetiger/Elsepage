import Foundation

/// Chinese-first app date formatting. User-facing UI must not depend on the
/// device's system language to decide whether months render as English names.
public enum ElsepageDateFormat {
    public static let zhHans = Locale(identifier: "zh_Hans_CN")

    public static func monthTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month(.wide).locale(zhHans))
    }

    public static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month().day().locale(zhHans))
    }

    public static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month().day().hour().minute().locale(zhHans))
    }

    public static func yearMonthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month().day().locale(zhHans))
    }

    public static func yearMonth(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month(.wide).locale(zhHans))
    }
}
