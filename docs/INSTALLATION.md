# Install Fandy

Requires an Apple Silicon MacBook Pro and macOS 15 or later. See [Compatibility](COMPATIBILITY.md) for tested hardware.

1. [Download Fandy](https://github.com/NidaleNieve/Fandy_MacOS/releases/latest/download/Fandy-0.4.0-arm64.dmg).
2. Open the DMG and drag **Fandy** into **Applications**.
3. Open `/Applications/Fandy.app` and follow its setup window.
4. In **System Settings → General → Login Items & Extensions → Background App Activity**, enable **Fandy**.
5. Click the fan icon in the menu bar and choose a profile.

The app must remain at `/Applications/Fandy.app` for its fan helper to register. Run one fan-control utility at a time.

## Updating

Automatic updates check daily by default; change the frequency or disable automatic checks in Settings. Downloaded background updates normally install when you quit. You can also check manually or install a staged update from Settings.

To update manually, choose System, quit Fandy, replace the copy in Applications, and reopen it. Existing profiles and preferences are preserved. Do not delete a helper while it still owns manual fan control.

## If fan control is unavailable

Confirm that you opened the copy in Applications and enabled Background App Activity. Use **Allow Fan Control…** or the setup window's retry action. Reinstall a fresh signed download if Fandy reports a damaged or invalid installation; avoid changing permissions or deleting system files to work around it.

[Report an issue](https://github.com/NidaleNieve/Fandy_MacOS/issues) with your Mac model, macOS version, Fandy version and displayed error. Review attachments for personal information before posting.
