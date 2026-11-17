import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import ReadLoop

@MainActor
enum DesignSystemSnapshot {
    /// Set `SNAPSHOT_RECORD=1` in the test environment (Scheme → Test →
    /// Arguments) to re-record the reference PNGs, then commit them.
    static var recordMode: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    static func assert<V: View>(
        _ view: V,
        named name: String,
        size: CGSize,
        colorScheme: ColorScheme,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let content =
            view
            .frame(width: size.width, height: size.height)
            .background(ElsepageColor.canvas)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)

        guard let image = renderer.uiImage else {
            XCTFail("Could not render snapshot \(name)", file: file, line: line)
            return
        }

        // Perceptual comparison keeps antialiasing and system-font tweaks from
        // turning every OS update into a wall of false failures.
        assertSnapshot(
            of: image,
            as: .image(precision: 0.99, perceptualPrecision: 0.98),
            record: recordMode ? .all : nil,
            file: file,
            testName: name,
            line: line
        )
    }
}
