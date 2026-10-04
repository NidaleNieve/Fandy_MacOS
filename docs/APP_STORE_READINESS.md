# Mac App Store assessment

Reviewed October 4, 2026. **Current status: blocked; no App Store submission or approval.**

The GitHub release is a direct-download app. Uploading the same binary to App Store Connect would not clear the technical restrictions below. Developer ID notarization is a separate direct-distribution process, not App Store approval.

## Current blockers

| Requirement | Fandy’s current implementation | Result |
| --- | --- | --- |
| Sandbox: [Apple App Sandbox documentation](https://developer.apple.com/documentation/security/app-sandbox/) and review guideline 2.4.5(i) | App and root helper are intentionally unsandboxed. | Blocked. |
| Root escalation: [guideline 2.4.5(v)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) | The authenticated fan helper runs as root. | Blocked. |
| Public interfaces: [guideline 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements) | Public IOKit calls carry an undocumented AppleSMC command ABI and generation-specific SMC keys. | No demonstrated App Store-compatible fan-control API. |
| Consent for startup/background work: [guideline 2.4.5(iii)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) | Login registration defaults on; a helper remains available after GUI quit for recovery. | Store variant needs explicit opt-in and an approved background lifecycle. |

Apple’s [SMAppService guidance](https://developer.apple.com/forums/thread/802443) supports sandboxed jobs, but requires a sandboxed app’s job to be sandboxed too. SMAppService does not waive the root or private-interface restrictions. Simply enabling a sandbox entitlement would break the existing controller rather than make it compliant.

## Work before a viable Store version

1. Obtain Apple guidance on a public, permitted fan-control interface and its entitlement requirements. Include the exact AppleSMC operations and helper lifecycle in the technical inquiry. No inquiry has been sent on the user’s behalf.
2. If Apple identifies no supported route, decide whether to keep the full controller as a notarized direct-download app or design a separate genuinely useful Store product. Do not conceal an external root-helper dependency from review.
3. For any approved architecture, validate sandboxed app/helper access, user-selected imports with security-scoped access, application rules, global shortcuts, local storage and System-first recovery. Re-run physical safety gates whenever the fan backend changes.
4. Add explicit launch-at-login consent and a readily accessible in-app privacy-policy link. The public [privacy policy](PRIVACY.md) is prepared, but the app has not gained that link in this documentation-only release.
5. Create App Store Connect metadata, age rating, support and privacy URLs, marketing icon, actual screenshots, encryption/export-compliance answers and detailed hardware review notes. Confirm the final privacy labels against the actual Store binary; the current app has no automatic collection/upload service.
6. Select an appropriate source/distribution license and preserve third-party notices. Fandy’s original source currently has no separate open-source license.
7. Build with Apple Distribution signing, validate the Store archive, complete hardware/OS acceptance and submit for Apple review only after the architecture blockers are resolved.

## Direct download now

The GitHub DMG is Developer ID-signed, notarized and stapled. App and image signatures, tickets and Gatekeeper assessment pass. Distribution uses `Scripts/distribute.py`; no certificate or notarization credential is committed to Git. The signer’s identity is part of Apple’s certificate and remains visible; the owner has explicitly accepted this for public releases.

No claim of App Store readiness, private entitlement approval, physical compatibility on inaccessible Macs or guaranteed recovery while the helper is dead is made.
