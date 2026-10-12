#!/usr/bin/env python3
"""Insert the native-video probe into an explicitly disposable installed profile."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--profile', type=Path, required=True)
p.add_argument('--video-file', type=Path, help='Local MP4 or WebM acceptance fixture')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
if not (a.profile / '.agora-disposable-profile').is_file():
    p.error('Refusing to modify an unmarked profile')
main = a.profile / 'plugins/logos_forum/qml/Main.qml'
text = main.read_text(encoding='utf-8')
if 'id: hostVideoProbe' in text:
    p.error('Video probe is already installed')
probe = (root / 'native/tests/host/VideoProbe.qml.inc').read_text(encoding='utf-8')
video = (a.video_file or root / 'design/agora/demo-media/playback-test.mp4').resolve()
if not video.is_file() or video.suffix.lower() not in ('.mp4', '.webm'):
    p.error('Provide an existing MP4 or WebM fixture')
probe = probe.replace('VIDEO_FILE_JSON', json.dumps(video.as_uri()))
end = text.rfind('}')
if end < 0 or text[end:].strip() != '}':
    p.error('Unexpected Main.qml root layout')
main.write_text(text[:end] + probe + text[end:], encoding='utf-8')
