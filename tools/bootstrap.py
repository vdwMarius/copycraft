#!/usr/bin/env python3
"""Pinned Linux development dependencies; no system writes or secret credentials."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(os.environ.get('COPYCRAFT_TOOLING', '/workspace/tooling'))

def fetch(name, url, digest, algorithm='sha256'):
    path = TOOLS / name
    if not path.exists():
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', url, '-o', str(path)], check=True)
    h = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024*1024), b''):
            h.update(part)
    if h.hexdigest() != digest:
        raise RuntimeError(f'{name}: checksum mismatch; remove the file and retry')
    print(f'Verified {name}', flush=True)
    return path

def main():
    TOOLS.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output(['godot', '--version'], text=True)
    if not version.startswith('4.6.3.stable'):
        raise RuntimeError('Install official Godot 4.6.3 stable before bootstrap')
    voxel = fetch('voxel.zip', 'https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip', '600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8')
    with zipfile.ZipFile(voxel) as archive:
        archive.extractall(ROOT)
    templates = fetch('templates.tpz', 'https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz', 'da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68', 'sha512')
    target = TOOLS / 'data/godot/export_templates/4.6.3.stable'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(templates) as archive:
        for name in ['android_debug.apk', 'android_release.apk', 'linux_debug.x86_64', 'linux_release.x86_64']:
            with archive.open('templates/' + name) as source, (target / name).open('wb') as dest:
                shutil.copyfileobj(source, dest)
    # Google repository's published package SHA1 values (repository2-1.xml).
    for filename, checksum, folder, dest in [
        ('build-tools_r35_linux.zip','2cfaa0bbb2336e9ec18ed3ecea84fa2e2af607bc','android-15','build-tools/35.0.0'),
        ('platform-35_r02.zip','0bb560a90a7a2cbd0dd8348224d518b638fe7949','android-35','platforms/android-35'),
        ('platform-tools_r37.0.2-linux.zip','736a08af10515674e40d8b754fe87390d698da2b','platform-tools','platform-tools')]:
        package = fetch(filename, 'https://dl.google.com/android/repository/' + filename, checksum, 'sha1')
        destination = TOOLS / 'android-sdk' / dest
        if not destination.exists():
            stage = TOOLS / ('stage-' + filename)
            with zipfile.ZipFile(package) as archive:
                archive.extractall(stage)
            source = stage / folder
            if not source.exists():
                source = next(stage.iterdir())
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(source, destination)
        for path in destination.rglob('*'):
            if path.is_file() and (path.parent.name == 'bin' or path.name in ['adb','aapt','aapt2','aidl','apksigner','zipalign','d8']):
                path.chmod(0o755)
    java = Path(shutil.which('java')).resolve().parents[1]
    key = TOOLS / 'debug.keystore'
    if not key.exists():
        subprocess.run([str(java/'bin/keytool'),'-genkeypair','-keystore',str(key),'-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','10000','-storepass','android','-keypass','android','-dname','CN=Android Debug,O=Android,C=US'],check=True)
    config = TOOLS/'config/godot'
    config.mkdir(parents=True, exist_ok=True)
    (config/'editor_settings-4.6.tres').write_text('[gd_resource type="EditorSettings" format=3]\n[resource]\n' + '\n'.join(f'export/android/{k} = "{v}"' for k,v in {'android_sdk_path':TOOLS/'android-sdk','java_sdk_path':java,'debug_keystore':key,'debug_keystore_user':'androiddebugkey','debug_keystore_pass':'android'}.items())+'\n')
    print('Bootstrap complete. Debug signing only; no release credentials configured.')

if __name__ == '__main__':
    main()
