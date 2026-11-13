# Input-safety headless test harness

Effects class: headless; no app launch; writes only under `build/test-input-safety/` (gitignored).

## What it compiles

`01_Project/Package.swift` defines module `MousePlus` (so `@testable import MousePlus` works) and
test target `MousePlusTests`. Both use explicit `sources:` lists that point at the real files in
`01_Project/MousePlus/` and `01_Project/MousePlusTests/` in place: no copies, no stubs. Swift
language mode v5 (matches `SWIFT_VERSION = 5.0` in the Xcode project), macOS 14. No package
dependencies: the chosen sources import none of the zPackages products (`ShortcutKit`,
`MacUIKitSettings`). `MousePlusApp.swift` (`@main` + AppDelegate) is never included.

## Commands

```bash
scripts/test-input-safety.sh --all                                   # every included suite
scripts/test-input-safety.sh --suite MouseButtonTriggerMonitorTests  # repeatable
scripts/test-input-safety.sh --list                                  # included/excluded + reasons
```

The script runs `swift test --package-path 01_Project` with scratch, cache, config and security
paths under `build/test-input-safety/`, so `01_Project/.build` and `.swiftpm` are never created.

## Included suites (93 tests, all pass)

ActionTypeCodingTests (4), HUDColorResolverTests (7), HUDCustomizationCodingTests (8),
HUDMotionPolicyTests (4), InputTapRegistryTests (6), KeyboardTriggerMonitorTests (5),
KeystrokeCaptureRecorderTests (14, headless-safe subset), KeystrokePayloadCodingTests (7),
MouseButtonTriggerMonitorTests (7), RadialGeometryTests (10), RuntimeTrustMonitorTests (12,
injected fakes only), TriggerRecorderServiceTests (3), TriggerServiceTests (6). No per-test
exclusions remain: `TriggerRecorderService` takes an injectable `TriggerRecorderEventMonitoring`,
so its tests never install live `NSEvent` monitors; system taps take an injectable
`InputTapFactory`, so tests never create a live `CGEventTap`.

## Excluded

- `KeystrokeCaptureEditorTests` (split from `KeystrokeCaptureRecorderTests`): references
  `AppDelegate` (`MousePlusApp.swift`) and `ActionDataEditor`/`MenuEditorModel` (SwiftUI,
  `MacUIKitSettings`); stays app-hosted/Xcode-only.
- `HUDTriggerRoutingTests`: needs `ConfigurationService`, the settings workspace and more of the
  app closure.
- All other suites: not audited for a headless closure.

Safety audit of included suites: no test creates a live event tap (the monitor tests use a fake
tap and build `CGEvent`s without posting), prompts for Accessibility, or touches UserDefaults,
Application Support, pasteboard or processes.

## Adding a suite

1. Read the test file and its source closure; confirm no live taps, no `NSEvent` monitors, no
   CGEvent posting, no Accessibility prompt, no writes outside a test namespace.
2. Add the test file to the test target `sources:` and any needed real source files to the module
   `sources:` in `01_Project/Package.swift`.
3. Run `swift build --build-tests` via the script (`--all`); fix missing closure by adding real
   files, never stubs.
4. Add the suite name to `list()` in `scripts/test-input-safety.sh`; add per-test exclusions to
   `SKIPPED_TESTS` there.
