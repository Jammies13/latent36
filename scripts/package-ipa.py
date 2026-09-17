"""Package a genuine device build; refuse missing/non-arm64 executables."""
from pathlib import Path
import plistlib
import struct
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / "build/DerivedData/Build/Products/Release-iphoneos/Latent36.app"
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
binary = app / info["CFBundleExecutable"]
magic, cpu = struct.unpack("<II", binary.read_bytes()[:8])
assert magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected an arm64 Mach-O device binary"
assert info["CFBundlePackageType"] == "APPL"
assert "iPhoneOS" in info["CFBundleSupportedPlatforms"], "Simulator builds cannot run on a phone"

ipa = root / "build/Latent36.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        if path.is_file():
            entry = zipfile.ZipInfo("Payload/Latent36.app/" + path.relative_to(app).as_posix())
            entry.create_system = 3
            entry.external_attr = (0o100755 if path == binary else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, "Corrupt IPA archive"
print(f"Created {ipa} ({ipa.stat().st_size:,} bytes). Sign/import with SideStore or LiveContainer.")
