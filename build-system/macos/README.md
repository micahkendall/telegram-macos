# Telegram-iOS on macOS

This port builds the Telegram-iOS application for **arm64 Mac Catalyst on macOS 15 or later**. It uses
the MacOSX SDK and the `arm64-apple-ios15.0-macabi` ABI. It does not build, boot,
or launch an iOS simulator.

## Build

Install the Xcode version pinned in `versions.json`, including its Metal compiler:

```sh
xcodebuild -downloadComponent MetalToolchain
git submodule update --init --recursive --depth 1 --jobs 8
python3 build-system/macos/build.py --output /absolute/path/Telegram-iOS-Mac.app
```

Run from the repository root. Choose an unused output path. The script verifies
the pinned Bazel download, applies the checked-in patches to the pinned build-rule
and tgcalls submodules, checks the Postbox import rules, builds the full
`//Telegram:Telegram` target, converts the fresh archive to a Mac application
bundle, and signs it locally. It rejects app and framework binaries whose Mach-O
platform is not `MACCATALYST`.

The default build cache is `build-input/macos-bazel`. Use `--bazel-user-root` to
reuse another cache. `--jobs` controls parallel compilation.

## API credentials

The first invocation creates `build-input/macos-configuration.json`, which is
ignored by Git. Its initial API ID is `0` and its API hash is empty. That is enough
to compile. A functioning login needs non-placeholder API credentials.
For an independently registered application, obtain your API ID and hash from
<https://my.telegram.org/apps> and enter them in the local JSON file.

For the user-requested native Mac protocol profile, pass `--native-mac-identity`:

```sh
python3 build-system/macos/build.py --native-mac-identity --output /absolute/path/Telegram-iOS-Mac-desktop.app
```

This explicitly selects the public API ID/hash from the native Swift Mac client,
using `native-client-profile.json`, and embeds its version/channel and connection
profile into the packaged application's Info.plist. It does not overwrite the
local configuration file or use the official app's storage, bundle identifier,
keychain, signing identity, or entitlements. The metadata test can compare a
read-only reference checkout and the packaged app:

```sh
python3 build-system/macos/test_protocol.py --reference /path/to/telegram-macos --app /path/to/Telegram-iOS-Mac-desktop.app
```

Both repositories pin the same Telegram-iOS core commit. The Catalyst profile
uses Mac host device/OS values, the `macos` language category, native Mac
initConnection parameter keys, and desktop phone-login inputs. It also enables
the native Mac live engine-switching and liveness fallback branches, defaults
to the Rust engine as the native Mac client does, uses non-cellular network
classification, and preserves release-style login tokens. A user-selected engine
setting is preserved; the server kill switch and normal fallback remain active.
Call negotiation advertises only the reference Mac client's supported versions
and layer. The underlying media/capture library remains the Catalyst-compatible
iOS implementation; this does not establish identical media traffic. Pass
`--calls-reference /path/to/tgcalls` to the metadata test to compare its announced
versions to the pinned Mac tgcalls source (fetch the recorded commit first). QR authorization
is available from the phone-entry screen and uses the existing login-token
export, expiration, update, migration, and password-state handling.

The native Mac app reports a SHA-1 digest of its public signing certificate
chain. The compatibility profile forwards that published digest, inspected from
the Apple-verified native Mac distribution, as connection metadata. It does not
sign this Catalyst app with Telegram's private key: the local app is still
ad-hoc signed and has no production push or associated-domain entitlements.
No cryptographic signature, attestation token, or CAPTCHA success is fabricated.
The distributed Mac binary's build number is newer than its source project's
number; the profile records both and uses the distributed binary's version on
the connection. To recheck the binary metadata and signing-chain digest, add
`--official-app /path/to/the/official/Telegram.app` to the metadata test.
This is protocol-profile alignment, not proof of server-side indistinguishability.
Account login, messaging, calls, media, and background behavior require live
comparison; metadata tests do not establish those outcomes.

Use `--configuration /absolute/path/configuration.json` for a different local
configuration. Keep an independent bundle ID and URL scheme to avoid sharing an
identity with an installed official Telegram app.

## Platform changes

- The standalone app stores its data in Application Support, under its own group
  identifier. Passcode keychain items use a bundle-specific service name. The
  build does not require a signed iOS app-group entitlement.
- The bundled iOS extensions, alternate app icons, and Google reCAPTCHA SDK are
  excluded. That Google SDK contains no Catalyst slice. A requested challenge
  completes without a token, matching the native Mac callback; flows requiring
  a mobile challenge may fail.
- Legacy ES2 renderers use the desktop OpenGL compatibility context through
  prefixed context and view classes. Shader precision syntax is translated, and
  CoreVideo textures use explicit upload/readback. This has a performance cost
  compared with the iOS zero-copy path. Newer effects continue to use Metal.
- Core Image renders through its supported bitmap API before uploading legacy
  textures. VideoToolbox and WebRTC use Catalyst-compatible buffer attributes.
- Pending uploads use a macOS process activity and keep their account workers active.
  The activity ends when uploads finish, the app returns to the foreground, or the
  manager is destroyed.
- iOS-only keyboard conversation context, fold regions, and camera multitasking
  APIs are guarded. Translation services require Mac Catalyst 26; the Mac
  translation sheet uses `TranslationSession` because Apple's iOS translation
  presentation modifier is unavailable on Catalyst.
- The resulting local signature has no Apple push entitlement. Production push
  delivery and distribution signing require a separate signing setup.

## Graphics validation

```sh
python3 build-system/macos/graphics/test.py
```

This builds and runs a real Catalyst executable. It checks shader compilation,
rendered BGRA pixel values, texture sharing between contexts, Core Image upload,
drawable presentation, and vertical image orientation. These checks do not
replace interactive testing of calls, video capture, editing, and authentication
with a real account.

## Live anonymous protocol validation

After a full Catalyst build, this probe links the actual Rust archive used by
the app into a real Catalyst executable and runs public production RPCs:

```sh
python3 build-system/macos/probe_network.py --app /path/to/Telegram-iOS-Mac-native-profile.app --pfs --qr
```

It verifies `help.getNearestDc` and `help.getConfig` response constructors after
fresh key exchange, then repeats with a bound temporary key. With `--qr`, it
also calls `auth.exportLoginToken` to verify the API ID/hash and unauthenticated
QR flow; token contents are never printed or saved. It uses the same
Mac connection profile and built-in production RSA public key. Keys exist only
in memory and are destroyed with the probe; it does not load an account, request
a phone login code, send a message, or persist authentication material. Passing
this probe establishes anonymous RPC and PFS interoperability, not authenticated
login, messaging, media parity, or server-side indistinguishability.
