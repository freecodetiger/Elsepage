import XCTest

/// App/ is compiled only by the Xcode target, not by `swift test`, so a new
/// App file that was never registered into project.pbxproj (via xcodegen)
/// silently fails the user's build with "cannot find X in scope". This test
/// keeps target membership honest: every Swift file under App/ must appear
/// in the generated project.
final class XcodeProjectMembershipTests: XCTestCase {
    func testEveryAppSwiftFileIsRegisteredInXcodeProject() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/ReadLoopCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root

        let appDir = repoRoot.appendingPathComponent("App")
        let pbxproj = try String(
            contentsOf: repoRoot.appendingPathComponent("ReadLoop.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        let enumerator = try FileManager.default
            .enumerator(at: appDir, includingPropertiesForKeys: nil)
        let appFiles = (enumerator?.allObjects ?? [])
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { $0.lastPathComponent }
            .sorted()

        XCTAssertFalse(appFiles.isEmpty, "App/ 应包含 Swift 源文件;若目录结构变更,请同步更新本测试")

        let missing = appFiles.filter { !pbxproj.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            """
            以下 App/ 文件未登记进 ReadLoop.xcodeproj(用户 xcodebuild 将失败):
            \(missing.joined(separator: "\n"))
            在仓库根目录运行 `xcodegen` 重新生成工程后重试。
            """
        )
    }
}
