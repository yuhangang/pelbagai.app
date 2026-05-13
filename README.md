# Pelbagai

Pelbagai is an iOS SwiftUI app for on-device chat, speech, vision scanning,
local tools, and local persistence.

## Runtime Notes

The app currently targets Gemma 4 text and vision checkpoints through the
SharpAI forks of `mlx-swift-lm` and `mlx-swift`. This is an intentional spike
to unblock native Gemma 4 loading while the upstream Apple MLX Swift stack does
not yet expose a `gemma4` model implementation.

Model downloads use a small app-owned bridge over `Hub` and `Tokenizers`, so
first-run model loading still fetches weights from Hugging Face on demand
without depending on the old `mlx-swift-examples` convenience loader. The app
now forces a normal online fetch attempt for those first-run downloads instead
of relying on `HubApi`'s conservative automatic offline heuristic. The current
package build only honors that by disabling the package's network-monitor gate
via `CI_DISABLE_NETWORK_MONITOR=1` before app-managed model downloads, then
keeps the downloaded weights on-device for later offline reuse.

Chat routing now goes through a Swift-owned agent layer before MLX generation.
The agent injects a compact relevant memory block, exposes only turn-matched
native chat tool schemas, validates model tool calls against that allowlist, and
stages approval-required actions in the chat UI before executing the plugin.
Agent turns also preflight available memory, retry one failed or malformed model
reply with compact context, and keep diagnostic breadcrumbs for local debugging.
Simple time/date and battery requests still execute in Swift instead of running
a second model generation pass after the tool result. The chat toolbar includes
a text-turn retry action that replays the last user message after removing the
failed assistant output. The iOS build also declares Apple's increased-memory-
limit entitlement for supported devices; the app must still handle normal iOS
memory limits because extra memory is not guaranteed on every device.
Image input is downsampled through ImageIO before chat or scanner inference so
camera and photo-library originals are not kept at full decoded size while Gemma
vision preprocessing runs. Image-only Gemma 4 turns also keep the visual soft
token budget conservative and route both `gemma4` and `gemma4_audio` config
aliases through the app runtime wrapper so the audio tower stays disabled unless
audio capability is explicitly enabled.

System integration now goes through Swift-native plugins registered by
`NativePluginRegistry`. Plugins are trusted compile-time code, not dynamic JSON
tools. Chat tools and local tool runtime actions can call plugin capabilities,
while dynamic tool definitions remain declarative adapters that cannot create
new native powers.

The bundled Wikipedia tool now uses config-driven `stateBridges` and
`runtimeActions` in `LOCAL_TOOLS.json` instead of a custom Swift handler. Its
current config returns the full article lead when available and reuses the last
resolved subject for follow-up detail requests.

## Validation

Run the minimum local checks after Swift or package changes:

```sh
xcodebuild -list -project pelbagai.xcodeproj
xcodebuild -resolvePackageDependencies -project pelbagai.xcodeproj
xcodebuild build -project pelbagai.xcodeproj -scheme pelbagai -destination 'generic/platform=iOS Simulator'
```

If sandboxed Xcode cannot write under `~/Library/Developer` or SwiftPM caches,
rerun the validation in an approved environment and do not treat the build as
verified until it completes there.
