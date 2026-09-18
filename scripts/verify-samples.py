"""Reject metadata-bearing preview originals before building or publishing."""
from pathlib import Path
import struct
import hashlib

root = Path(__file__).resolve().parents[1]
names = ['clouds', 'river', 'aurora', 'motorsport']
for name in names:
    path = root / 'Latent36/PreviewSamples' / (name + '.png')
    data = path.read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), f'{name}: invalid PNG'
    offset = 8
    kinds = []
    while offset < len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        assert kind in (b'IHDR', b'IDAT', b'IEND'), f'{name}: unexpected chunk {kind}'
        kinds.append(kind)
        offset += 12 + length
    assert offset == len(data) and kinds[-1] == b'IEND'
    print(f'{name}.png: image data only; SHA256 {hashlib.sha256(data).hexdigest()}')
print('PASS: all four built-in photographs contain no ancillary metadata.')
