# OpenLogi Reference: What MousePlus Can Use

**Written:** 2026-11-21
**Source:** https://github.com/AprilNEA/OpenLogi at commit `9ca7ef0` (2026-11-12)
**Licence:** MIT OR Apache-2.0. MousePlus is GPLv3, so porting is allowed; keep attribution if
actual code is ported rather than the protocol re-implemented.
**Language:** Rust (GPUI interface). Nothing drops into our Swift code; this is a protocol and
design reference.

OpenLogi is an open-source replacement for Logi Options+. It has an "Actions Ring" and, more
usefully for us, a complete HID++ implementation with recorded device fixtures for the MX Master 3S
and MX Master 4.

**Status of the facts below.** Marked *checked* where I read the source line or fixture myself,
*reported* where it comes from a research pass over the code that I did not re-read. Nothing here
has been tested on our hardware.

---

## 1. Summary

| Area | Use for MousePlus | Priority |
|------|-------------------|----------|
| HID++ button diversion | Answers the open "advanced Logitech HID++ support" question in `PROJECT_STATE.md`. Gives button IDs, call sequence and pitfalls for a Swift port. | High |
| Device fixtures | Recorded HID++ exchanges for the MX Master 3S and MX Master 4. Usable as test data for a Swift parser, and they reduce what we must capture ourselves. | High |
| Haptic feedback | Buzz the MX Master 4 on wedge hover and on activation. Needs the HID++ backend first. | Later |
| Click-through fix | Possible gap in our transparent panel; needs a check. | Low, quick |
| Hold-versus-click rule | Design idea for merging our two trigger modes. | Idea only |
| Ring layout, editor, per-app layouts | Nothing. Ours already does more. | None |

---

## 2. HID++ trigger backend

### Why it matters

Decision "Mouse-Button Trigger Backend: IOHIDManager" (2026-04-29) left one blind spot: Logitech-only
buttons that never appear on standard HID pages. OpenLogi shows these are reached by *diverting*
the button over HID++, after which the mouse reports presses to the host software instead of
acting on them itself. This is the route for the MX Master 3S gesture button and the MX Master 4
haptic panel.

### Transport

- macOS transport is `IOHIDManager` (through the `async-hid` crate) — the same API we already use.
  One manager for the whole process. *(reported)*
- Match the vendor collection that carries the long report *(checked,
  `crates/openlogi-hid/src/transport.rs:265`)*:
  - usage page `0xff00`, usage `0x0002` — USB, Bolt and Unifying receivers, Bluetooth classic.
  - usage page `0xff43`, usage `0x0202` — Bluetooth LE direct. Accepts **long reports only**, so
    short requests must be sent in long form.
- Report formats *(checked, `crates/openlogi-hidpp/src/channel/message.rs:5`)*:
  - short: report ID `0x10`, 7 bytes
  - long: report ID `0x11`, 20 bytes
  - layout: `[reportID, deviceIndex, featureIndex, (function << 4) | softwareID, params…]`
- Device index: `0xff` for Bluetooth direct; the pairing slot (1–6) through a receiver. The 3S
  fixture uses `0xff`, the MX Master 4 fixture uses `0x02`. *(checked in fixtures)*
- Software ID: pick a non-zero value (OpenLogi leases one of `0x2…0xf`). Every open handle receives
  every input report, so replies must be matched on device, feature, function **and** software ID.
  *(reported)*
- Error replies arrive with feature index `0xff`. *(reported)*

### Control IDs

| Mouse | Control | ID | Evidence |
|-------|---------|----|----------|
| MX Master 3S | Gesture (thumb) button | `0x00C3` | *checked:* `crates/openlogi-device/src/reprog_controls.rs:48`; 3S fixture row `00c3 00a9 31…` |
| MX Master 4 | Gesture button | `0x00C3` | *checked:* MX Master 4 fixture row `00c3 009c 31…` |
| MX Master 4 | Haptic panel ("Actions Ring" button) | `0x01A0` | *checked:* `crates/openlogi-hidpp/src/feature/reprog_controls/control_ids.rs:525`; fixture row `01a0 0109 31…`. Not in Logitech's published list. |

Fixtures: `fixtures/devices/mx-master-3s-001/cases/reprogrammable-controls.json` and the same path
under `mx-master-4-001`.

### Call sequence (feature `0x1b04`, Reprogrammable Controls v4)

1. **Find the feature index.** Root feature (index 0), function 0, params `[0x1b, 0x04, 0]`. Reply
   byte 0 is the index. It differs per device: `0x09` on the 3S fixture, `0x0d` on the MX Master 4
   fixture. *(checked in fixtures)*
2. **Enumerate controls.** Function 0 returns the count. Function 1 with a row number returns:
   bytes 0–1 control ID, 2–3 task ID, 4 flags, 5 position, 6 group, 7 group mask, 8 extra flags.
   Divertable is flag bit 5; raw-XY capable is bit 0 of the extra flags. *(reported)*
3. **Save the current state.** Function 2 with `[cidHigh, cidLow, 0]`. Keep the reply for restore.
   *(reported)*
4. **Divert.** Function 3, long report, payload `[cidHigh, cidLow, flags, remapHigh, remapLow,
   flags2]`. Each setting is a bit pair: the high bit means "change this", the low bit is the value
   *(checked, `crates/openlogi-hidpp/src/feature/reprog_controls.rs:340`)*:
   - divert on: `0x03`
   - divert on plus raw XY on: `0x33`
   - divert on, raw XY explicitly off: `0x23`
   - undivert: `0x02` (plus `0x20` to clear raw XY)
   - remap `0x0000` leaves the remap unchanged
