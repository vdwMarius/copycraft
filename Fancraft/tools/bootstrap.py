#!/usr/bin/env python3
"""Set up the pinned Godot 4.6.3 toolchain for Fancraft Android builds (Linux).

Downloads go to $FANCRAFT_TOOLING (default /home/user/tooling), never into Git.
Android signing uses apksigner/zipalign from the Android SDK build-tools if present,
otherwise from the Ubuntu packages (`apt-get install apksigner zipalign`).
Creates a local *debug* keystore only - not a release key.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

VERSION = '4.6.3'
BASE = f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/'
TEMPLATES_SHA512 = 'da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68'
TOOLS = Path(os.environ.get('FANCRAFT_TOOLING', '/home/user/tooling'))
ROOT = Path(__file__).resolve().parents[1]
# Voxel Tools (Zylann/godot_voxel, MIT) GDExtension, pinned release archive.
VOXEL_URL = 'https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip'
VOXEL_SHA256 = '600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8'


def fetch(name, url):
    path = TOOLS / name
    if not path.exists():
        print(f'Downloading {url}', flush=True)
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', url, '-o', str(path)], check=True)
    return path


def main():
    TOOLS.mkdir(parents=True, exist_ok=True)
    editor = TOOLS / f'Godot_v{VERSION}-stable_linux.x86_64'
    if not editor.exists():
        with zipfile.ZipFile(fetch('godot.zip', BASE + f'Godot_v{VERSION}-stable_linux.x86_64.zip')) as z:
            z.extractall(TOOLS)
        editor.chmod(0o755)
    tpz = fetch('templates.tpz', BASE + f'Godot_v{VERSION}-stable_export_templates.tpz')
    h = hashlib.sha512()
    with tpz.open('rb') as f:
        for part in iter(lambda: f.read(1 << 20), b''):
            h.update(part)
    if h.hexdigest() != TEMPLATES_SHA512:
        raise SystemExit('templates.tpz checksum mismatch; delete it and retry')
    target = TOOLS / f'data/godot/export_templates/{VERSION}.stable'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(tpz) as z:
        for name in ['android_debug.apk', 'android_release.apk', 'version.txt']:
            if not (target / name).exists():
                with z.open('templates/' + name) as src, (target / name).open('wb') as dst:
                    shutil.copyfileobj(src, dst)
    voxel = fetch('voxel.zip', VOXEL_URL)
    if hashlib.sha256(voxel.read_bytes()).hexdigest() != VOXEL_SHA256:
        raise SystemExit('voxel.zip checksum mismatch; delete it and retry')
    with zipfile.ZipFile(voxel) as z:
        for name in z.namelist():
            keep = name.startswith('addons/zylann.voxel/') and not name.endswith('/')
            if '/bin/' in name:
                keep = keep and ('linux.' in name and 'x86_64' in name or 'android' in name and 'arm64' in name)
            if keep:
                z.extract(name, ROOT)
    # Minimal SDK layout that Godot's non-Gradle exporter needs.
    sdk = TOOLS / 'android-sdk'
    bt = sdk / 'build-tools/35.0.0'
    bt.mkdir(parents=True, exist_ok=True)
    for tool in ['apksigner', 'zipalign']:
        if not (bt / tool).exists():
            found = shutil.which(tool)
            if not found:
                raise SystemExit(f'{tool} not found: install Android build-tools or `apt-get install apksigner zipalign`')
            (bt / tool).symlink_to(found)
    for stub in [sdk / 'platform-tools/adb', sdk / 'cmdline-tools/latest/bin/sdkmanager']:
        if not stub.exists():
            stub.parent.mkdir(parents=True, exist_ok=True)
            real = shutil.which(stub.name)
            if real:
                stub.symlink_to(real)
            else:
                stub.write_text('#!/bin/sh\nexit 0\n')
                stub.chmod(0o755)
    java = Path(shutil.which('java')).resolve().parents[1]
    key = TOOLS / 'debug.keystore'
    if not key.exists():
        subprocess.run([str(java / 'bin/keytool'), '-genkeypair', '-keystore', str(key), '-alias', 'androiddebugkey',
                        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-storepass', 'android',
                        '-keypass', 'android', '-dname', 'CN=Android Debug,O=Android,C=US'], check=True)
    config = TOOLS / 'config/godot'
    config.mkdir(parents=True, exist_ok=True)
    settings = {'android_sdk_path': sdk, 'java_sdk_path': java, 'debug_keystore': key,
                'debug_keystore_user': 'androiddebugkey', 'debug_keystore_pass': 'android'}
    (config / 'editor_settings-4.6.tres').write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
        + ''.join(f'export/android/{k} = "{v}"\n' for k, v in settings.items()))
    print(f'Bootstrap complete. Use GODOT={editor} or put it on PATH. Debug signing only.')


if __name__ == '__main__':
    main()
