#!/usr/bin/env bash
# Headless input-safety test harness. Compiles real sources in place via
# 01_Project/Package.swift; never launches the app. Effects: writes only under
# build/test-input-safety/. See docs/testing/input-safety-harness.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/test-input-safety"

# Test methods excluded by --skip. Each installs live NSEvent local/global
# monitors via TriggerRecorderService (no seam yet; re-admitted by task R2/R3).
SKIPPED_TESTS=(
  "MouseButtonTriggerMonitorTests/testMouseRecorderFlagClearsOnCancel"
  "MouseButtonTriggerMonitorTests/testExistingBindingPassesToRecorderWithoutOpeningHUD"
)

usage() {
  echo "usage: $(basename "$0") --all | --suite <Name> [--suite <Name> ...] | --list" >&2
  exit 2
}

list() {
  cat <<'LIST'
Included suites (compiled from real sources in place):
  ActionTypeCodingTests
  HUDColorResolverTests
  HUDCustomizationCodingTests
  HUDMotionPolicyTests
  KeystrokePayloadCodingTests
  MouseButtonTriggerMonitorTests   (minus the two skipped tests below)
  RadialGeometryTests
  RuntimeTrustMonitorTests

Excluded tests (skipped via --skip, still compiled):
  MouseButtonTriggerMonitorTests/testMouseRecorderFlagClearsOnCancel
      TriggerRecorderService.record installs live NSEvent local+global monitors (unseamed).
  MouseButtonTriggerMonitorTests/testExistingBindingPassesToRecorderWithoutOpeningHUD
      Same: TriggerRecorderService.record installs live NSEvent monitors (unseamed).

Excluded suites (not compiled; source closure not headless-safe or needs app target):
  KeystrokeCaptureRecorderTests  references AppDelegate (MousePlusApp.swift, @main) and
                                 ActionDataEditor/MenuEditorModel (SwiftUI, MacUIKitSettings)
  HUDTriggerRoutingTests         needs TriggerService, ConfigurationService, keyboard monitor, etc.
  All other suites in 01_Project/MousePlusTests (not yet audited for headless closure)
LIST
}

[[ $# -gt 0 ]] || usage
mode=""; suites=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) mode=all; shift ;;
    --list) list; exit 0 ;;
    --suite) [[ $# -ge 2 ]] || usage; mode=suite; suites+=("$2"); shift 2 ;;
    *) usage ;;
  esac
done

mkdir -p "$OUT/cache" "$OUT/config" "$OUT/security" "$OUT/clang-modules"
export CLANG_MODULE_CACHE_PATH="$OUT/clang-modules"

args=(test
  --package-path "$ROOT/01_Project"
  --scratch-path "$OUT/.build"
  --cache-path "$OUT/cache"
  --config-path "$OUT/config"
  --security-path "$OUT/security")

if [[ "$mode" == suite ]]; then
  for s in "${suites[@]}"; do args+=(--filter "^MousePlusTests\\.${s}/"); done
fi
for t in "${SKIPPED_TESTS[@]}"; do args+=(--skip "^MousePlusTests\\.${t}\$"); done

exec swift "${args[@]}"
