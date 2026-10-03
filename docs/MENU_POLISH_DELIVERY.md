# Menu and profile improvements — 2026-10-03

Historical verification record. Menu layout, sidebar implementation and undo scope are superseded by [compact native UI corrections](NATIVE_UI_DELIVERY.md).

## Recovery and truthful presentation

Two paths retained a resolved automatic-restoration warning: the GUI's hardware error and the controller's unverified fault. Successful verified handback clears both. Other failure context remains available. Startup explicitly requests the already-qualified restoration operation before normal monitoring; a transient failure retries through the existing restoration state machine without requiring a profile switch. This does not manufacture verification from RPM or hide a genuinely failed release.

The menu checkmark now means **selected profile**, immediately, including initialization. The status separately says Starting/Restoring until acknowledgement. Engine activation, eligibility, sensor validation and the helper's lease admission gates are unchanged. Duration and process conditions can be attached during initialization; an expired condition still prevents dispatch and restores System.

## Native menu and window behavior

Menu content is bounded to 330 points. Profile names, explanations, diagnostics, and action text wrap instead of stretching the menu. Native menu chrome adds its standard margins. Custom action rows keep the menu open for mouse-selected profiles and quick duration presets. Keyboard selection retains native menu behavior. Opening a window, an editable picker or quitting ends tracking normally.

A small observed-speed bar is shown in System and custom modes. The value is the highest physical fan's **actual RPM / that fan's maximum RPM**, clamped to 0–100; both RPM values appear below it. Stopped fans show 0%. This differs from the custom curve's normalized request, where 0% maps to minimum RPM. Stale/unavailable observations do not produce a reassuring speed reading.

Editable For/Until and searchable application controls use a native popover anchored to the status icon. [Apple documents that custom NSMenu views do not support keyboard input](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MenuList/Articles/ViewsInMenuItems.html). This avoids relying on unsupported embedded text entry. Until has a selectable analog dial, with hour/minute editing indicated by the accent color; default 24-hour display uses a 24-hour dial. The For/Until selection and focused fields are visibly highlighted. Native aesthetics and input/focus behavior still require human review; no screenshot or GUI automation was used.

Settings and Profiles activate before ordering their window front, move to the current Space, deminiaturize when needed and repeat key ordering after menu tracking ends. The sidebar is an NSSplitViewController with both items explicitly non-collapsible; the sidebar's minimum width is 220 points and it remains adjustable up to 350 points. There is no sidebar toggle. Rows have an inset, bottom buttons share their style/icon sizing, and Live is a fixed-size text indicator. Double-clicking a profile activates it.

The cancellation label says **Cancel <profile>** when no configured schedule falls within the timed activation; it adds Resume Schedule only when a real unpaused range is relevant. Falling back to System alone is not a schedule. Indefinite/process conditions have no known end, so their label checks the coming week. Cancellation still hands back to System before any schedule resumes. Cancelling an already scheduled profile pauses its current occurrence; it cannot restart itself on the next tick. Resume Schedule explicitly clears that pause.

## Shortcuts and activation defaults

Settings offers an initially unset global shortcut for opening the menu and one for each profile. Record accepts Command/Option/Control combinations, Escape cancels, and Clear removes a binding. A profile shortcut activates that profile; pressing it again selects System. Carbon RegisterEventHotKey registers explicit combinations, with no global keyboard monitor, event tap, Accessibility or Input Monitoring permission. Registration conflicts are displayed; choose combinations not used for other application commands. Registrations are suspended while recording so the recorded key neither triggers fan control nor gets consumed by an existing Fandy hotkey. The recorder handles input only in Fandy's own focused control and logs no key events.

Every profile, including System/Max, has **When activated**: until changed, a duration, or while a chosen application's exact process instance is running. Application selection includes running applications and a native application-file picker. If the configured app is not running, manual activation is unavailable rather than becoming indefinite. PID plus kernel start time prevents a reused PID from extending control. Manual menu/shortcut activations apply the default; schedules retain their explicit intervals. Menu conditions can replace it immediately.

Activation defaults travel with individual profile files and full settings. Shortcuts travel in full settings. Old configuration/profile files default to unset shortcuts and no activation override. Duplicate profiles inherit activation defaults, but not a duplicate global shortcut or overlapping schedule. These are portable intent, never runtime leases or model qualification.

## Editing and Gaming

Universal Undo/Redo covers curve/name/floor changes, creation/deletion/reordering, schedules/pauses, imports and activation preferences; history survives sidebar selection. Undo restores validated configuration and schedules a save, with an unsaved warning if persistence fails. It never resurrects a saved manual lease. Direct manipulation stays grouped. Collection commits cannot overwrite a newer manual selection when a profile is deleted.

Right-clicking near a curve node offers Delete Point; elsewhere within the plot it offers Add Point at that position. Insertion clamps percentage between neighbors to maintain monotonic cooling. At least two nodes remain; invalid/duplicate/nonfinite points are rejected. Disabled graphs do not accept contextual edits.

Gaming's revision-two chip curve is 35°C→15%, 45→25%, 55→40%, 65→55%, 72→70%, 77→85%, 81→95%, 85→100%. It is stronger than the regular chip curve throughout its range. Existing revision-one definitions migrate only when their previous curve/floor/idle settings are untouched. Edited curves remain unchanged; Reset to Default adopts the new curve. Temperatures use the qualified operational chip input, not falsely certified CPU/GPU averages. Sustained gaming/acoustic calibration remains a separate follow-up.

## Verification

Final software results: **296 Swift tests** (28 hardware, 181 core, 87 app), **33 tool tests**, full **Address Sanitizer 296** with leak detection disabled, and **six focused Thread Sanitizer checks** pass. Signed single-job build and deep/strict signature verification pass. Cases cover stale-error recovery without profile switching, initialization timing, exact process-instance defaults/exit, absent applications, universal configuration undo/redo, duplicate/imported defaults, shortcut conflicts/bounds, schedule lookahead/pauses, scheduled cancellation, sidebar/menu constraints, observed RPM normalization, contextual nodes and untouched Gaming migration. Automated verification is software, command construction, model/view state, sanitizer checks and structured hardware observations. No screenshots, GUI navigation, synthetic stress, power changes or initial Max experiment.

Signed replacement used explicit both-fan release, unregister/service absence, verified bundle replacement and normal registration. A final GUI-only update preserved the byte-identical registered helper. Genuine startup verification passed five ticks, System, helper controlReady, modes 0/0 and monitoringIssuePresent=false, without selecting another profile. The ordinary app is running System; helper and login registrations report enabled. A subsequent independent read-only SMC observation found both fans in mode 0. Raw measurements and signing configuration stay local and are excluded from publishing.

Remaining human checks: appearance/interaction in the new native menu/popovers, actual shortcut key routing on the user's keyboard, Space/window-front behavior, sustained gaming acoustics/thermals and coordinated physical active sleep/wake. Model and signature checks are not a claim of visual testing or actual key/sleep observations.
