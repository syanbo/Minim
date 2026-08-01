import XCTest
@testable import MinimCore

final class ReleaseVersionTests: XCTestCase {

    func testParsesPlainAndTagged() {
        XCTAssertEqual(ReleaseVersion("1.2.3"), ReleaseVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(ReleaseVersion("v1.2.3"), ReleaseVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(ReleaseVersion(" v1.0.0 "), ReleaseVersion(major: 1, minor: 0, patch: 0))
    }

    func testShortFormsPadWithZero() {
        XCTAssertEqual(ReleaseVersion("2"), ReleaseVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(ReleaseVersion("2.1"), ReleaseVersion(major: 2, minor: 1, patch: 0))
    }

    func testRejectsGarbage() {
        for bad in ["", "abc", "1.2.3.4", "1..2", "-1.0.0", "1.2.x", "v"] {
            XCTAssertNil(ReleaseVersion(bad), "「\(bad)」不该被解析成版本号")
        }
    }

    /// 字符串比较会把 1.10.0 误判成小于 1.9.0（逐字符比，'1' < '9'），
    /// 于是发布 1.10.0 后装着 1.9.0 的用户收不到更新提示。这就是要按数字比的原因
    func testNumericOrderingNotLexicographic() {
        XCTAssertTrue("1.10.0" < "1.9.0")    // 字符串比较：错的
        XCTAssertTrue(ReleaseVersion("1.9.0")! < ReleaseVersion("1.10.0")!)   // 数字比较：对的

        XCTAssertTrue(ReleaseVersion("1.0.9")! < ReleaseVersion("1.0.10")!)
        XCTAssertTrue(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!)
    }

    func testEqualityAndOrdering() {
        XCTAssertEqual(ReleaseVersion("1.0.0"), ReleaseVersion("v1.0.0"))
        XCTAssertFalse(ReleaseVersion("1.0.0")! < ReleaseVersion("1.0.0")!)
        XCTAssertTrue(ReleaseVersion("1.0.0")! < ReleaseVersion("1.0.1")!)
    }

    func testDescriptionRoundTrips() {
        XCTAssertEqual(ReleaseVersion("v2.1")!.description, "2.1.0")
    }
}
