#!/usr/bin/env python3
"""Verify a native Catalyst app and produce the GitHub Release download."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    if app.name != 'Telegram.app':
        parser.error('The release bundle must be named Telegram.app')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    profile = json.loads((ROOT / 'build-system/macos/native-client-profile.json').read_text())
    if info.get('TGMacClientProfile') != profile:
        raise SystemExit('Packaged native Mac API profile differs from the pinned profile')
    if info.get('CFBundleName') != 'Telegram' or info.get('CFBundleDisplayName') != 'Telegram':
        raise SystemExit('Incorrect application display name')
    if info.get('CFBundleSupportedPlatforms') != ['MacOSX']:
        raise SystemExit('Release must be a Mac application bundle')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    binaries = [app / 'Contents/MacOS' / info['CFBundleExecutable']]
    binaries += [p / p.stem for p in sorted((app / 'Contents/Frameworks').glob('*.framework'))]
    for binary in binaries:
        if run('lipo', '-archs', str(binary)) != 'arm64':
            raise SystemExit(f'Expected Apple silicon arm64 binary: {binary}')
        platforms = [line.split()[-1] for line in run('xcrun', 'vtool', '-show-build', str(binary)).splitlines()
                     if line.strip().startswith('platform ')]
        if platforms != ['MACCATALYST']:
            raise SystemExit(f'Expected native Catalyst platform: {binary}')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'Telegram-macos-arm64.zip'
    if archive.exists():
        archive.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
    install = output / 'INSTALL.txt'
    install.write_text('''Telegram for Apple silicon Macs

Requires macOS 15 or later and an Apple silicon (M-series) Mac.
1. Extract Telegram-macos-arm64.zip.
2. Drag Telegram.app into Applications, replacing an older copy if appropriate.
3. Open Telegram from Applications and sign in using QR or phone authorization.

This community build is ad hoc signed, not Developer ID signed or notarized.
If macOS blocks opening it, attempt to open it once, then use System Settings >
Privacy & Security > Open Anyway. Only proceed if you trust this build's source.

Uses the pinned native Swift Telegram for macOS API profile (API ID 9).
Local account data, login tokens, and private build configuration are not shipped.
Existing data uses the independent local.telegramios.maccatalyst identifier.
No iOS simulator or developer tools are needed to run the downloaded app.

Verify the download in Terminal with: shasum -a 256 -c SHA256SUMS.txt
''')
    checksums = []
    for path in (archive, install):
        hasher = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                hasher.update(chunk)
        digest = hasher.hexdigest()
        checksums.append(f'{digest}  {path.name}\n')
    (output / 'SHA256SUMS.txt').write_text(''.join(checksums))
    print(f'Verified {len(binaries)} native arm64 Catalyst binaries; release archive: {archive}')


if __name__ == '__main__':
    main()
