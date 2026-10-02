#!/usr/bin/env python3
"""Create self-contained builds and verify their extracted ZIPs. Mac signing defaults to ad-hoc; Developer ID signing is optional. No notarization or publishing."""
import argparse
import os
from pathlib import Path
import plistlib
import platform
from verify_package import verify
import shutil
import subprocess

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', choices=['win-x64', 'osx-x64', 'osx-arm64'], required=True)
parser.add_argument('--output', type=Path, default=root/'artifacts')
parser.add_argument('--signing-identity', help='Mac Developer ID Application certificate name; omit for an ad-hoc review build')
args = parser.parse_args()
if args.signing_identity and (not args.runtime.startswith('osx') or
                             not args.signing_identity.startswith('Developer ID Application: ')):
    parser.error('--signing-identity requires a Mac runtime and a Developer ID Application certificate')
if args.runtime.startswith('osx') and platform.system() != 'Darwin':
    parser.error('Mac packaging requires macOS for signing and ZIP verification')
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
    resources = app/'Contents'/'Resources'
    resources.mkdir(exist_ok=True)
    shutil.copy2(root/'Stackish.Desktop'/'Assets'/'Stackish.icns', resources/'Stackish.icns')
    with (app/'Contents'/'Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleName': 'Stackish', 'CFBundleDisplayName': 'Stackish',
                      'CFBundleIdentifier': 'com.brentozar.stackish', 'CFBundleExecutable': 'Stackish',
                      'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'Stackish.icns', 'CFBundleShortVersionString': '0.1.0',
                      'CFBundleVersion': '1', 'NSHighResolutionCapable': True}, stream)
    # Sign nested files first, then seal the complete bundle. The .NET apphost's
    # original signature predates Info.plist and does not sign this app bundle.
    signing = ['codesign', '--force', '--sign', args.signing_identity or '-']
    if args.signing_identity:
        signing += ['--timestamp', '--options', 'runtime']
    for item in sorted(executable.rglob('*')):
        if item.is_file() and item != executable/'Stackish':
            subprocess.run(signing + [str(item)],
                           check=True, stdout=subprocess.DEVNULL)
    bundle_signing = signing.copy()
    if args.signing_identity:
        bundle_signing += ['--entitlements', str(root/'macos.entitlements')]
    subprocess.run(bundle_signing + [str(app)], check=True)
    archive = output/('Stackish-'+args.runtime+'.zip')
    if archive.exists():
        archive.unlink()
    # Python's ZIP writer loses the extended-attribute signatures of managed
    # assemblies. Preserve them in AppleDouble records, as Archive Utility expects.
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    verify(archive, args.runtime)
    print(app)
else:
    shutil.make_archive(str(output/('Stackish-'+args.runtime)), 'zip', publish)
    verify(output/('Stackish-'+args.runtime+'.zip'), args.runtime)
    print(publish/'Stackish.exe')
