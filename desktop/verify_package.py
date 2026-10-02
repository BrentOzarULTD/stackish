#!/usr/bin/env python3
"""Verify the extracted delivery archive, not the pre-archive build directory."""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile
import zipfile


def verify(archive, runtime, require_notarized=False):
    archive = Path(archive).resolve()
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None:
            raise RuntimeError('ZIP integrity check failed')
    with tempfile.TemporaryDirectory(prefix='stackish-package-check-') as directory:
        root = Path(directory)
        if runtime.startswith('osx'):
            if platform.system() != 'Darwin':
                raise RuntimeError('Mac packages must be verified on macOS')
            # ditto preserves resource forks / extended-attribute signatures on
            # managed assemblies, as macOS Archive Utility does.
            subprocess.run(['ditto', '-x', '-k', str(archive), str(root)], check=True)
            app = root/'Stackish.app'
            executable = app/'Contents'/'MacOS'/'Stackish'
            if not executable.stat().st_mode & 0o111:
                raise RuntimeError('Mac launcher lost executable permissions')
            subprocess.run(['lipo', '-verify_arch', 'arm64' if runtime == 'osx-arm64' else 'x86_64', str(executable)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
            if require_notarized:
                subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
                subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=4', str(app)], check=True)
            else:
                print('Bundle integrity verified. Developer-preview only: notarization/Gatekeeper acceptance NOT established.')
        else:
            with zipfile.ZipFile(archive) as zipped:
                zipped.extractall(root)
            if not (root/'Stackish.exe').is_file() or not (root/'Stackish.dll').is_file():
                raise RuntimeError('Missing Windows launcher or application assembly')
        print(f'Extracted package verified: {archive.name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive')
    parser.add_argument('--runtime', choices=['osx-arm64', 'osx-x64', 'win-x64'], required=True)
    parser.add_argument('--require-notarized', action='store_true')
    args = parser.parse_args()
    if args.require_notarized and not args.runtime.startswith('osx'):
        parser.error('--require-notarized applies only to Mac packages')
    verify(args.archive, args.runtime, args.require_notarized)
