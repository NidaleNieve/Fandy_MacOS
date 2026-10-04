# Install Fandy

## Download and open

1. Open the [latest release](https://github.com/NidaleNieve/Fandy_MacOS/releases/latest).
2. Download `Fandy-0.2.0-arm64.dmg` from **Assets**. The source-code ZIP is for developers.
3. Open the DMG and drag **Fandy** onto **Applications**.
4. Open Fandy from Applications. Look for the fan icon in your menu bar.

Requires an Apple Silicon MacBook Pro and macOS 15 or later. First launch leaves cooling with macOS.

## Allow fan control

In Fandy’s setup window, click **Open System Settings…**. Go to:

**General → Login Items & Extensions → Background App Activity → Fandy**

Enable Fandy, then return to the app. The setup window closes once approval is available. If profiles remain gray, the menu’s **Allow Fan Control…** action opens the same settings. This is permission for Fandy’s background fan helper; it is not a kernel or system extension.

Choose **System** whenever you want macOS to manage cooling. Use one fan-control utility at a time; competing utilities can prevent Fandy from taking control.

## If macOS blocks opening

This initial release is Apple Development-signed and **not notarized**. Another Mac may require a separate Gatekeeper approval or may refuse it.

For an unidentified-developer warning, after checking that you downloaded the official release, follow [Apple’s opening instructions](https://support.apple.com/en-us/102445): **System Settings → Privacy & Security → Open Anyway**, when macOS offers that action. Do not disable Gatekeeper, SIP or other protections. If the warning reports damage or malicious software, stop and [report the exact message](https://github.com/NidaleNieve/Fandy_MacOS/issues).

Developer ID signing and notarization are still required for a smoother general-public installation experience. Background App Activity approval is a separate step and does not bypass Gatekeeper.

## Updating

Choose System and quit Fandy. Replace the copy in Applications with the new release, then reopen it. Your profiles and schedules remain stored locally. macOS may ask you to approve the updated helper again.

## Need help?

[Open an issue](https://github.com/NidaleNieve/Fandy_MacOS/issues) with your Mac model, macOS version, Fandy version and the problem. Review exported diagnostics before posting. Do not attach private schedules, your full configuration or raw personal logs unless you want them public.
