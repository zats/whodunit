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
    fputs("usage: whodunit [--jsonl|--json|--csv|--tsv] <PATH>\\n", stderr)
    exit(2)
}

enum OutputFormat {
    case text
    case jsonl
    case json
    case csv
    case tsv
}

let args = Array(CommandLine.arguments.dropFirst())
var format: OutputFormat = .text
var path: String?

for arg in args {
    switch arg {
    case "--jsonl":
        format = .jsonl
    case "--json":
        format = .json
    case "--csv":
        format = .csv
    case "--tsv":
        format = .tsv
    case "--help", "-h":
        usage()
    default:
        if arg.hasPrefix("-") { usage() }
        if path == nil {
            path = arg
        } else {
            usage()
        }
    }
}

guard let path else { usage() }

guard let resolver = FileEditingResolver(path) else {
    fputs("invalid path\\n", stderr)
    exit(2)
}

let encoder = JSONEncoder()
encoder.outputFormatting = []

func escapeDelimited(_ s: String, delimiter: Character) -> String {
    if s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.contains("\t") {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return s
}

switch format {
case .jsonl:
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
case .json:
    let lines: [OutputLine] = resolver.apps.map { app in
        OutputLine(
            app: .init(pid: String(app.pid), name: app.name, bundleID: app.bundleID),
            isFrontmost: app.isFrontmost,
            hasTabs: app.hasTabs,
            isFileTabVisible: app.isTabDisplayingFileVisible
        )
    }
    let data = try encoder.encode(lines)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
case .csv, .tsv:
    let delimiter: Character = (format == .tsv) ? "\t" : ","
    let sep = String(delimiter)
    print(["pid", "name", "bundleID", "isFrontmost", "hasTabs", "isFileTabVisible"].joined(separator: sep))
    for app in resolver.apps {
        let cols: [String] = [
            escapeDelimited(String(app.pid), delimiter: delimiter),
            escapeDelimited(app.name, delimiter: delimiter),
            escapeDelimited(app.bundleID, delimiter: delimiter),
            String(app.isFrontmost),
            String(app.hasTabs),
            String(app.isTabDisplayingFileVisible),
        ]
        print(cols.joined(separator: sep))
    }
case .text:
    for app in resolver.apps {
        print("\(app.name) pid=\(app.pid) frontmost=\(app.isFrontmost) hasTabs=\(app.hasTabs) visible=\(app.isTabDisplayingFileVisible)")
    }
}
