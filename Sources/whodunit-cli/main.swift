import Foundation
import Whodunit

private struct OutputLine: Encodable {
    struct App: Encodable {
        let pid: String
        let name: String
        let bundleID: String
    }

    let app: App
    let isFrontmost: Bool
    let hasTabs: Bool
    let isFileTabVisible: Bool
}

private func usage() -> Never {
    fputs("usage: whodunit <PATH> [--jsonl]\\n", stderr)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, !path.hasPrefix("-") else { usage() }

let jsonl = args.contains("--jsonl")

guard let resolver = FileEditingResolver(path) else {
    fputs("invalid path\\n", stderr)
    exit(2)
}

let encoder = JSONEncoder()
encoder.outputFormatting = []

if jsonl {
    for app in resolver.apps {
        let line = OutputLine(
            app: .init(pid: String(app.pid), name: app.name, bundleID: app.bundleID),
            isFrontmost: app.isFrontmost,
            hasTabs: app.hasTabs,
            isFileTabVisible: app.isTabDisplayingFileVisible
        )
        let data = try encoder.encode(line)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
} else {
    for app in resolver.apps {
        print("\(app.name) pid=\(app.pid) frontmost=\(app.isFrontmost) hasTabs=\(app.hasTabs) visible=\(app.isTabDisplayingFileVisible)")
    }
}
