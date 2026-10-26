#!/usr/bin/env python3
"""Exercise Catalyst rendering, shader translation, and CoreVideo pixel readback."""
import pathlib
import platform
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
GRAPHICS = pathlib.Path(__file__).resolve().parent
if platform.system() != "Darwin" or platform.machine() != "arm64":
    raise SystemExit("Requires an Apple silicon Mac")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="telegram-catalyst-graphics-") as directory:
    binary = pathlib.Path(directory) / "roundtrip"
    command = ["xcrun", "clang", "-fobjc-arc", "-DGL_SILENCE_DEPRECATION=1", "-DGLES_SILENCE_DEPRECATION=1", "-target", "arm64-apple-ios15.0-macabi", "-isysroot", sdk, "-iframework", sdk + "/System/iOSSupport/System/Library/Frameworks", "-I" + str(GRAPHICS / "include"), str(GRAPHICS / "MacOpenGL.m"), str(GRAPHICS / "tests/roundtrip.m")]
    for framework in ("Foundation", "UIKit", "OpenGL", "CoreVideo", "QuartzCore", "CoreGraphics", "CoreImage"):
        command.extend(["-framework", framework])
    command.extend(["-o", str(binary)])
    subprocess.run(command, check=True)
    kind = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    if "platform MACCATALYST" not in kind:
        raise SystemExit("Test binary is not a native Mac Catalyst binary")
    subprocess.run([str(binary)], check=True)
