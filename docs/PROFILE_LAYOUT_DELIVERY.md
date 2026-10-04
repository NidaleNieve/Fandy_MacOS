# Profile layout and native time controls — 2026-10-04

Profiles now has four separated tabs: Fan Curves, Schedule, Pause Schedule and When Activated. Pause date ranges moved to their own editor without changing schedule priority, persistence, imports or undo. The schedule's manual-priority note is a bottom information tip; the redundant 24-hour explanatory sentence is removed.

Chip and Chassis use native collapsible disclosure groups. Used sections expand when selecting a profile; unused sections start collapsed. Selecting a target input reveals its relevant section and chassis graph. The optional temperature target is below minimum airflow/idle controls. The airflow reset restores only that setting to the bundled default, or zero for a custom profile.

Graphs retain editable nodes and add a dashed request envelope: maximum of the enabled curve, minimum airflow and a matching temperature target. A labelled target marker makes its temperature visible. Separate input temperature scales remain intact. The target response uses the actual production proportional formula; the graph does not invent a new fan-control policy or overwrite nodes. Its legend explicitly notes that other sensors and the immutable chip guard can request more. Disabled curves stay uneditable while their floor/target contribution can still be displayed. Target temperatures outside the previous graph range expand the view safely.

Point add/remove buttons have identical icon frames and native styles. The transient Changes not saved line is removed; validation and real persistence failures still appear. Sidebar heading, rows and action bar share the same system background with separators. Right-click menus add Duplicate, Export and Remove, acting on the clicked identity. Built-ins remain protected against removal, and deleting an unselected custom profile preserves editor selection. Export includes the selected profile's scheduling metadata through the existing interchange format.

Other Time/Until retains its inline hover submenu. For/Until now uses the same native segmented picker style as the profile tabs. A fixed content area and reserved error row keep the selector/Continue button in place across both modes. The duration fields share a centered grid. AppKit's `NSDatePicker` clock-and-calendar style with hour/minute elements replaces the custom dial; its clock uses the traditional light appearance while exact fields retain the 24/12-hour preference. See Apple's [date picker element documentation](https://developer.apple.com/documentation/appkit/nsdatepicker/datepickerelements).

## Verification

- 318 Swift tests pass: 28 hardware, 190 core, 100 app, with one job and no parallel tests.
- Four added regressions cover graph/control-engine parity, separate input scales and corrupt-number rejection, clicked-identity context actions/protected built-ins, and native clock midnight/24-hour bindings.
- 37 tool tests pass.
- Signed single-job Release build succeeds, retaining app/helper identifiers and local signing configuration.
- Installed by verified automatic restoration, helper unregister, staged whole-bundle replacement and normal ServiceManagement registration. Five-tick live startup passes in System with helper controlReady, Apple ownership, fan modes 0/0 and no monitoring warning; helper/login registration remains enabled.
- Updated test DMG is in `build/Distribution/2026-10-04`, alongside its checksum and verification report. Existing image/signature/privacy checks apply. It remains Apple Development-signed and unnotarized, with the same distribution and Mac17,9 control limitations described in [packaging delivery](INLINE_MENU_AND_DMG.md).

No screenshots, GUI navigation, visual comparisons or manual fan-profile experiments were used. Automated checks cover models, action dispatch, graph calculations, native control configuration, compilation and packaging. Human review of pointer feel and appearance remains appropriate. Hardware qualification, watchdog, authentication and fan command sequence are unchanged.
