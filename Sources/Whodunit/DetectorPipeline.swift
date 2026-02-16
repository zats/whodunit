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
        let allCandidates = options.registry.applicable(to: app)

        // If we have any app-specific heuristics, skip negative-priority `.any` fallbacks.
        // This prevents generic tab-title fallbacks from producing false positives in apps
        // like VS Code (where multiple unrelated files can share the same basename).
        let hasSpecific = allCandidates.contains(where: { $0.match.specificity > 0 })
        let candidates: [HeuristicRegistry.Entry]
        if hasSpecific {
            candidates = allCandidates.filter { $0.match.specificity > 0 || $0.priority >= 0 }
        } else {
            candidates = allCandidates
        }

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
