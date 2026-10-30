#!/usr/bin/env python3
"""Verify the shipped listing bytes and README images without external services."""
import hashlib
import json
from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'marketing/app-store/1.0/manifest.json').read_text())
for asset in manifest['assets']:
    path = root / 'marketing/app-store' / asset['file']
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == asset['sha256'], f'Changed listing asset: {path}'
    if path.suffix == '.png':
        assert data[:8] == b'\x89PNG\r\n\x1a\n', path
        assert struct.unpack('>II', data[16:24]) == (asset['width'], asset['height']), path
for source in re.findall(r'<img[^>]+src="([^"]+)"', (root / 'README.md').read_text()):
    assert (root / source).is_file(), f'Missing README image: {source}'
print(f"PASS: {len(manifest['assets'])} App Store assets match the manifest; README images exist.")
