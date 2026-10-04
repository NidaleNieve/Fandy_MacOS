#!/usr/bin/env python3
"""Developer ID release; credentials stay in the local notarytool keychain profile."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

SPEC = importlib.util.spec_from_file_location('package_dmg', Path(__file__).with_name('package-dmg.py'))
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


def developer_identity():
    result = PACKAGE.run(['security', 'find-identity', '-v', '-p', 'codesigning'])
    matches = re.findall(r'\b([0-9A-F]{40})\s+"Developer ID Application:[^"\n]+"', result.stdout.decode())
    if len(matches) != 1:
        raise ValueError('Exactly one valid Developer ID Application identity is required; configure it privately in Xcode')
    return matches[0]


def notarize(path, profile):
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(path), '--keychain-profile', profile,
                             '--wait', '--output-format', 'json'], capture_output=True, timeout=1800)
    # Apple tool output may include private account information. Emit only reviewed status.
    try:
        report = json.loads(result.stdout)
    except (ValueError, TypeError):
        raise ValueError('Notarization failed; inspect the local keychain profile privately') from None
    if result.returncode or not isinstance(report, dict) or report.get('status') != 'Accepted':
        raise ValueError('Apple did not accept the notarization submission; no release was published')


def sign(path, identity, identifier):
    PACKAGE.run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', '--identifier', identifier, path])


def distribute(app, output, profile):
    if not profile.strip() or '\n' in profile or '\r' in profile:
        raise ValueError('A local notarytool keychain profile name is required')
    info, _ = PACKAGE.verify_app(app)
    original_team, _ = PACKAGE.signature(app, 'is.dsr.fandy')
    identity = developer_identity()  # Fail before creating any public artifact.
    name = f"Fandy-{info['CFBundleShortVersionString']}-arm64.dmg"
    if (output / name).exists():
        raise ValueError('Release output already exists; choose a new directory')
    with tempfile.TemporaryDirectory(prefix='fandy-distribution-') as directory:
        work = Path(directory)
        staged = work / 'Fandy.app'
        PACKAGE.run(['ditto', '--noqtn', app, staged])
        sign(staged / PACKAGE.HELPER, identity, 'is.dsr.fandy.fan-helper')
        sign(staged, identity, 'is.dsr.fandy')
        PACKAGE.verify_app(staged)
        team, kind = PACKAGE.signature(staged, 'is.dsr.fandy')
        if team != original_team or kind != 'Developer ID Application':
            raise ValueError('Distribution must preserve the existing trusted signing team')
        archive = work / 'Fandy.zip'
        PACKAGE.run(['ditto', '-c', '-k', '--keepParent', staged, archive])
        notarize(archive, profile)
        PACKAGE.run(['xcrun', 'stapler', 'staple', staged])
        candidate = PACKAGE.package(staged, work / 'image', release_staging=True)
        sign(candidate, identity, 'is.dsr.fandy.disk-image')
        notarize(candidate, profile)
        PACKAGE.run(['xcrun', 'stapler', 'staple', candidate])
        PACKAGE.run(['xcrun', 'stapler', 'validate', candidate])
        PACKAGE.run(['codesign', '--verify', '--strict', candidate])
        PACKAGE.run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', candidate])
        PACKAGE.run(['hdiutil', 'verify', candidate])
        # Verify the final stapled image, not just its pre-notarization predecessor.
        import plistlib
        mounted = plistlib.loads(PACKAGE.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', candidate]).stdout)
        entry = next(x for x in mounted['system-entities'] if 'mount-point' in x)
        try:
            installed = Path(entry['mount-point']) / 'Fandy.app'
            PACKAGE.verify_app(installed)
            PACKAGE.run(['xcrun', 'stapler', 'validate', installed])
            PACKAGE.run(['spctl', '--assess', '--type', 'execute', installed])
        finally:
            PACKAGE.run(['hdiutil', 'detach', entry['dev-entry']])
        checksum = hashlib.sha256(candidate.read_bytes()).hexdigest()
        report = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                  'architecture': 'arm64', 'minimumMacOS': '15.0', 'signatureClass': kind,
                  'notarized': True, 'sha256': checksum, 'compatibility': PACKAGE.compatibility_manifest(),
                  'verified': ['app/helper matching team and identity', 'hardened runtime',
                               'app notarization and staple', 'DMG notarization and staple',
                               'Gatekeeper app and image', 'mounted final payload', 'privacy payload', 'image integrity']}
        output.mkdir(parents=True, exist_ok=True)
        PACKAGE.run(['ditto', candidate, output / name])
        (output / (name + '.sha256')).write_text(f'{checksum}  {name}\n')
        (output / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Created {name}; Developer ID signed, notarized and stapled')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=PACKAGE.ROOT / 'build/DerivedData/Build/Products/Release/Fandy.app')
    parser.add_argument('--output', type=Path, default=PACKAGE.ROOT / 'build/Distribution-Release')
    parser.add_argument('--keychain-profile', required=True, help='Local profile name, never a password or API key')
    args = parser.parse_args()
    try:
        distribute(args.app.resolve(), args.output.resolve(), args.keychain_profile)
    except (ValueError, OSError, StopIteration, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, ValueError) else 'Distribution failed; no verified release was published')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
