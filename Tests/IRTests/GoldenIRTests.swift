import Testing

@testable import IR

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// TestURL wraps our test arguments to make their descriptions pretty
struct TestURL {
    var url: URL
}
extension TestURL: CustomTestStringConvertible {
    var testDescription: String { url.lastPathComponent }
}

func goldenFiles() -> [TestURL] {
    let files = Bundle.module.urls(
        forResourcesWithExtension: "json",
        subdirectory: "Fixtures"
    )!
    return files.map { TestURL(url: $0 as URL) }
}

@Test("testParsingGolden", arguments: goldenFiles())
func testParsingGolden(input: TestURL) async throws {
    let data = try Data(contentsOf: input.url)
    let _ = try JSONDecoder().decode(Policy.self, from: data)
}
