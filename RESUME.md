# Wave 4 Signed Verification Checkpoint

The exact post-review signed Debug app is launched from:

`/tmp/mouseplus-wave4-final.I9bFyc/Build/Products/Debug/MousePlus.app`

Automated evidence is complete: two adversarial passes, 70 focused tests, and 207/207 tests from fresh derived data passed. Developer signing team: `FDMSRXXN73`.

## User checklist

- [ ] Reorder the first item Earlier and last item Later; both wrap and keep the same item selected.
- [ ] With outside dismissal enabled, click another app and a transparent panel corner; both dismiss. Disable it and confirm an outside click preserves the HUD.
- [ ] Compare an unhovered custom wedge/icon in preview and live HUD in light and dark appearance; selection remains a neutral marker.
- [ ] Exercise Always, Reveal, and Hidden. Hidden has no outer backing and cannot expand; Reveal appears only after inner-to-outer travel and resets next invocation.
- [ ] Tap-toggle: center click opens Menu Items Settings; center drag beyond 4 pt moves without executing; wedges still hit correctly after moving; test a display edge/second display if available.
- [ ] Hold-release remains pointer-anchored and executes normally; preview clicks never execute; direct mouse triggering produces no beep.
- [ ] Change a setting and immediately choose Quit MousePlus in General; confirm termination. Relaunch the same app, confirm the change persisted and triggers re-armed.
- [ ] Report whether the menu-bar status icon is visible and its Quit MousePlus command works.

Pre-check configuration SHA-256:

`a40e0a45163d6835bf7f594780ac7efd4f0e45ba5f4d5789fb55d8e66100c9fc`

Record pass/fail details before marking tasks 4.2–4.3 or the specification Complete.
