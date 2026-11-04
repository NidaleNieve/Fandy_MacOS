#!/usr/bin/env python3
"""Choose full verification unless every changed file is public documentation."""
import argparse
import os
from pathlib import Path, PurePosixPath
import subprocess

ROOT_DOCS = {'README.md', 'ARCHITECTURE.md', 'SAFETY.md', 'SECURITY.md', 'AGENTS.md'}


def documentation_path(path):
    file = PurePosixPath(path)
    if file.is_absolute() or '..' in file.parts or '\\' in path:
        return False
    if path in ROOT_DOCS or path == '.gitignore':
        return True
    if file.parts[:1] != ('docs',) or file.parts[:2] == ('docs', 'licenses'):
        return False
    return file.suffix == '.md' or (file.parts[:2] == ('docs', 'images') and
                                     file.suffix in {'.png', '.svg'})


def requires_app_checks(root, base, head):
    if not base or set(base) == {'0'}:
        return True
    result = subprocess.run(['git', 'diff', '--raw', '-z', '--no-renames', '--no-abbrev',
                             base, head, '--'], cwd=root, check=True, capture_output=True)
    fields = result.stdout.split(b'\0')
    if fields == [b'']:
        return True
    if fields.pop() != b'' or len(fields) % 2:
        raise ValueError('Invalid Git diff output')
    for metadata, raw_path in zip(fields[::2], fields[1::2]):
        parts = metadata.split()
        if len(parts) != 5 or not parts[0].startswith(b':'):
            raise ValueError('Invalid Git diff record')
        modes = {parts[0][1:], parts[1]}
        if not modes <= {b'000000', b'100644'} or not documentation_path(os.fsdecode(raw_path)):
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    args = parser.parse_args()
    app = requires_app_checks(Path.cwd(), args.base, args.head)
    output = f'app={str(app).lower()}\n'
    if destination := os.environ.get('GITHUB_OUTPUT'):
        with open(destination, 'a') as stream:
            stream.write(output)
    print('Full app verification required.' if app else 'Documentation-only verification required.')


if __name__ == '__main__':
    main()
