# Pelbagai System Design

## Model Runtime

`GemmaManager` keeps the selected text model as the real Gemma 4 E2B/E4B MLX
checkpoint IDs. The project now pins to the SharpAI forks of
`mlx-swift-lm` and `mlx-swift` because upstream `ml-explore/mlx-swift`
did not yet expose a native `gemma4` model implementation for this app's use
case.

Model downloads now go through an app-owned bridge over the `Hub` and
`Tokenizers` modules from `swift-transformers` rather than the convenience
loader that shipped with `mlx-swift-examples`. `GemmaManager` and
`VisionManager` still use the same `ModelConfiguration` IDs, but loading now
depends on the forked MLX runtime plus that local downloader/tokenizer bridge.

Do not add compatibility shims that decode Gemma 4 config as Gemma3n config or
inject placeholder tensors. If this fork is removed later, replace it only with
an upstream runtime that exposes a real `gemma4` implementation.

`MLXModelManager` owns the resident text model container and the MLX cache
limit. Generation paths must release temporary cache pressure after each request
and must avoid redundant inference passes for app-owned data. The iOS target
includes the increased-memory-limit entitlement as a best-effort hint for
supported devices, but runtime behavior must remain correct when iOS does not
grant extra memory.

## Local Tool Protocol

Pelbagai uses a small local tool protocol instead of full MCP transport.
Built-in definitions are bundled in `LOCAL_TOOLS.json`, and user-created
definitions are persisted by `ToolRegistry` in Documents as
`local_tool_definitions.json`. `ScanTemplate.toolDefinition` remains a
compatibility adapter over the same definition shape.

Chat-owned built-in tools such as current time and battery level execute in
Swift. `GemmaManager` may detect explicit time/date/battery requests before
model generation, and if the model emits a built-in tool call, the manager
executes it and returns a Swift-formatted final answer without a second
follow-up model generation pass.

Local tool definitions describe the local tool ID, display name, briefing,
index keywords, prompt, examples, simple input/output/state schemas,
capabilities, optional `chainTo` allowlist, optional `stateBridges`, and
optional `runtimeActions`.

Stored scan records use `ScanResult` with:

- `schemaVersion`: versioned storage shape for future migrations.
- `toolID`: normalized local tool identity used by `ToolStorage`.
- `richFields`: visible extracted fields.
- `scriptNotes`: non-executable extraction notes. Legacy `script` JSON decodes
  into this field for backward compatibility.
- `state`: persisted per-result state. `ToolStorage.latestState(for:)` feeds the
  latest state back into scanner prompts when the selected tool declares
  `persistent_state`, or when a tool declares a runtime `stateBridge` that
  explicitly falls back to prior state for follow-up behavior.
- `actions`: declarative actions requested by a scan result.
- `confidence`: optional 0.0-1.0 extraction confidence emitted by the model and
  clamped by the runtime.
- `followUp`: optional request to hand off to another tool, accepted only when
  that tool appears in the source definition's `chainTo` allowlist.

## Prompt Runtime

The local tool prompt is split between definition-owned extraction instructions
and runtime-owned protocol instructions. User-created definitions may describe
what to extract, but the app appends the JSON shape, meta-key contract, and
capability limits immediately before vision inference.

`briefing`, `rules`, and `examples` are injected into the scanner prompt. The
examples field is treated as few-shot extraction data, so generated or curated
tools can improve output shape without relying only on rules text.

Runtime-owned meta keys are:

- `_isValid`: extraction success flag.
- `_validationNotes`: short quality note.
- `_confidence`: 0.0-1.0 confidence value.
- `_state`: emitted only for tools with `persistent_state`.
- `_actions`: emitted only for tools with `open_url`.
- `_followUp`: emitted only when `chainTo` is non-empty.

`ToolManager` now executes config-driven `runtimeActions` instead of
tool-specific handlers. A runtime action maps an emitted `_action` value to a
generic HTTP request plus a reusable response mode such as `text_path`,
`html_lead_sections`, or `ranked_html_sections`.

`stateBridges` let a tool persist normalized fields into state and reuse them on
later turns. The bundled Wikipedia tool uses a `topic` -> `last_topic` bridge,
while its retrieval behavior lives entirely in `LOCAL_TOOLS.json`.

## Action Execution

Model output never executes code. The scanner accepts `_actions` as data only
when the active local tool has the matching capability. Unsupported `_state`,
`_actions`, and `_followUp` keys are stripped by `VisionManager` before a
`ScanResult` is stored or rendered.

SwiftUI validates and executes supported actions through app-owned code. The
current supported action is `openURL`; `ScannerView` only opens `http` and
`https` URLs after the user taps the action. Parsed actions are always marked as
requiring user approval.

`ScriptEngine` remains only as a deprecated no-op compatibility shim. New
features must not reintroduce JavaScript execution for model-produced content.

## Storage

`ToolStorage` writes one JSON array per normalized tool ID under
`Documents/tool_storage/`. Save and replace operations stamp each result with the
normalized `toolID`, keeping old records decodable while new records encode the
current schema version.

`ToolRegistry` persists only user-created definitions. Resetting custom tools
removes the user definition file and reloads bundled definitions from the app
bundle.

## Future Plans

### Tool Workflows and Hooks

The local tool protocol should be able to grow into inter-tool workflows without
giving model output execution privileges. The intended shape is:

```text
ToolDefinition
  -> ToolInvocation
  -> ToolResult
  -> StatePatch
  -> Action/Event
  -> ToolOrchestrator decision
```

Future workflow support should add Swift-owned types such as `ToolInvocation`,
`ToolResult`, `ToolEvent`, and `ToolOrchestrator`. A scan result may request a
declarative next step, but the orchestrator must validate and execute only
allowed transitions.

Planned examples:

- Pipeline: receipt scan -> field normalization -> expense classification -> CSV
  export.
- Workflow: parcel label scan -> postcode/state validation -> courier grouping
  -> batch export.
- Hook: after saving a result, update aggregate state, run a validation tool, or
  create an export-ready record.
- Human-in-loop action: ask the user before opening a URL, invoking another
  tool, exporting data, or performing any externally visible action.

`ToolAction` can evolve beyond `openURL` with typed cases such as `invokeTool`
and `exportCSV`. These actions must remain declarative data. Model output may
suggest an action; app-owned Swift code decides whether it is available, valid,
approved, and safe to run.
