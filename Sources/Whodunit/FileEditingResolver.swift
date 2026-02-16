import Foundation

import AppKit

public struct FileEditingResolver: Sendable {
    public let target: URL
    public let apps: [AppUsage]

    public init?(_ path: String, options: DetectionOptions = .default) {
        guard let targetURL = PathNormalizer.fileURL(from: path) else { return nil }
        self.target = targetURL

        let allApps = RunningAppEnumerator.enumerate()
        let frontmostPID = FrontmostAppResolver.frontmostPID()

        var results: [AppUsage] = []
        results.reserveCapacity(allApps.count)

        for running in allApps {
            let usage = DetectorPipeline.evaluate(
                app: running,
                target: targetURL,
                isFrontmost: running.pid == frontmostPID,
                options: options
            )
            if usage.displaysFile || usage.isTabDisplayingFileVisible {
                results.append(usage)
            }
        }

        self.apps = results
    }
}
