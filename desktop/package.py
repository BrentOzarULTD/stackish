#!/usr/bin/env python3
"""Create self-contained Windows or macOS review builds. No signing or publishing."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', choices=['win-x64', 'osx-x64', 'osx-arm64'], required=True)
parser.add_argument('--output', type=Path, default=root/'artifacts')
args = parser.parse_args()
output = args.output.resolve()/args.runtime
publish = output/'publish'
if publish.exists():
    shutil.rmtree(publish)
subprocess.run(['dotnet', 'publish', str(root/'Stackish.Desktop'), '-c', 'Release', '-r', args.runtime,
                '--self-contained', 'true', '-p:PublishSingleFile=false', '-p:PublishTrimmed=false',
                '-p:UseSharedCompilation=false', '-o', str(publish)], check=True)
if args.runtime.startswith('osx'):
    app = output/'Stackish.app'
    if app.exists():
        shutil.rmtree(app)
    executable = app/'Contents'/'MacOS'
    executable.mkdir(parents=True, exist_ok=True)
    shutil.copytree(publish, executable, dirs_exist_ok=True)
    os.chmod(executable/'Stackish', 0o755)
    with (app/'Contents'/'Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleName': 'Stackish', 'CFBundleDisplayName': 'Stackish',
                      'CFBundleIdentifier': 'com.brentozar.stackish', 'CFBundleExecutable': 'Stackish',
                      'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.0',
                      'CFBundleVersion': '1', 'NSHighResolutionCapable': True}, stream)
    shutil.make_archive(str(output/('Stackish-'+args.runtime)), 'zip', output, 'Stackish.app')
    print(app)
else:
    shutil.make_archive(str(output/('Stackish-'+args.runtime)), 'zip', publish)
    print(publish/'Stackish.exe')
