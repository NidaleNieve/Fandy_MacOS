#!/usr/bin/env python3
"""Check the Git index without printing sensitive values. Not a substitute for review."""
import argparse
import getpass
from pathlib import Path
import re
import struct
import subprocess
import zlib

# Only this reviewed, demo-data app rendering may be committed as a binary.
PUBLIC_IMAGES = {'docs/images/profiles.png'}


def png_problems(content):
    if len(content) > 2 * 1024 * 1024 or not content.startswith(b'\x89PNG\r\n\x1a\n'):
        return ['invalid public PNG']
    position = 8
    chunks = []
    while position < len(content):
        if position + 12 > len(content):
            return ['invalid public PNG']
        size = struct.unpack_from('>I', content, position)[0]
        end = position + size + 12
        if end > len(content):
            return ['invalid public PNG']
        kind = content[position + 4:position + 8]
        payload = content[position + 8:end - 4]
        checksum = struct.unpack_from('>I', content, end - 4)[0]
        if zlib.crc32(kind + payload) != checksum:
            return ['invalid public PNG']
        if kind not in {b'IHDR', b'IDAT', b'IEND', b'sRGB', b'gAMA', b'cHRM', b'pHYs'}:
            return ['unreviewed PNG metadata']
        if kind == b'IHDR':
            if chunks or size != 13:
                return ['invalid public PNG']
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            if not (0 < width <= 4096 and 0 < height <= 3072 and depth == 8 and color in {2, 6}
                    and compression == filtering == interlace == 0):
                return ['invalid public PNG']
        if kind == b'IEND' and (size != 0 or end != len(content)):
            return ['invalid public PNG']
        chunks.append(kind)
        position = end
    if not chunks or chunks[0] != b'IHDR' or chunks[-1] != b'IEND' or b'IDAT' not in chunks:
        return ['invalid public PNG']
    return []

PRIVATE_SUFFIXES = ('.local.xcconfig', '.csv', '.jsonl', '.log', '.pem', '.key', '.p12', '.pfx',
                    '.mobileprovision', '.provisionprofile', '.cer', '.ips', '.crash')
PRIVATE_COMPONENTS = {'build', '.build', 'DerivedData', 'xcuserdata', '.swiftpm', '__pycache__',
                      '.codex', '.agents', '.aws', '.vscode', '.idea', 'private'}
PRIVATE_REPORTS = {'BUILD_VERIFICATION.md', 'SENSOR_DISCOVERY.md', 'SENSOR_QUALIFICATION.md',
                   'BOUNDED_MEASUREMENT.md', 'CHIP_COVERAGE.md', 'UNATTENDED_TESTING.md'}
PATTERNS = {
    'home directory': re.compile('/' + r'Users/[^/\s"\'<>]+|/' + r'home/[^/\s"\'<>]+'),
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub credential': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b'),
    'cloud credential': re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'personal email': re.compile(r'\b[A-Za-z0-9_.+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'),
    'inline signing team': re.compile(r'DEVELOPMENT_TEAM["\']?\s*=\s*["\']?[A-Z0-9]{10}\b'),
}


def scan(path, content, signing_ids=(), username=''):
    file = Path(path)
    problems = []
    if (set(file.parts) & PRIVATE_COMPONENTS or path.startswith('docs/local/') or
            file.name in PRIVATE_REPORTS or file.name == '.env' or file.name.startswith('.env.') or
            file.name.endswith(PRIVATE_SUFFIXES)):
        problems.append('private artifact')
    if path in PUBLIC_IMAGES:
        return problems + png_problems(content)
    if len(content) > 512 * 1024 or b'\0' in content:
        return problems + ['binary or oversized artifact']
    try:
        text = content.decode('utf-8')
    except UnicodeDecodeError:
        return problems + ['non-text artifact']
    # These notices contain legally required third-party author/contact attribution.
    third_party_notice = path.startswith('docs/licenses/')
    for label, pattern in PATTERNS.items():
        if label == 'personal email' and third_party_notice:
            continue
        for match in pattern.finditer(text):
            if label == 'personal email' and match.group().split('@')[1] in {'example.com', 'example.invalid', 'fandy.invalid'}:
                continue
            problems.append(f'{label} at line {text.count(chr(10), 0, match.start()) + 1}')
    if any(value and value in text for value in signing_ids):
        problems.append('local signing identifier')
    if len(username) >= 4 and username.lower() not in {'root', 'user', 'runner', 'admin'}:
        if re.search(r'\b' + re.escape(username) + r'\b', text, re.IGNORECASE):
            problems.append('local account name')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', required=True)
    parser.parse_args()
    root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    # Local identifiers are only comparison inputs; they never appear in reports or committed policy.
    signing_ids = set()
    for file in (root / 'Config').rglob('*.local.xcconfig'):
        signing_ids.update(re.findall(r'^DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\s*$', file.read_text(), re.MULTILINE))
    failures = []
    for path in filter(None, paths):
        content = subprocess.check_output(['git', 'show', ':' + path], cwd=root)
        failures.extend((path, issue) for issue in scan(path, content, signing_ids, getpass.getuser()))
    for path, issue in failures:
        print(f'{path}: {issue}')
    if failures:
        print('Public-content check failed. Sensitive values were not printed.')
        return 1
    print(f'Public-content check passed: {sum(bool(path) for path in paths)} staged files.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
