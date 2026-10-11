# Helper installation recovery — 0.3.2 build 26

A stale development build reproduced ServiceManagement error **-67056**, “code has no resources but signature indicates they must be present.” The Background App Activity approval was already enabled. Independent signature and Gatekeeper checks accepted the installed, notarized build 25; its helper reported enabled, bootstrap ready and no fault. Closing the old development process and reopening the installed copy restored normal operation. The broken build was removed from Launch Services and retained outside app discovery.

Startup, migration and retry now check the app’s resource signature before modifying registration. Invalid signatures receive a reinstall-in-Applications message, disable custom activation and do not open a permission guide. System restoration remains available. Valid development signatures retain their existing location policy; Developer ID distribution still requires installation in Applications. This changes no fan transaction, client authentication requirement or hardware support recipe.

Tests were added first and failed because the installation policy and failure reporting were absent. The four focused tests (signature errors, location policy, approval presentation and version identity) then passed. The complete software suites pass **491 Swift tests** (72 hardware, 241 core, 178 app) and **58 tool tests**. One-job signed Release compilation passes. Observations of the installed helper were status-only; no loud profile, stress load, user-data reset or permission reset was performed.

Build 26 remains local. The working installed copy was reopened rather than replaced. No GitHub release, updater publication or pull request was created.
