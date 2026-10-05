#!/usr/bin/env python3
"""Package an existing signed Release app without installing or operating its helper."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HELPER = Path('Contents/Library/HelperTools/FandyFanHelper')
SERVICE = Path('Contents/Library/LaunchDaemons/is.dsr.fandy.fan-service.plist')



def run(args):
    result = subprocess.run([str(x) for x in args], capture_output=True, timeout=120)
    if result.returncode:
        # Signing tool output may contain certificate owner or private local paths.
        raise ValueError(f'{Path(str(args[0])).name} verification/packaging failed')
    return result


def validate_metadata(info, service):
    if info.get('CFBundleIdentifier') != 'is.dsr.fandy' or info.get('CFBundleExecutable') != 'Fandy':
        raise ValueError('Unexpected app identity or executable')
    for field in ['CFBundleShortVersionString', 'CFBundleVersion']:
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', str(info.get(field, ''))):
            raise ValueError('Invalid bundle version')
    if info.get('LSMinimumSystemVersion') != '15.0':
        raise ValueError('Review changed minimum macOS version before packaging')
    if service.get('Label') != 'is.dsr.fandy.fan-service' or service.get('BundleProgram') != str(HELPER):
        raise ValueError('Unexpected helper identity or program path')
    if service.get('ProgramArguments') != ['FandyFanHelper']:
        raise ValueError('Unexpected helper argument vector')
    if service.get('MachServices') != {'is.dsr.fandy.fan-helper': True}:
        raise ValueError('Unexpected helper services')


def signature(path, expected_id):
    run(['codesign', '--verify', '--strict', path])
    description = run(['codesign', '-dv', '--verbose=4', path]).stderr.decode()
    fields = dict(line.split('=', 1) for line in description.splitlines() if '=' in line)
    if fields.get('Identifier') != expected_id or fields.get('TeamIdentifier') in [None, 'not set']:
        raise ValueError('Missing trusted signing team or unexpected identifier')
    if 'runtime' not in fields.get('CodeDirectory v', '') and not re.search(r'flags=.*\bruntime\b', description):
        raise ValueError('Hardened runtime is required')
    entitlements = run(['codesign', '-d', '--entitlements', ':-', path]).stdout.strip()
    if entitlements and plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
        raise ValueError('Debugging entitlement is forbidden in packaged builds')
    authority = next((line.partition('=')[2] for line in description.splitlines() if line.startswith('Authority=')), '')
    if authority.startswith('Apple Development:'):
        kind = 'Apple Development'
    elif authority.startswith('Developer ID Application:'):
        kind = 'Developer ID Application'
    else:
        raise ValueError('Unsupported signing certificate class')
    return fields['TeamIdentifier'], kind


def check_payload(app):
    # A signed bundle, not the working directory, is the only payload source.
    forbidden = {'.csv', '.jsonl', '.log', '.p12', '.pfx', '.pem', '.key', '.xcconfig'}
    for path in app.rglob('*'):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()):
                raise ValueError('App payload contains an external symlink')
        elif path.is_file():
            if path.suffix.lower() in forbidden or any(part.endswith('.dSYM') for part in path.parts):
                raise ValueError('App payload contains private/development files')
            if re.search(rb'/' + rb'Users/[^/\x00\n]+/', path.read_bytes()):
                raise ValueError('App payload contains a developer home path; rebuild Release with path mapping')


def verify_app(app):
    if not app.is_dir() or app.name != 'Fandy.app':
        raise ValueError('A signed Fandy.app bundle is required')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    validate_metadata(info, plistlib.loads((app / SERVICE).read_bytes()))
    run(['codesign', '--verify', '--deep', '--strict', app])
    team, kind = signature(app, 'is.dsr.fandy')
    helper_team, helper_kind = signature(app / HELPER, 'is.dsr.fandy.fan-helper')
    if (team, kind) != (helper_team, helper_kind):
        raise ValueError('App/helper signing identities do not match')
    for binary in [app / 'Contents/MacOS/Fandy', app / HELPER]:
        if run(['lipo', '-archs', binary]).stdout.decode().strip() != 'arm64':
            raise ValueError('Unexpected architecture; Apple Silicon only for v1')
    check_payload(app)
    return info, kind


def compatibility_manifest():
    # This is release metadata, never hardware authority. The signed Swift registry
    # is the sole source of the notebook roster and reference revision.
    source = (ROOT / 'Sources/FandyHardware/DeviceRegistry.swift').read_text()
    families = dict((f'M{family}', re.findall(r'"(Mac[^" ]+)"', models))
                    for family, models in re.findall(r'\(\.m([1-5]), \[(.*?)\]\)', source))
    if set(families) != {'M1', 'M2', 'M3', 'M4', 'M5'} or any(not x for x in families.values()):
        raise ValueError('Compiled device registry cannot be represented in release metadata')
    revision = re.search(r'statsRevision = "([0-9a-f]{40})"', source)
    if not revision:
        raise ValueError('Missing pinned source revision')
    return {'locallyTested': ['Mac17,9'], 'referenceSupportedFamilies': families,
            'statsRevision': revision[1], 'runtimeChecksRequired': True,
            'interfaces': ['direct mode', 'bounded Ftst handover'],
            'otherHardwarePhysicallyTested': False}


def package(app, output, release_staging=False):
    info, kind = verify_app(app)
    if release_staging:
        if kind != 'Developer ID Application':
            raise ValueError('Release staging requires Developer ID Application signing')
        run(['xcrun', 'stapler', 'validate', app])
        run(['spctl', '--assess', '--type', 'execute', app])
    output.mkdir(parents=True, exist_ok=True)
    name = f"Fandy-{info['CFBundleShortVersionString']}-arm64.dmg"
    dmg = output / name
    if dmg.exists():
        raise ValueError('Output already exists; choose a new output directory')
    with tempfile.TemporaryDirectory(prefix='fandy-package-') as directory:
        staging = Path(directory) / 'image'
        staging.mkdir()
        run(['ditto', '--noqtn', app, staging / 'Fandy.app'])
        (staging / 'Applications').symlink_to('/Applications')
        verify_app(staging / 'Fandy.app')
        temporary = Path(directory) / name
        run(['hdiutil', 'create', '-format', 'UDZO', '-volname', 'Fandy', '-srcfolder', staging, temporary])
        run(['hdiutil', 'verify', temporary])
        # Check the actual image read-only without mounting in Finder or launching.
        mounted = plistlib.loads(run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', temporary]).stdout)
        devices = mounted['system-entities']
        volume = next(Path(e['mount-point']) for e in devices if 'mount-point' in e)
        device = next(e['dev-entry'] for e in devices if 'mount-point' in e)
        try:
            if {p.name for p in volume.iterdir()} - {'.Trashes', '.fseventsd'} != {'Fandy.app', 'Applications'}:
                raise ValueError('Unexpected image contents')
            verify_app(volume / 'Fandy.app')
            if not (volume / 'Applications').is_symlink() or (volume / 'Applications').readlink() != Path('/Applications'):
                raise ValueError('Missing Applications install shortcut')
        finally:
            run(['hdiutil', 'detach', device])
        # Publish only after the disk image and its mounted app have passed checks.
        run(['ditto', temporary, dmg])
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (output / (name + '.sha256')).write_text(f'{checksum}  {name}\n')
    manifest = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                'architecture': 'arm64', 'minimumMacOS': '15.0', 'compatibility': compatibility_manifest(),
                'signatureClass': kind, 'notarized': False, 'sha256': checksum,
                'verified': ['app/helper signatures', 'matching team', 'hardened runtime', 'no debug entitlement',
                             'privacy payload check', 'disk image integrity', 'read-only mounted payload']}
    (output / 'verification.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Created {name}; signature class: {kind}; notarized: no')
    return dmg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/DerivedData/Build/Products/Release/Fandy.app')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/Distribution')
    args = parser.parse_args()
    try:
        package(args.app.resolve(), args.output.resolve())
    except (ValueError, OSError, StopIteration, subprocess.TimeoutExpired) as error:
        # Don't print arbitrary OS/tool errors which could expose developer paths.
        print(str(error) if isinstance(error, ValueError) else 'Packaging failed; check the signed Release bundle and output directory')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
