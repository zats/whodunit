import Foundation
import Whodunit

private struct OutputLine: Encodable {
    struct App: Encodable {
        let name: String
        let pid: Int
        let bundleId: String
        let frontmost: Bool
    }

    struct File: Encodable {
        let visibility: FileVisibility
    }

    let app: App
    let file: File
}

private func usage() -> Never {
    fputs("usage: whodunit [--jsonl|--json|--csv|--tsv] [-R|--reveal] <PATH>\n", stderr)
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
var reveal = false

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
    case "-R", "--reveal":
        reveal = true
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
    fputs("invalid path: \(path)\n", stderr)
    exit(2)
}

if reveal {
    guard resolver.apps.count == 1, let app = resolver.apps.first else {
        fputs("file is not detected as open: \(resolver.target.path)\n", stderr)
        exit(1)
    }

    guard Whodunit.reveal(path: resolver.target, in: app) else {
        fputs("file is not detected as open: \(resolver.target.path)\n", stderr)
        exit(1)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = []

func escapeDelimited(_ s: String, delimiter: Character) -> String {
    if s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.contains("\t") {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return s
}

private func makeLine(_ usage: AppUsage) -> OutputLine {
    OutputLine(
        app: .init(
            name: usage.name,
            pid: Int(usage.pid),
            bundleId: usage.bundleID,
            frontmost: usage.isFrontmost
        ),
        file: .init(visibility: usage.fileVisibility)
    )
}

switch format {
case .jsonl:
    for app in resolver.apps {
        let line = makeLine(app)
        let data = try encoder.encode(line)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
case .json:
    let lines = resolver.apps.map(makeLine)
    let data = try encoder.encode(lines)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
case .csv, .tsv:
    let delimiter: Character = (format == .tsv) ? "\t" : ","
    let sep = String(delimiter)
    print(["pid", "name", "bundleId", "frontmost", "visibility"].joined(separator: sep))
    for app in resolver.apps {
        let line = makeLine(app)
        let cols: [String] = [
            String(line.app.pid),
            escapeDelimited(line.app.name, delimiter: delimiter),
            escapeDelimited(line.app.bundleId, delimiter: delimiter),
            String(line.app.frontmost),
            line.file.visibility.rawValue,
        ]
        print(cols.joined(separator: sep))
    }
case .text:
    for app in resolver.apps {
        let line = makeLine(app)
        print("\(line.app.name) pid=\(line.app.pid) bundleId=\(line.app.bundleId) frontmost=\(line.app.frontmost) visibility=\(line.file.visibility.rawValue)")
    }
}
