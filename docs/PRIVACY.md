# Fandy privacy policy

Effective date: October 5, 2026.

Fandy operates locally. It has no account system, analytics, advertising, tracking or automatic crash uploads. The application does not send temperature readings, profiles or schedules to its developer.

## What stays on your Mac

- Saved profiles, temperature curves, schedules, pauses, activation conditions, shortcuts and preferences.
- Current fan speeds and temperature readings used for display and control.
- Local rotating diagnostic logs about fan-control operations and failures.
- Application identities and process start times used for rules such as ending a profile when a game closes. Fandy does not read application contents, browser history or keystrokes.

Configuration and logs are stored in your user Library’s Application Support/Fandy directory. macOS separately stores service approvals, login registration and window preferences. Runtime fan leases, target RPM and active process watches are not restored from saved files after a restart.

## Permissions

Background App Activity allows the bundled privileged fan helper to run. The normal application runs as your user. The helper has a narrow authenticated fan-control interface and no general file, shell or network API.

Fandy does not request Accessibility, Screen Recording, Input Monitoring, Full Disk Access, Camera or Microphone permissions. Files are read or written only when you choose an import or export through a file dialog. It does not scan your documents.

## Sharing and external services

You control exports. Configuration/profile exports can contain profile names, schedules, application rules and preferences. Sharing those files shares their contents. Diagnostic exports use a restricted summary that omits custom names, paths and raw readings.

GitHub downloads, issue reports and links opened in a browser are handled by GitHub or the destination website under their own policies. Anything you post in a public GitHub issue is public. Update checks contact GitHub for the release feed and update archives. GitHub receives ordinary network request information, including your IP address and updater/app version. Sparkle system profiling is disabled. No temperature readings, configurations, schedules or diagnostic logs are sent. Updates can be disabled in Settings by turning off Automatic updates and choosing Never.

## Removing data

Choose System and quit Fandy before removing its local data. Delete Application Support/Fandy to remove saved configuration and logs. macOS service approvals are managed separately in System Settings. Reset to Defaults in Fandy resets configuration; it does not erase historical logs or macOS permission records.

## Questions

Use the [project’s issue tracker](https://github.com/NidaleNieve/Fandy_MacOS/issues) for privacy questions without including private logs or personal information. This policy will be updated if data handling changes.
