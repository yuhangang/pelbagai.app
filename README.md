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
without depending on the old `mlx-swift-examples` convenience loader.

Built-in chat tools for time/date and battery execute in Swift instead of
running a second model generation pass after the tool result. The iOS build also
declares Apple's increased-memory-limit entitlement for supported devices; the
app must still handle normal iOS memory limits because extra memory is not
guaranteed on every device.

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
