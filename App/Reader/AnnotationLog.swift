import CoreGraphics
import os
import UIKit

/// Temporary diagnostics for the in-place annotation menus. Currently used to
/// pin down the intermittent "menu flashes then disappears" race on device:
/// every event that can open or close a menu is logged with a millisecond
/// timestamp so the closing event and its delay can be read off the trace.
/// Remove once the race is confirmed and fixed.
enum AnnotationLog {
    private static let logger = Logger(subsystem: "com.readloop.reader", category: "annotation")

    static func event(_ message: String) {
        let t = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        logger.log("[annot] t=\(t, privacy: .public) \(message, privacy: .public)")
    }

    static func id(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    static func rect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(format: "(%.0f,%.0f %.0fx%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
