import Foundation

enum PathNormalizer {
    static func fileURL(from path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return normalizeFileURL(url)
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        return normalizeFileURL(URL(fileURLWithPath: expanded))
    }

    static func normalizeFileURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        if FileManager.default.fileExists(atPath: path) {
            return standardized.resolvingSymlinksInPath()
        }
        return standardized
    }
}

