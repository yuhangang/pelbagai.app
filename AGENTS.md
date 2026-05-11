# Pelbagai Agent Guide

This file is the operating contract for AI agents and humans changing this repo.
Keep it current when architecture, validation commands, documentation policy, or
project structure changes.

## Project Shape

Pelbagai is a SwiftUI app built from `pelbagai.xcodeproj`. It combines on-device
chat, speech, vision scanning, local tools, structured extraction, and local
persistence.

Current ownership boundaries:

- `PelbagaiApp.swift` and `MainView.swift`: app entry, tab routing, and high-level
  navigation only.
- `ChatView.swift`, `ScannerView.swift`, `ToolDataView.swift`, `ContentView.swift`:
  SwiftUI presentation and user interaction. Keep domain parsing, database
  writes, model lifecycle, and audio/session policy out of large `body` blocks.
- `GemmaManager.swift`, `VisionManager.swift`, `WhisperManager.swift`: model
  lifecycle and inference state. They are `@MainActor` observable managers and
  must guard concurrent loads/generation/processing.
- `AudioService.swift` and `SpeechService.swift`: AVFoundation input/output
  services. Keep audio-session side effects here instead of scattering them
  through views.
- `DatabaseManager.swift`: GRDB-backed chat session/message persistence.
- `ToolStorage.swift`: JSON file storage for scan/tool results.
- `ScanResult.swift`: scan templates, local tool definitions, prompt contracts,
  field data types, declarative tool actions, and CSV-facing model compatibility.
- `ScriptEngine.swift`: legacy no-op compatibility shim. Model-produced scripts
  must not execute; route new behavior through Swift-owned `ToolAction` handling.
- `ExcelExporter.swift`: export formatting and file generation.

## Architecture Rules

Preserve the separation between UI, model managers, services, and persistence.
SwiftUI views may coordinate user intent, but durable behavior belongs in the
manager/service/storage layer.

Do not add a second source of truth for model state, recording state, selected
model, chat history, or stored scan results. Route state through the existing
managers unless the change explicitly introduces a new bounded store.

Model lifecycle changes must handle memory pressure and cancellation. Any new
Gemma, Vision, or Whisper path needs clear loading, loaded, active, failure, and
unload behavior. Never start a new model load/generation while the matching
manager is already active unless the manager explicitly serializes that work.

Keep prompt and tool protocols strict. If local tools are added, update the tool
enum, parser, system prompt, execution branch, and tests or manual verification
notes together. The model must not expose XML tags, JSON protocol details, or
internal rules in user-facing answers.

Persistence changes must be migration-safe. Append GRDB migrations instead of
rewriting existing schema assumptions. Preserve JSON backward compatibility in
`ToolStorage` and `ScanResult` unless a documented migration is included.

Treat local tool output as declarative data. Do not grant model-produced content
network, filesystem, database, script, or UI powers. Keep web loading as an
explicit caller-owned `ToolAction.openURL` handoff with URL validation and user
approval.

Prefer small dedicated SwiftUI subviews over very large computed views when a
screen grows. Extract components around real concepts such as message bubbles,
scan result cards, input controls, tool summaries, and export actions.

## Best Practices

Use structured Swift APIs rather than string parsing when the platform gives one.
For JSON, database rows, dates, file URLs, CSV, audio buffers, and model output
cleaning, keep parsing centralized and covered by focused checks.

Keep async work explicit. UI mutations from background callbacks must hop to
`@MainActor`. Avoid detached tasks unless ownership, cancellation, and lifetime
are obvious.

Keep user data local by default. Chat history, scan results, audio, images, and
model output should not leave the device unless a feature explicitly states that
contract in UI and documentation.

Avoid broad singletons beyond the existing app-level services. When adding new
stateful behavior, first decide whether it belongs in an existing manager, a new
isolated service, or a view-local state object.

Do not hide failures behind silent fallbacks. Surface model download, microphone,
speech, database, export, and parse failures through actionable status text or
logs that make debugging possible.

## Documentation Contract

Create or update `README.md` when setup, dependencies, permissions, model
downloads, platform targets, user-visible features, or manual verification steps
change.

Create or update `system_design.md` when architecture changes materially:
manager ownership, model lifecycle, storage schema, script execution, local tool
protocols, scanner pipeline, export flow, or cross-screen state.

Update release notes or a changelog if one exists when behavior changes are
user-visible. If no changelog exists, mention the user-visible change in the
final handoff and consider creating one for release work.

Update this `AGENTS.md` when validation commands, documentation expectations,
architecture boundaries, or harness policy change.

## Harness Engineering

Start every non-trivial change with:

```sh
git status --short
```

Treat a dirty worktree as normal. Do not revert or overwrite unrelated user
changes.

Minimum local checks after Swift changes:

```sh
xcodebuild -list -project pelbagai.xcodeproj
xcodebuild -resolvePackageDependencies -project pelbagai.xcodeproj
xcodebuild build -project pelbagai.xcodeproj -scheme pelbagai -destination 'generic/platform=iOS Simulator'
```

If an iOS test target is added, the default quality gate must become:

```sh
xcodebuild test -project pelbagai.xcodeproj -scheme pelbagai -destination 'platform=iOS Simulator,name=<available simulator>'
```

When the sandbox blocks Xcode from writing to `~/Library/Developer`,
`~/Library/Caches/org.swift.swiftpm`, or CoreSimulator logs, record the failure
and rerun with an approved environment instead of treating the build as verified.

For model, audio, camera, scanner, export, database, or script changes, compile
success is not enough. Add the narrowest reliable harness you can:

- unit tests for pure parsing, prompt/tool parsing, JSON migration, CSV/export
  formatting, and script transforms;
- integration checks for GRDB migrations and `ToolStorage` read/write behavior;
- manual simulator/device checks for microphone, speech output, camera/photo
  picker, model download, streaming response, and export share sheet.

Do not introduce "AI slop" guardrails as prose only. If a class of regression is
important, add a runnable check, a test target, a fixture, a script, or a CI step.
Docs explain the guardrail; the harness enforces it.

## Change Checklist

Before handing off, confirm:

- architecture boundaries stayed intact or `system_design.md` explains the new
  boundary;
- documentation was updated for user-visible or setup-affecting behavior;
- relevant build/test/manual checks were run, or the blocker is stated plainly;
- model prompts, local tools, storage schemas, and export formats remain backward
  compatible or include a migration path;
- no unrelated user work was reverted.
