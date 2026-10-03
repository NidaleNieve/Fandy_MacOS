# Compact native UI corrections — 2026-10-03

This replaces the menu and editor layout described in the earlier menu-polish report. Fan control, sensor qualification, authentication, watchdog and restoration commands remain unchanged.

## Menu

Normal profile actions, minute/hour presets, Settings, Profiles and Quit use standard `NSMenuItem` rows. The custom SwiftUI hover style is removed; AppKit controls ordinary highlighting and keyboard selection. Native actions dismiss the menu normally. There is no private tracking override or synthetic reopening.

Custom readout content is 168 points wide, with 140 points for wrapping text. AppKit adds its native state/key-equivalent margins. A menu-layout regression requires the complete menu to remain at most 256 points wide, including a very long profile name. AppKit does not wrap standard titles; exceptionally long actions use a bounded native text view, retaining full titles for accessibility and type selection. Minute/hour submenus use native sizing.

The observed fan bar is 120 by 3 points. Percentage and each physical fan's RPM appear beneath it. This remains actual RPM divided by each fan's maximum, including System and stopped fans. The redundant indefinite-manual summary and fixed 64/80-point readout heights are removed. Timed/process/scheduled conditions retain a wrapping summary.

Other Time/Until and While App Is Running open their editable/searchable popovers directly. The extra Choose action is gone. The clock preference is removed from UI, runtime state and new exports; old exports may contain that retired field and decoding discards it. Time-format preference still applies to Until and scheduling. The menu shortcut is named Toggle Menu and closes an open menu or opens a closed one. The explanatory shortcut paragraph is removed.

## Profiles

A native `NSTableView` handles sidebar selection and double-click activation separately. Selecting a row changes the editor immediately; native `doubleAction` activates that exact row. Invalid rows and changes during collection commits are rejected. Rows and matching bottom buttons retain insets.

`NSSplitViewController` retains its hosting controllers rather than replacing both root view trees on every live/model update. Each retained SwiftUI root observes the shared model independently. The sidebar remains adjustable from 220 to 350 points and cannot collapse. The detail area's minimum accommodates the editor and independent status column.

Visible Fan Curves / Schedule / When Activated tabs replace hidden disclosure arrows. Current profile/control state, temperatures and observed fan-speed readout occupy a fixed right column, outside the editor's scroll view. The Live indicator is removed; Undo remains in the toolbar, with Redo in its context menu.

Undo includes profile definitions, creation/deletion/order, schedules/pauses and per-profile activation defaults. Settings changes never register profile undo operations. Undo/redo preserves current global preferences; bindings to a profile that is removed must still be dropped to avoid dangling references. No saved manual lease is recreated.

A secondary click directly deletes a nearby node or adds one at the clicked graph position. No Add/Delete context-menu step remains. Validation, monotonic interpolation and the two-node minimum still apply; disabled graphs reject editing.

## Settings and responsiveness

Sensor search uses `NSSearchField`, with left-aligned text and the standard search affordance. Logical sensors/aggregates precede a visible Raw temperature sensors separator; raw SMC/HID choices remain in the same list. Physical-core identities remain estimates where unqualified.

Rendering application-condition availability reads a cached set. Eligible running applications refresh at most once per second while needed; explicit activation forces a fresh identity check. A regression performs 1,000 availability queries without enumerating processes again. The activation path still validates the exact process instance before installing its exit condition.

## Verification

- 302 Swift tests: 28 hardware, 181 core, 93 app; limited concurrency.
- 33 tool tests.
- Full Address Sanitizer: all 302 tests pass, leak detection disabled for platform-owned runtime state.
- Signed single-job native build succeeds; app/helper signatures and signing-team continuity verified.
- Installed through verified automatic restoration, helper unregister, launchd-service absence, signed bundle replacement and normal ServiceManagement registration. The immediate register attempt encountered asynchronous removal settlement; the normal retry succeeded without changing signing or bypassing approval.

Installed startup verification passed five ticks in System with fresh live monitoring, helper controlReady, Apple ownership, both modes 0/0 and no monitoring warning. Helper/login registrations remain enabled. The ordinary app is running in System; an independent read-only SMC tool also observed modes 0/0.

No screenshots, automated GUI navigation, visual comparison, synthetic stress or custom fan activation were used for this UI delivery. Native appearance, pointer feel, sidebar dragging and actual shortcut input still require human review. The automated results cover command/state/model/layout behavior rather than claiming visual approval. Existing active physical sleep/wake, subjective comfort and gaming/acoustic calibration follow-ups remain.
