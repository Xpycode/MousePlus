#!/usr/bin/env bash
# Headless input-safety test harness. Compiles real sources in place via
# 01_Project/Package.swift; never launches the app. Effects: writes only under
# build/test-input-safety/. See docs/testing/input-safety-harness.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/test-input-safety"

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
  InputTapRegistryTests
  KeyboardTriggerMonitorTests
  KeystrokeCaptureRecorderTests    (headless-safe reducer/recorder tests only)
  KeystrokePayloadCodingTests
  MouseButtonTriggerMonitorTests
  RadialGeometryTests
  RuntimeSafetyCoordinatorTests
  RuntimeTrustMonitorTests
  TriggerRecorderServiceTests
  TriggerServiceTests

Excluded suites (not compiled; source closure not headless-safe or needs app target):
  KeystrokeCaptureEditorTests    references AppDelegate (MousePlusApp.swift, @main) and
                                 ActionDataEditor/MenuEditorModel (SwiftUI, MacUIKitSettings)
  HUDTriggerRoutingTests         needs ConfigurationService, SettingsWorkspaceCoordinator, etc.
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

exec swift "${args[@]}"