5. **Read presses.** Notifications arrive on the same feature index with software ID 0
   *(checked, `crates/openlogi-hidpp/src/feature/reprog_controls/event.rs:96`)*:
   - function 0: up to four currently pressed control IDs, big-endian, in bytes 0–7. There is no
     separate "released" message; press and release are the difference between successive frames.
   - function 1: raw XY movement, `dx` and `dy` as signed 16-bit big-endian. Only needed for
     gesture-style input, which we do not need for a trigger.

### Keeping the diversion alive

- Diversion is volatile. It is lost on sleep, reconnect and host switch.
- Watch the reconnect broadcast of feature `0x1d4b` (Wireless Device Status), wait 200 ms, then
  send the divert again. *(checked: constant at `crates/openlogi-device/src/session/capture.rs:48`)*
- Undivert on quit using the saved state, or the button stays dead until the mouse reconnects.
  *(reported)*
- OpenLogi stops all HID traffic during sleep and DarkWake. *(reported)*

### Coexistence — the open risk

- The OpenLogi README tells users to quit Logi Options+: "Only one application can own a receiver
  at a time." *(checked, `README.md:176`)*
- Another tool's divert change is visible to us, because the device's reply reaches every handle
  and carries the other tool's software ID. OpenLogi re-diverts when that happens, capped at three
  times per control per minute so two tools cannot loop.
  *(checked: cap at `crates/openlogi-device/src/session/capture/redivert.rs:24`)*
- A failed device open with permission already granted means another app seized the device
  exclusively (they name Options+ and Karabiner-Elements). *(reported)*
- **Nothing is said about BetterMouse**, which is our currently supported route. Whether a divert
  from MousePlus survives next to BetterMouse must be tested live before committing to this.

### Permission

Input Monitoring only, which MousePlus already requires. A denied device open fails silently, so
access must be checked explicitly to explain the failure. Accessibility is not needed for this
path. *(reported)*

### Estimated size of a minimal Swift port

Scope: "divert one button, deliver down/up to the existing `TriggerMonitor` protocol".

- six to eight request types, one input-report callback, re-divert on reconnect, undivert on quit
- a rough guess of a few hundred lines, sitting beside `Services/HID/` — an estimate, not a
  measurement
- the fixtures can drive unit tests for the parser without hardware

---

## 3. Haptic feedback (MX Master 4 only)

- Feature `0x19b0`, reverse-engineered by OpenLogi.
  *(checked, `crates/openlogi-hidpp/src/feature/haptic_feedback.rs`)*
- Play: function 4, payload `[waveform, 0, 0]`. Waveform `4` (subtle collision) on hover, `1`
  (damp state change) on activation. *(checked for the call and the values; their use on
  hover/activation is reported)*
- Function 0 returns the supported waveforms as a bitmask; function 3 returns status, 0 = ready.
  *(reported)*
- They ignore repeated hover reports for the same slot so a still pointer cannot flood the queue,
  and they hand the haptic setting back after the ring closes. *(checked: doc comments in
  `crates/openlogi-agent-core/src/action_ring.rs` and `CHANGELOG.md`)*

For MousePlus this would be an optional per-HUD setting, and it must stay presentation-only, in
line with the HUD motion rule in `PROJECT_STATE.md`.

---

## 4. Ring behaviour ideas

### Click-through on transparent pixels

macOS hands a click on a nearly transparent pixel to the window underneath. OpenLogi measured that
1/255 alpha lets the click through and 0.01 alpha holds it, so they fill the ring's footprint with
mid grey at 1% alpha. *(checked, `crates/openlogi-overlay/src/ring.rs:95`)*

Our panel is `isOpaque = false` with a clear background (`Controllers/RingWindowController.swift:287`),
and selection is cursor-driven through `RadialGeometry.hitTest` rather than per-wedge hit testing.
So a click in a gap between wedges may or may not reach our panel. **Not verified — needs a live
check** in tap-to-open mode: click a gap and the dead zone over another app's window.

### Hold-versus-click on one trigger

OpenLogi uses one trigger for both styles: released within 250 ms it counts as a click and the
ring stays open for a pointer click; held longer, release chooses the highlighted slot, or cancels
if the pointer is back in the centre. Only the first release counts.
*(checked, `crates/openlogi-agent-core/src/action_ring.rs:43`)*

MousePlus stores the mode per binding (`TriggerMode` in `Models/Configuration.swift:336`), so the
user picks one. An automatic rule would remove that choice. This is a product decision, not a fix.

### Not worth taking

- Eight fixed slots, one level, direction-only aiming — ours has concentric rings and submenus.
- Per-app layouts — we have app-specific HUDs.
- Their window and multi-display handling is mostly about Wayland and Windows.

---

## 5. Suggested next steps

1. **Coexistence test first.** With BetterMouse running, send one divert for `0x00C3` on the 3S and
   see whether presses arrive and whether BetterMouse undoes it. This decides between "implement",
   "accept limitation" and "require quitting other tools".
2. If it holds, write a spec for a minimal HID++ trigger: the two control IDs above, down/up only,
   re-divert on reconnect, undivert on quit.
3. Check the click-through question on a live build; it is independent of everything else.
4. Haptics only after step 2 ships.
