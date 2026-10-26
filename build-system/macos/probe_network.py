#!/usr/bin/env python3
"""Run public RPCs with throwaway keys through the app's actual Catalyst Rust archive."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MACOS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", required=True, type=Path)
parser.add_argument("--qr", action="store_true", help="Also request an ephemeral QR token; never print or persist it")
parser.add_argument("--pfs", action="store_true", help="Also verify temporary-key binding before public RPCs")
args = parser.parse_args()
info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
profile = json.loads((MACOS / "native-client-profile.json").read_text())
assert info["TGMacClientProfile"] == profile
archive = ROOT / "bazel-bin/third-party/mtproto-engine/libmtproto_engine_ffi.a"
assert archive.is_file(), "Build the full Catalyst app first"
schema = (ROOT / "submodules/TelegramApi/swift_scheme.tl").read_text()
for definition in ("jsonObject#99c1d49d", "jsonObjectValue#c0de1bd9", "jsonString#b71e767a", "config#cc1a241e"):
    assert definition in schema
if args.qr:
    assert "auth.exportLoginToken#b7e085fe" in schema
    assert "auth.loginToken#629f1980" in schema
layer = re.search(r"currentLayer\(\) -> UInt\s*\{\s*return (\d+)", (ROOT / "submodules/TelegramCore/Sources/State/Serialization.swift").read_text()).group(1)
example = (ROOT / "third-party/mtproto-engine/crates/mtproto-core/examples/live_rpc.rs").read_text()
pem = bytes(re.search(r'const PROD_KEY: &str = "(.*?)";', example).group(1), "utf8").decode("unicode_escape")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="telegram-catalyst-network-") as temporary:
    contents = Path(temporary) / "NetworkProbe.app/Contents"
    binary = contents / "MacOS/network-probe"
    binary.parent.mkdir(parents=True)
    info["CFBundleExecutable"] = binary.name
    info["CFBundleIdentifier"] = "local.telegramios.network-probe"
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    key = Path(temporary) / "production-public-key.pem"
    key.write_text(pem)
    command = ["xcrun", "clang", "-fobjc-arc", "-fmodules", "-Werror", "-target", "arm64-apple-ios15.0-macabi", "-isysroot", sdk,
               "-iframework", sdk + "/System/iOSSupport/System/Library/Frameworks", "-DTELEGRAM_API_LAYER=" + layer,
               "-I" + str(ROOT / "submodules/MtProtoKit/PublicHeaders"),
               "-I" + str(ROOT / "third-party/mtproto-engine/crates/mtproto-ffi/include"),
               str(ROOT / "submodules/MtProtoKit/Sources/MTMacOSClientInfo.m"),
               str(ROOT / "submodules/MtProtoKit/Sources/MTApiEnvironment.m"),
               str(MACOS / "tests/live_rpc.m"), str(archive),
               "-framework", "Foundation", "-framework", "UIKit", "-framework", "Security", "-framework", "SystemConfiguration", "-lresolv", "-liconv", "-o", str(binary)]
    subprocess.run(command, check=True)
    assert "platform MACCATALYST" in subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    for mode in (["plain", "pfs"] if args.pfs else ["plain"]):
        result = subprocess.run([str(binary), str(key), mode] + (["qr"] if args.qr else []), text=True, capture_output=True, timeout=50)
        if result.stderr:
            print(result.stderr)
        print(result.stdout, end="", flush=True)
        result.check_returncode()
        assert json.loads(result.stdout)["success"]
print("Public RPCs passed through the app's native Catalyst Rust library. No existing account credentials or keys were used; new test keys and QR tokens were not printed or persisted.")
