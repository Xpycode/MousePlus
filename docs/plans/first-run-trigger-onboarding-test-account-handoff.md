# MousePlus onboarding — test-account handoff

This is a GUI-only test. Codex and Terminal are not needed in the test account.
The staged app is `/private/tmp/MousePlus-onboarding-20261107/MousePlus.app`, version 0.1.0 (1),
signed for team `FDMSRXXN73`. It passed strict signature verification on the M4 Pro Mac.
This build passed the daily-account persistence, color-well, and title-placement checks.
It has not been launched in a fresh test account for this acceptance pass. The app in `/Applications` is the daily-use
installation; leave that installation and the daily account's settings alone.

**Scope:** First-run permission and trigger setup, direct physical input, both trigger modes,
cross-app opening and Escape dismissal, persistence, and keyboard navigation. VoiceOver was
deferred by the user on 2026-09-27 and is not part of this pass. A test account is used to
protect the daily account's configuration and permission state.

## Before switching accounts

1. Make sure this file and `MousePlus.app` are present in
   `/private/tmp/MousePlus-onboarding-20261107/`. Temporary files may disappear after a reboot;
   if either is missing, stop and return to the daily account.
2. Sign out of the daily account, then sign in to a new macOS test account. Signing out avoids
   having two MousePlus processes compete for global input. The Codex session need not be
   available in the test account.
3. In the test account, open Finder and choose **Go → Go to Folder…** (Shift-Command-G).
   Enter `/private/tmp/MousePlus-onboarding-20261107/`. Open `READ-ME-FIRST.txt` with TextEdit.
   Do not move the app into Applications.
4. Note the Mac model, macOS version, mouse model, any button-mapping software, and whether
   MousePlus is absent or disabled in **System Settings → Privacy & Security → Accessibility**.
   A truly fresh permission check requires no existing grant in this test account.

## Run the checks, in this order

Mark each result **PASS**, **FAIL**, or **NOT RUN**, with a short observation. A screenshot of a
failure helps, but the exact text and action sequence matter most. Keep the pointer in the
center of the ring during Escape checks so no action is selected.

1. **Fresh launch, no Accessibility grant.** Double-click the staged `MousePlus.app` in Finder.
   Expect one "Welcome to MousePlus" permission window, no ring trigger silently assigned,
   and an **Open System Settings** button. If macOS blocks the app from opening, record the
   exact message and stop; do not bypass a security warning for this test.
2. **Grant and continue.** Use the window's button, enable MousePlus in
   **Privacy & Security → Accessibility**, return to MousePlus, and choose **Choose a Trigger** (the continuation button for a fresh configuration).
   Expect Settings to open on **Triggers** with "Choose how to open MousePlus" guidance.
   Record any repeated dialog or window loop.
3. **Close without a trigger; relaunch.** Do not edit any settings yet. Close Settings,
   then quit MousePlus from its menu-bar icon. Reopen the staged app from
   `/private/tmp/MousePlus-onboarding-20261107/`. Expect Triggers setup to return once,
   with no immediate reopen loop after you close it. Permission is now granted and
   the untouched fresh account still has no configured ring trigger. If you already
   changed settings, stop this row and report it rather than deleting configuration.
4. **Keyboard recording and cancel.** In Triggers, click **Record** for Keyboard Trigger and
   press Escape. Expect cancellation with no new binding. Record a keyboard shortcut that does
   not conflict with macOS or another app. Wait for **Saved**. Expect the displayed binding and
   trial instructions to match the saved shortcut and selected mode. Cancel another recording
   and confirm the saved binding remains.
5. **Recorder timeout.** Start Mouse Button Trigger recording and press nothing for about four
   seconds. Expect timeout/recovery guidance, with the previous binding still intact.
6. **Direct physical mouse recording.** Record a physical middle or extra mouse button
   (button 2 or higher), with no BetterMouse/Logi Options+ keyboard remapping for that button.
   Expect a saved mouse binding. If software intercepts the button, record the warning and
   report direct mouse input as **NOT VERIFIED**; a remapped keyboard shortcut is not a pass.
7. **Hold-release over another app.** Set a saved ring trigger to **Hold-release**, wait for
   Saved, activate Finder or another app, then hold the trigger. Expect the ring to open.
   Press Escape before releasing. Expect dismissal without executing an action.
8. **Tap-toggle over another app.** Set a saved ring trigger to **Tap-toggle**, wait for Saved,
   activate another app, and tap the trigger. Expect the ring to stay open. Press Escape.
   Expect dismissal without executing an action. Try the direct mouse binding too if it was
   captured; record its result separately from the keyboard shortcut.
9. **Persistence and configured launch.** Quit from the menu-bar icon and reopen the same staged
   app. Expect no automatic trigger-setup window. The binding and mode should still be shown
   in Triggers and work over another app.
10. **Permission restore.** With a saved binding, quit MousePlus. Turn its Accessibility toggle
    off in System Settings, then reopen the staged app. Expect permission guidance without
    losing the binding. Re-enable permission, continue, and verify the binding still works;
    no re-recording should be required.
11. **Settings access.** In Triggers, record a non-conflicting Open Settings Shortcut and wait
    for Saved. Expect guidance to name that shortcut. Clear it and wait for Saved. Expect
    guidance to direct you to the menu-bar icon; Settings should still open from that icon.
12. **Keyboard navigation.** With the relevant window open, use Tab/Shift-Tab and Return or
    Space to move through and activate its controls. Check that focus is visible and in a
    usable order, and that Escape cancels recording or dismisses the ring as described.
    VoiceOver is **not** part of this check.

If one step fails, record it and continue with independent steps only when the state is clear.
Do not reset macOS permissions with Terminal, grant keystroke-posting permission for this test,
or change files in the daily account.

## Save the results for Codex

Open TextEdit in the test account, create a plain-text note, and save it as
`/Users/Shared/MousePlus-onboarding-results.txt`. Include the fields below. Screenshots can be
saved to `/Users/Shared/` too. This shared folder is readable from the daily account; your
test account's Desktop usually is not.

    Date/time:
    Mac / macOS:
    Mouse and button-mapping software:
    Starting Accessibility state:
    Candidate path used:
    Steps 1–12: PASS / FAIL / NOT RUN, with actual result and any exact error text:
    Direct physical mouse button tested (or why unavailable):
    Screenshot filenames in /Users/Shared:
    Anything changed in the test account (binding, mode, permission):

Finally, quit MousePlus in the test account and sign out. Sign back into the daily account,
resume Codex, and provide the results file path. Codex will compare the evidence against the
acceptance checklist and keep any unverified row open.
