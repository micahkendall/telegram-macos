#!/usr/bin/env python3
"""Build Telegram-iOS for the Mac Catalyst ABI, without an iOS simulator."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PATCHES = Path(__file__).resolve().parent / "patches"
MAC_PROFILE = json.loads((Path(__file__).resolve().parent / "native-client-profile.json").read_text())


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT, **kwargs)


def apply_patches():
    repositories = [(name, ROOT / "build-system/bazel-rules" / name) for name in ("apple_support", "rules_apple", "rules_swift")]
    repositories.append(("tgcalls", ROOT / "submodules/TgVoipWebrtc/tgcalls"))
    for name, repo in repositories:
        patch = PATCHES / (name + ".patch")
        reverse = subprocess.run(
            ["git", "-C", str(repo), "apply", "--reverse", "--check", str(patch)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if reverse.returncode == 0:
            continue
        run(["git", "-C", repo, "apply", "--check", patch])
        run(["git", "-C", repo, "apply", patch])


def bazel_binary():
    pin = json.loads((ROOT / "versions.json").read_text())["bazel"]
    version, expected_hash = pin.split(":", 1)
    target = ROOT / "build-input" / ("bazel-" + version + "-darwin-arm64")
    target.parent.mkdir(exist_ok=True)
    if not target.exists():
        url = "https://github.com/bazelbuild/bazel/releases/download/{}/{}".format(version, target.name)
        temporary = target.with_suffix(".download")
        urllib.request.urlretrieve(url, temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected_hash:
            temporary.unlink()
            raise RuntimeError("Downloaded Bazel checksum does not match versions.json")
        temporary.replace(target)
    if hashlib.sha256(target.read_bytes()).hexdigest() != expected_hash:
        raise RuntimeError("Bazel checksum does not match versions.json")
    target.chmod(0o755)
    return target


def configure(path, bazel, native_mac_identity=False):
    sys.path.insert(0, str(ROOT / "build-system/Make"))
    from BuildConfiguration import build_configuration_from_json
    if not path.exists():
        configuration = json.loads((ROOT / "build-system/template_minimal_development_configuration.json").read_text())
        configuration.update(bundle_id="local.telegramios.maccatalyst", api_id="0", api_hash="", team_id="", app_specific_url_scheme="telegramiosmac")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(configuration, indent=2) + "\n")
        path.chmod(0o600)
    configuration = build_configuration_from_json(str(path))
    if native_mac_identity:
        configuration.api_id = MAC_PROFILE["api_id"]
        configuration.api_hash = MAC_PROFILE["api_hash"]
        configuration.enable_icloud = False
        configuration.is_internal_build = "false"
    repository = ROOT / "build-input/configuration-repository"
    repository.mkdir(parents=True, exist_ok=True)
    (repository / "MODULE.bazel").write_text('module(name = "build_configuration")\n')
    (repository / "BUILD").touch()
    (repository / "provisioning").mkdir(exist_ok=True)
    (repository / "provisioning/BUILD").touch()
    configuration.write_to_variables_file(str(bazel), False, "development", str(repository / "variables.bzl"))
    if configuration.api_id == "0" or not configuration.api_hash:
        print("Build-only configuration: set your own api_id and api_hash in {} to enable sign-in.".format(path), flush=True)


def verify_mach_o(binary):
    output = run(["xcrun", "vtool", "-show-build", binary], capture_output=True, text=True).stdout
    platforms = [line.split()[-1] for line in output.splitlines() if line.strip().startswith("platform ")]
    if not platforms or any(item != "MACCATALYST" for item in platforms):
        raise RuntimeError("Expected MACCATALYST binary: {}\n{}".format(binary, output))


def package(destination, native_mac_identity=False):
    archive = ROOT / "bazel-bin/Telegram/Telegram.ipa"
    if not archive.is_file():
        raise RuntimeError("Full Telegram build produced no archive")
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise RuntimeError("Output already exists: {}; choose another --output path".format(destination))
    # Always read the fresh archive, never the possibly stale *_archive-root directory.
    with tempfile.TemporaryDirectory(prefix="telegram-catalyst-") as temporary:
        staging = Path(temporary)
        with zipfile.ZipFile(archive) as source:
            source.extractall(staging)
        source = staging / "Payload/Telegram.app"
        info = plistlib.loads((source / "Info.plist").read_bytes())
        executable = info["CFBundleExecutable"]
        verify_mach_o(source / executable)
        contents = staging / "Telegram-iOS-Mac.app/Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        (contents / "MacOS").mkdir()
        for item in source.iterdir():
            if item.name in ("Info.plist", "_CodeSignature", "embedded.mobileprovision"):
                continue
            if item.name == executable:
                target = contents / "MacOS" / item.name
            elif item.name == "Frameworks":
                target = contents / item.name
            else:
                target = resources / item.name
            shutil.move(str(item), target)
        binary = contents / "MacOS" / executable
        binary.chmod(0o755)
        run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", binary])
        for key in ("LSRequiresIPhoneOS", "UIRequiredDeviceCapabilities", "MinimumOSVersion", "DTPlatformVersion", "DTSDKName"):
            info.pop(key, None)
        info.update(CFBundleSupportedPlatforms=["MacOSX"], UIDeviceFamily=[6], LSMinimumSystemVersion="15.0", DTPlatformName="macosx", CFBundleDisplayName="Telegram", CFBundleName="Telegram")
        if native_mac_identity:
            info.update(CFBundleShortVersionString=MAC_PROFILE["version"], CFBundleVersion=MAC_PROFILE["build"], SOURCE=MAC_PROFILE["channel"])
            info["TGMacClientProfile"] = dict(MAC_PROFILE)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        framework_dir = contents / "Frameworks"
        if framework_dir.exists():
            for framework in sorted(framework_dir.glob("*.framework")):
                library = framework / framework.stem
                verify_mach_o(library)
                library.chmod(0o755)
                framework_info = framework / "Info.plist"
                if framework_info.exists():
                    metadata = plistlib.loads(framework_info.read_bytes())
                    metadata["CFBundleSupportedPlatforms"] = ["MacOSX"]
                    metadata["DTPlatformName"] = "macosx"
                    metadata.pop("MinimumOSVersion", None)
                    framework_info.write_bytes(plistlib.dumps(metadata))
                run(["codesign", "--force", "--sign", "-", framework])
        run(["codesign", "--force", "--sign", "-", contents.parent])
        run(["codesign", "--verify", "--deep", "--strict", contents.parent])
        shutil.copytree(contents.parent, destination, symlinks=True)
    print("Native Mac Catalyst app: {}".format(destination), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", type=Path, default=ROOT / "build-input/macos-configuration.json")
    parser.add_argument("--output", type=Path, default=ROOT / "build-input/Telegram-iOS-Mac.app")
    parser.add_argument("--bazel-user-root", type=Path, default=ROOT / "build-input/macos-bazel")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 4, 12))
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--package-only", action="store_true")
    parser.add_argument("--native-mac-identity", action="store_true", help="Use the pinned native Swift Mac client's public API identity and connection profile")
    args = parser.parse_args()
    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("This port currently targets Apple silicon Macs")
    apply_patches()
    bazel = bazel_binary()
    configure(args.configuration.resolve(), bazel, args.native_mac_identity)
    if args.prepare_only:
        return
    if not args.package_only:
        run([sys.executable, "build-system/Make/PostboxImportCheck.py"])
        run([bazel, "--output_user_root=" + str(args.bazel_user_root.resolve()), "build", "//Telegram:Telegram", "--config=mac-catalyst", "-c", "dbg", "--jobs=" + str(args.jobs), "--keep_going", "--verbose_failures", "--curses=no", "--color=no"])
    package(args.output, args.native_mac_identity)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
