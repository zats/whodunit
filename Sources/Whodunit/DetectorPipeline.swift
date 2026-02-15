import Foundation

#if os(macOS)

enum DetectorPipeline {
    static func evaluate(
        app: AppDescriptor,
        target: URL,
        isFrontmost: Bool,
        options: DetectionOptions
    ) -> AppUsage {
        let normalizedTarget = PathNormalizer.normalizeFileURL(target)
        let candidates = options.registry.applicable(to: app)

        var displays = false
        var visible = false
        var hasTabs = false
        var steps: [DetectionStep] = []

        for entry in candidates {
            guard let result = entry.run(app, normalizedTarget) else { continue }

            if result.displaysFile == true { displays = true }
            if result.visibleFile == true { visible = true }
            if result.hasTabs == true { hasTabs = true }

            if options.includeDebug {
                steps.append(DetectionStep(name: entry.name, notes: result.debug))
            }
        }

        if visible { displays = true }

        return AppUsage(
            bundleID: app.bundleID,
            pid: app.pid,
            name: app.name,
            isFrontmost: isFrontmost,
            hasTabs: hasTabs,
            displaysFile: displays,
            isTabDisplayingFileVisible: visible,
            debug: options.includeDebug ? steps : nil
        )
    }
}

#endif
