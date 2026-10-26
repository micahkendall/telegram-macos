#!/usr/bin/env python3
"""Compare the real Catalyst MTApiEnvironment with the pinned native Mac profile."""
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
parser.add_argument("--reference", type=Path, help="Read-only checkout of TelegramMessenger/telegram-macos")
parser.add_argument("--calls-reference", type=Path, help="tgcalls checkout containing the pinned native Mac commit")
parser.add_argument("--official-app", type=Path, help="Verify the signed native Mac distribution against the pinned metadata")
parser.add_argument("--app", type=Path, help="Validate an already packaged application")
args = parser.parse_args()
profile = json.loads((MACOS / "native-client-profile.json").read_text())
info = {
    "CFBundleIdentifier": "local.telegramios.protocol-test",
    "CFBundleExecutable": "protocol-test",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": profile["version"],
    "CFBundleVersion": profile["build"],
    "SOURCE": profile["channel"],
    "TGMacClientProfile": dict(profile),
}
if args.app:
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    assert info["TGMacClientProfile"] == dict(profile)
if args.reference:
    reference = args.reference.resolve()
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(reference), *arguments], text=True).strip()
    assert git("rev-parse", "HEAD") == profile["reference_commit"]
    assert git("ls-tree", "HEAD", "submodules/telegram-ios").split()[2] == profile["shared_core_commit"]
    credentials = (reference / "packages/ApiCredentials/Sources/ApiCredentials/Config.swift").read_text()
    assert re.search(r"apiId:Int32\s*\{\s*return " + profile["api_id"], credentials)
    assert profile["api_hash"] in credentials
    assert 'return "macos"' in credentials
    assert profile["network_bundle_id"] in credentials
    project = (reference / "Telegram.xcodeproj/project.pbxproj").read_text()
    assert "MARKETING_VERSION = " + profile["version"] + ";" in project
    assert "CURRENT_PROJECT_VERSION = " + profile["reference_source_build"] + ";" in project
    assert "SOURCE = " + profile["channel"] in (reference / "Telegram-Mac/Release.xcconfig").read_text()
if args.calls_reference:
    versions = []
    for source in ("tgcalls/InstanceImpl.cpp", "tgcalls/v2/InstanceV2Impl.cpp", "tgcalls/v2/InstanceV2ReferenceImpl.cpp"):
        code = subprocess.check_output(["git", "-C", str(args.calls_reference), "show", profile["reference_calls_commit"] + ":" + source], text=True)
        body = code.split("::GetVersions() {", 1)[1].split("return result;", 1)[0]
        versions += re.findall(r'result.push_back\("([^\"]+)"\)', body)
    assert sorted(versions) == profile["call_versions"]
    wrapper = subprocess.check_output(["git", "-C", str(args.calls_reference), "show", profile["reference_calls_commit"] + ":macos/Sources/OngoingCallThreadLocalContext.mm"], text=True)
    assert re.search(r"maxLayer\s*\{\s*return " + str(profile["call_max_layer"]) + ";", wrapper)
if args.official_app:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "-R", '=anchor apple generic and certificate leaf[subject.OU] = "6N38VWS5BX"', str(args.official_app)], check=True)
    inspected = json.loads(subprocess.check_output(["swift", str(MACOS / "inspect_reference.swift"), str(args.official_app)], text=True))
    for field in ("version", "build", "signing_certificate_sha1"):
        assert inspected[field] == profile[field], field
    assert inspected["source"] == profile["channel"]
    assert inspected["bundle_id"] == profile["network_bundle_id"]
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="telegram-native-protocol-") as temporary:
    contents = Path(temporary) / "ProtocolTest.app/Contents"
    binary = contents / "MacOS/protocol-test"
    binary.parent.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    command = ["xcrun", "clang", "-fobjc-arc", "-fmodules", "-Werror", "-target", "arm64-apple-ios15.0-macabi", "-isysroot", sdk,
               "-iframework", sdk + "/System/iOSSupport/System/Library/Frameworks",
               "-DTELEGRAM_API_LAYER=" + re.search(r"currentLayer\(\) -> UInt\s*\{\s*return (\d+)", (ROOT / "submodules/TelegramCore/Sources/State/Serialization.swift").read_text()).group(1),
               "-I" + str(ROOT / "submodules/MtProtoKit/PublicHeaders"),
               str(ROOT / "submodules/MtProtoKit/Sources/MTMacOSClientInfo.m"),
               str(ROOT / "submodules/MtProtoKit/Sources/MTApiEnvironment.m"),
               str(MACOS / "tests/protocol.m"), "-framework", "Foundation", "-framework", "UIKit", "-o", str(binary)]
    subprocess.run(command, check=True)
    assert "platform MACCATALYST" in subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    environment = json.loads(subprocess.check_output([str(binary)], text=True))
    assert environment["api_id"] == int(profile["api_id"])
    assert environment["device_model"]
    assert environment["system_version"] == subprocess.check_output(["sysctl", "-n", "kern.osproductversion"], text=True).strip()
    assert environment["app_version"] == "{} ({}) {}".format(profile["version"], profile["build"], profile["channel"])
    assert environment["lang_pack"] == "macos"
    assert environment["lang_code"] == "en"
    assert environment["copy_preserves_environment"]
    assert environment["params"] == {"bundleId": profile["network_bundle_id"], "data": profile["signing_certificate_sha1"]}
    serialization = (ROOT / "submodules/TelegramCore/Sources/State/Serialization.swift").read_text()
    assert "return " + str(environment["layer"]) in serialization
    hardware = json.loads(subprocess.check_output(["system_profiler", "-json", "SPHardwareDataType", "-detailLevel", "mini"], text=True))["SPHardwareDataType"][0]
    expected_model = hardware["machine_name"]
    if hardware.get("chip_type", "").startswith("Apple "):
        expected_model += hardware["chip_type"][5:]
    assert environment["device_model"] == expected_model
    print(json.dumps(environment, indent=2))
print("Native Catalyst connection profile matches the pinned Mac reference; the local code signature and account behavior are not asserted.")
