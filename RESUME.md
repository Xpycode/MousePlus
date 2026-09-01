# Wave 7 Resume Checkpoint

Wave 7.1 and 7.2 are complete and committed:

- `69a14bc` — final automated/static gates and concurrency-warning fixes
- `05e5d0e` — adversarial safety fixes and regressions

The signed Debug app at `/tmp/MousePlus-Wave7-Live/Build/Products/Debug/MousePlus.app`
was built with the installed Developer ID identity and launched on 2026-09-01.

Remaining task: Wave 7.3 user-driven T12 smoke. Confirm:

1. Open the four-pane Settings workspace; resize it and confirm no second editor window exists.
2. Edit a Menu Item, wait for Saved, switch/reopen, and confirm the edit and selection persist.
3. Record a harmless keystroke, Cancel once, then Save and Test Action against a disposable target.
4. Invoke the live ring and confirm the edited action runs; successful actions stay silent.
5. Spot-check F1 reopen-mid-edit, F7 direct Snap after removing sub-items, F8 12-subitem cap, and F15 invalid-symbol placeholder.
6. With Full Keyboard Access/VoiceOver, reach panes, editor fields, Test, Reset/Undo/Restore, and close choices; state is announced in text.
7. Make a dirty edit and exercise close Cancel; if practical, also confirm Retry/Discard on a temporary failure harness only.

After user confirmation: mark 7.3 and Wave 7 complete, update project/task state, delete this checkpoint and `docs/IMPLEMENTATION_PLAN.md`, then commit. Do not merge or push without the explicit repository-history procedure.
