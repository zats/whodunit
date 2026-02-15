import Testing
@testable import Whodunit

@Test func pathNormalizerFileURLRejectsEmpty() async throws {
    #expect(PathNormalizer.fileURL(from: "") == nil)
    #expect(PathNormalizer.fileURL(from: "   ") == nil)
}

@Test func pathNormalizerAcceptsFileURLString() async throws {
    let url = PathNormalizer.fileURL(from: "file:///tmp/test.txt")
    #expect(url?.isFileURL == true)
    #expect(url?.path == "/tmp/test.txt")
}

@Test func registryDefaultsContainFallback() async throws {
    #expect(AppMatchRule.any.matches(bundleID: "com.apple.TextEdit"))
    #expect(AppMatchRule.bundleID("com.apple.TextEdit").matches(bundleID: "com.apple.TextEdit"))
    #expect(!AppMatchRule.bundleID("com.apple.TextEdit").matches(bundleID: "com.apple.Safari"))
    #expect(AppMatchRule.bundleIDPrefix("com.apple.").matches(bundleID: "com.apple.TextEdit"))
    #expect(!AppMatchRule.bundleIDPrefix("com.apple.dt.").matches(bundleID: "com.apple.TextEdit"))
    #expect(AppMatchRule.bundleIDRegex("^com\\.apple\\..+$").matches(bundleID: "com.apple.TextEdit"))
}
