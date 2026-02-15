# Whodunit: Agent Notes

This repo is a Swift Package (`Whodunit`) intended to answer:

- Given a file path, which running apps are "using" it?
- For each such app, is the app frontmost, and does it currently show the specified file?

The hard part is that different apps expose this differently (some via Apple Events "documents", some via Accessibility UI trees, some only via window titles), and many apps have custom tab implementations.

## Goals

- Provide a single, stable public API: `Whodunit.appsUsing(path)` returns candidate apps that have the file open.
- Ensure `AppUsage.showsSpecifiedFile` encapsulates app-specific "is this file visible right now?" logic (native tabs, custom editors, etc.).
- Use layered heuristics that degrade gracefully when permissions or app capabilities are missing.
- Keep per-app heuristics isolated and testable.

Non-goals (for now):

- Controlling apps (opening files, changing tabs).
- Perfect accuracy for every macOS app out of the box.

## High-Level Architecture

- `RunningAppEnumerator`: Lists running, user-facing apps and resolves `bundleID` + `pid`.
- `FrontmostAppResolver`: Determines which app is frontmost via `NSWorkspace` (used to fill `AppUsage.isFrontmost`).
- `WindowSnapshotter`: Gathers window metadata using `CGWindowListCopyWindowInfo` (lightweight list) and Accessibility (deeper UI inspection).
- `DetectorPipeline`: For a given `(app, path)`, runs detectors in order and merges into a single `AppUsage` (and optional debug steps).
- `HeuristicRegistry`: Holds built-in and user-provided heuristics. Selects applicable heuristics for an app via match rules (bundle id, bundle id prefix, regex), with priority/override support.
- `AppDetectors`: Concrete heuristics (document enumeration, tab visibility, title parsing, etc.) selected by the registry.
- `PathNormalizer`: Normalizes file URLs/paths for matching (symlinks, `~`, percent-encoding) while staying conservative (never invent paths).

## Heuristics (Ordered Fallback)

The pipeline answers two questions:

- "Is the file open in this app?" (to decide if the app should be returned by `appsUsing`)
- "Is the file visible right now?" (to compute `showsSpecifiedFile`)

Ordered fallback:

1. Apple Events "documents": If scriptable, enumerate open document file URLs/paths (best signal for "open").
2. Accessibility focus: Find focused window and focused editor element; extract title/path from tab titles, navigation bars, and editor title labels (best signal for "visible").
3. Accessibility tab bar: If tabs are discoverable, identify the selected tab item and infer its represented file.
4. Window title parsing: Parse the frontmost window title for file/path patterns; treat as low-confidence unless the app is known to embed full paths.

## App-Specific Tab Logic

`showsSpecifiedFile` is where app families diverge. The detector selection should prefer bundle id matching, with shared implementations for families like:

- Native macOS tabs (standard tab groups)
- VS Code and forks (Electron)
- Chromium-based apps (Chrome, Arc-like patterns, etc.)

Keep these as separate detectors so we can iterate without destabilizing other apps.

## Extensibility (User-Provided Heuristics)

The architecture must support three things:

- Encapsulate app-specific logic behind small, testable heuristic units.
- Allow users of the library to register their own heuristics (including overrides for built-ins).
- Allow one heuristic implementation to apply to multiple apps (for "families" like Chromium browsers) using match rules.

Planned design:

- `AppMatchRule` (how a heuristic declares applicability) supports exact bundle id match (e.g. `com.apple.dt.Xcode`), bundle id prefix match (e.g. VS Code forks), and regex match for complex families (used sparingly).
- `HeuristicProvider` protocol provides one or more detectors for matching apps and includes a `priority` so user-registered providers can override built-ins deterministically.
- `DetectionOptions` includes registry configuration: default uses built-ins only; advanced callers can append providers or override/replace the built-in provider set.

This is the mechanism that lets "Chromium tab visibility" logic be implemented once and then attached to many bundle ids (Chrome, Chromium, Brave, etc.) without duplicating code.

Registry selection rules (planned):

- Order by `priority` (higher first), then by match specificity (exact > prefix > regex) so overrides behave predictably.
- Multiple providers may apply to the same app; the pipeline runs all applicable detectors and merges into a single `AppUsage`.
- A single provider can ship a family heuristic plus a list of bundle ids/prefixes it applies to (e.g. "Chromium tabs").

## Public API Shape (Planned)

- `Whodunit.appsUsing(_ path: String, options: DetectionOptions) -> [AppUsage]`
- `AppUsage` fields: `bundleID: String`, `pid: pid_t`, `isFrontmost: Bool`, `showsSpecifiedFile: Bool`, `debug: [DetectionStep]?`

Intended usage:

```swift
let apps = Whodunit.appsUsing(path)
for app in apps {
    print(app.isFrontmost && app.showsSpecifiedFile)
}
```

If we need richer output later, add it without breaking the `appsUsing` ergonomics (e.g. opt-in debug output or a separate API returning a full trace).

## Permissions And Operational Constraints

- Accessibility permission is required for reliable "visible" detection in most apps.
- Apple Events access may require user consent, and may be blocked in sandboxed contexts.
- Some apps do not expose enough metadata to reliably map a tab title to an on-disk path; in those cases `showsSpecifiedFile` should stay conservative (typically `false`) and `debug` should explain the limitation.

## Testing Strategy

- Unit tests for title parsing and path normalization using fixtures.
- Unit tests for detector selection and result merging (including debug trace output).
- Integration tests (optional / local-only) that require Accessibility permission and validate end-to-end detection for a small set of well-known apps (start with Xcode).

## Roadmap

1. Implement `PathNormalizer` and basic models (`AppUsage`, `DetectionStep`, `DetectionOptions`).
2. Implement `RunningAppEnumerator` and `FrontmostAppResolver`.
3. Implement an "open file" detector (Apple Events "documents") and a low-confidence window-title detector.
4. Implement Accessibility-based "visible file" detection (focused window / focused editor extraction).
5. Add the first per-app detector (start with Xcode; then expand to editor families like VS Code forks and Chromium-based apps).
6. Add an opt-in integration test harness.
