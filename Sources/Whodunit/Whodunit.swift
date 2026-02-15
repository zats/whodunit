import Foundation

#if os(macOS)

/// Namespace entrypoint for common operations.
public enum Whodunit {
    public static func appsUsing(_ path: String, options: DetectionOptions = .default) -> [AppUsage] {
        guard let resolver = FileEditingResolver(path, options: options) else { return [] }
        return resolver.apps
    }
}

#endif
