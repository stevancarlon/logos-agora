#!/usr/bin/env python3
"""Install a matching, separate Qt Multimedia runtime for Basecamp 0.3.2.
Does not patch Basecamp, alter sandbox policy, or bundle native code in Agora.
"""
import argparse, pathlib, shutil, subprocess, json
p=argparse.ArgumentParser()
p.add_argument('--qt',type=pathlib.Path,required=True)
p.add_argument('--configure-only',action='store_true',help='Update launcher/desktop without replacing a running runtime')
p.add_argument('--runtime-dir',type=pathlib.Path,default=pathlib.Path.home()/'.local/share/Logos/qt-media-6.9.2')
p.add_argument('--launcher',type=pathlib.Path,default=pathlib.Path.home()/'Applications/LogosBasecamp-Agora')
p.add_argument('--no-desktop',action='store_true',help='Do not modify the desktop shortcut')
p.add_argument('--appimage',type=pathlib.Path,default=pathlib.Path.home()/'Applications/LogosBasecamp-0.3.2-x86_64.AppImage')
a=p.parse_args();qt=a.qt.resolve()
assert subprocess.check_output([str(qt/'bin/qmake'),'-query','QT_VERSION'],text=True).strip()=='6.9.2'
assert a.appimage.is_file()
runtime=a.runtime_dir.resolve()
if not a.configure_only:
 (runtime/'lib').mkdir(parents=True,exist_ok=True)
 for folder in ['plugins/multimedia']:
  shutil.copytree(qt/folder,runtime/folder,dirs_exist_ok=True,symlinks=True)
 for pattern in ['libQt6Multimedia.so*','libQt6FFmpegStub*.so*','libavcodec.so*','libavformat.so*','libavutil.so*','libswresample.so*','libswscale.so*']:
  for f in (qt/'lib').glob(pattern):
   dst=runtime/'lib'/f.name
   if dst.is_symlink(): dst.unlink()
   shutil.copy2(f,dst,follow_symlinks=False)
 if (runtime/'qml/QtMultimedia').exists():
  shutil.rmtree(runtime/'qml/QtMultimedia')  # obsolete QML player runtime from the first integration probe
 renderer=pathlib.Path(__file__).resolve().parents[1]/'build/qt6.9.2-media/qml/Agora/Media'
 assert (renderer/'libagoramedia.so').is_file(), 'Build the media renderer first'
 shutil.copytree(renderer,runtime/'qml/Agora/Media',dirs_exist_ok=True)
 for license in ['LICENSE-MIT','LICENSE-APACHE']:
  shutil.copy2(pathlib.Path(__file__).resolve().parents[1]/license,runtime/('Agora-'+license))
 (runtime/'README.txt').write_text('Qt Multimedia 6.9.2 runtime from official Qt binary distribution, installed using aqtinstall.\nQt: https://download.qt.io/official_releases/qt/6.9/6.9.2/\nLicensing: https://doc.qt.io/qt-6.9/qtmultimedia-index.html#licenses\nFFmpeg: https://doc.qt.io/qt-6.9/qtmultimedia-attribution-ffmpeg.html\nNo Basecamp sandbox policy is changed. Only this runtime QML directory is added to the Qt runtime import path.\n')
# Explicit runtime selection, keeping the original AppImage untouched.
launcher=a.launcher.resolve()
launcher.parent.mkdir(parents=True,exist_ok=True)
import shlex
launcher.write_text('#!/bin/sh\nset -eu\n'+
 'media_runtime='+shlex.quote(str(runtime))+'\n'+
 'export LOGOS_NO_SCHEME_REGISTER=1\n'+
 'export QML_IMPORT_PATH="$media_runtime/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"\n'+
 'export QT_PLUGIN_PATH="$media_runtime/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"\n'+
 'export LD_LIBRARY_PATH="$media_runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'+
 'exec '+shlex.quote(str(a.appimage.resolve()))+' "$@"\n')
launcher.chmod(0o755)
desktop=pathlib.Path.home()/'.local/share/applications/logos-basecamp.desktop'
if desktop.exists() and not a.no_desktop:
 original=desktop.read_text()
 backup=desktop.with_suffix('.desktop.before-agora-media')
 if not backup.exists(): backup.write_text(original)
 lines=original.splitlines()
 lines=[('Exec="'+str(launcher)+'" --uri=%u') if line.startswith('Exec=') else line for line in lines]
 desktop.write_text('\n'.join(lines)+'\n')
print(launcher)
