import SwiftUI
import XCTest
@testable import ReadLoop

@MainActor
final class ComponentSnapshotTests: XCTestCase {
    func testButtonsLight() throws {
        try DesignSystemSnapshot.assert(
            buttonSample,
            named: "buttons-light",
            size: CGSize(width: 360, height: 190),
            colorScheme: .light
        )
    }

    func testButtonsDark() throws {
        try DesignSystemSnapshot.assert(
            buttonSample,
            named: "buttons-dark",
            size: CGSize(width: 360, height: 190),
            colorScheme: .dark
        )
    }

    func testListRowLight() throws {
        try DesignSystemSnapshot.assert(
            listRowSample,
            named: "list-row-light",
            size: CGSize(width: 360, height: 150),
            colorScheme: .light
        )
    }

    func testListRowDark() throws {
        try DesignSystemSnapshot.assert(
            listRowSample,
            named: "list-row-dark",
            size: CGSize(width: 360, height: 150),
            colorScheme: .dark
        )
    }

    func testSectionHeaderLight() throws {
        try DesignSystemSnapshot.assert(
            sectionHeaderSample,
            named: "section-header-light",
            size: CGSize(width: 360, height: 100),
            colorScheme: .light
        )
    }

    func testSectionHeaderDark() throws {
        try DesignSystemSnapshot.assert(
            sectionHeaderSample,
            named: "section-header-dark",
            size: CGSize(width: 360, height: 100),
            colorScheme: .dark
        )
    }

    func testBannerLight() throws {
        try DesignSystemSnapshot.assert(
            bannerSample,
            named: "banner-light",
            size: CGSize(width: 360, height: 150),
            colorScheme: .light
        )
    }

    func testBannerDark() throws {
        try DesignSystemSnapshot.assert(
            bannerSample,
            named: "banner-dark",
            size: CGSize(width: 360, height: 150),
            colorScheme: .dark
        )
    }

    private var buttonSample: some View {
        VStack(spacing: ElsepageSpacing.md) {
            ElsepageButton(
                title: "继续阅读",
                systemImage: "bookmark",
                role: .primary,
                action: {}
            )
            ElsepageButton(
                title: "次要操作",
                role: .secondary,
                action: {}
            )
        }
        .padding(ElsepageSpacing.lg)
    }

    private var listRowSample: some View {
        ElsepageCard(padding: 0) {
            ElsepageListRow(
                title: "ReadLoop Foundation Fixture",
                subtitle: "ReadLoop Contributors",
                metadata: "读到 42% · 12 分钟",
                systemImage: "book.closed",
                showsChevron: true,
                action: {}
            )
        }
        .padding(ElsepageSpacing.lg)
    }

    private var sectionHeaderSample: some View {
        ElsepageSectionHeader(
            title: "全部书籍",
            count: 12,
            actionTitle: "排序",
            action: {}
        )
        .padding(ElsepageSpacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bannerSample: some View {
        ElsepageBanner(
            style: .success,
            title: "已保存到本机",
            message: "这次阅读的想法会先留在设备上。",
            actionTitle: "查看",
            action: {}
        )
        .padding(ElsepageSpacing.lg)
    }
}
