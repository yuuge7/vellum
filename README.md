# Vellum

**AR tracing for Android.** Prop your phone over a sheet of paper, pin a picture to the page, and draw what you see through the camera.

Vellum overlays a reference image on the live camera feed. It can anchor the image to the paper so it stays in place when the phone moves, turn photos into clean line art or shading layers, walk you through step-by-step lessons, and record a time-lapse of the drawing.

[Download the latest release](../../releases/latest) · [Report a bug](../../issues)

---

## Contents

- [Features](#features)
- [Installing](#installing)
- [Development setup](#development-setup)
- [Project structure](#project-structure)
- [How it works](#how-it-works)
- [Contributing](#contributing)
- [Releases and versioning](#releases-and-versioning)
- [Release signing (maintainers)](#release-signing-maintainers)
- [Permissions and privacy](#permissions-and-privacy)

## Features

**Tracing**
- Full-screen back camera with the reference image drawn on top; flashlight toggle while tracing.
- Pinch to resize, drag to move, twist to rotate. Fit, Mirror and Rotate 90° shortcuts.
- **Lock** ignores all touches on the image so a resting hand never nudges it.
- Opacity slider (0–100 %) and **Strobe**, which flickers the image (on/off or 50 %/off, 1–8 Hz) so gaps between your lines and the reference stand out.

**Pin to paper (AR)**
- **Sheet edges** finds the four corners of the page and keeps the image glued to it, even when a hand covers a corner.
- **Surface** tracks texture on any flat surface when there is no clean sheet in view.
- Runs on a background isolate; the pose is smoothed so the overlay stays steady without lagging.

**Image tools**
- **Lines**: turns a photo into clean outlines, with adjustable detail, line weight and ink colour.
- **Tones**: splits a photo into 3 or 4 brightness bands (shadows to highlights), each toggleable, in grey or colour-coded.

**Content**
- Import from the Android photo picker or take a photo with the camera.
- Built-in templates: animals, botanical, objects, people, patterns and photo-like scenes.
- Step-by-step lessons (Cat face, Tulip, Head proportions, Cube in perspective). Each step fades in over dimmed earlier steps.
- Any photo can become a lesson: outline, shadows, mid-tones, highlights.

**Time-lapse**
- Periodic snapshots of the page plus the overlay are encoded into an H.264 video and saved to the gallery (`Pictures/Vellum`).

## Installing

1. Download `Vellum-vX.Y.apk` from the [latest release](../../releases/latest).
2. Open it on your phone and allow installing from that source when Android asks.
3. Grant camera access on first launch.

Requires Android 7.0 (API 24) or newer and a back camera. Every release is signed with the same key, so a new version installs over the previous one.

To check that an APK is genuine, compare its signing certificate with this SHA-256 fingerprint:

```
0A:BA:06:D6:0E:97:30:33:58:CD:8E:7E:AE:F6:CD:28:CF:D3:63:8B:2B:62:7C:1F:C1:95:53:21:C9:6F:4B:E6
```

```bash
apksigner verify --print-certs Vellum-vX.Y.apk   # from Android SDK build-tools
```

## Development setup

### Prerequisites

| Tool | Version |
| --- | --- |
| [Flutter](https://docs.flutter.dev/get-started/install) | 3.47.0, stable channel (Dart 3.13) |
| JDK | 17 or newer (Temurin recommended; Android Studio's bundled JBR works) |
| Android SDK | Platform 36 and build-tools, via Android Studio or the command-line tools |
| Device | Android phone with USB debugging, or an Android emulator with a camera |

Run `flutter doctor` and fix anything it reports under *Flutter* and *Android toolchain* before continuing.

### Clone and run

```bash
git clone <repository-url> vellum
cd vellum
flutter pub get
flutter run                # debug build on the connected device or emulator
```

`flutter run --release` also works without any signing setup: when `key.properties` is missing, release builds are signed with the local debug key.

### Checks

Run these before opening a pull request; CI runs the same ones.

```bash
flutter analyze            # must report no issues
flutter test               # vision, imaging, geometry and lesson tests
flutter build apk --debug  # confirms the Android (Kotlin) side compiles
```

### Testing on an emulator

Set the emulator's back camera to **VirtualScene** (Device Manager > Edit > Advanced settings). Hold Alt and use the mouse with W/A/S/D/Q/E to move around the scene; Extended controls > Camera lets you place an image on the wall or table. That is enough to exercise the camera overlay, time-lapse and AR tracking without a phone, but check Pin to paper on a real device over a real sheet before relying on it.

## Project structure

```
lib/
  main.dart          app entry point, orientation and system UI
  camera/            camera service, camera-to-screen geometry, AR session glue
  capture/           time-lapse recorder (Dart side)
  content/           procedural templates, lessons, shared pen styles
  imaging/           line art, tonal breakdown, YUV conversion, image helpers
  models/            overlay state, lesson state machine, trace documents
  tracking/          homography geometry, image ops, KLT, sheet detector, tracker, isolate worker
  ui/                theme, home screen, trace screen, painters, widgets
android/app/src/main/kotlin/com/vellum/ar_drawing/
  MainActivity.kt        method channel "vellum/timelapse"
  TimelapseEncoder.kt    MediaCodec H.264 encoder
test/                unit tests, with a synthetic camera scene for the tracker
.github/workflows/   CI for pull requests, automatic releases from main
```

## How it works

**Tracking** (`lib/tracking`). Camera frames go to a background isolate; frames are dropped while it is busy so tracking never queues behind the camera.
- *Sheet edges*: multi-threshold connected components, convex hull, maximum-area quadrilateral, then line-fit corners.
- *Surface*: Shi-Tomasi features followed by pyramidal Lucas-Kanade optical flow with forward-backward checks.
- Both estimate a homography with RANSAC. In sheet mode the feature pose is fused with the sheet outline to correct drift. The result is smoothed with One Euro filters and applied to the overlay as a perspective transform.

**Imaging** (`lib/imaging`). Line art is a Canny pipeline: blur, Sobel, non-maximum suppression, hysteresis and speck removal. Tones use multi-level Otsu thresholding.

**Time-lapse** (`lib/capture`, `TimelapseEncoder.kt`). Composites of the camera frame and the overlay are streamed over a method channel into a native MediaCodec encoder and saved to the gallery.

## Contributing

1. Fork the repository (or create a branch if you have write access).
2. Make your change on a feature branch, e.g. `feature/grid-overlay` or `fix/strobe-timing`.
3. Keep `flutter analyze` clean and add or update tests in `test/` for logic changes (tracking, imaging, models).
4. Try the change on a device or emulator, not only in tests.
5. Open a pull request against `main` with a short description and, for UI changes, a screenshot. CI must pass before merging.

Guidelines:
- Match the surrounding code style; the analyzer uses `flutter_lints`.
- Keep heavy image work off the UI thread (isolates, as the tracker and imaging code do).
- Do not edit the `version:` line in `pubspec.yaml` unless you intend a major version jump (see below).
- Never commit `key.properties`, `*.jks` or other signing material; `.gitignore` already excludes them.

## Releases and versioning

Every push to `main` triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which:

1. Runs `flutter analyze` and `flutter test`. If either fails, nothing is released.
2. Picks the next version from the existing `vX.Y` tags and writes it to `pubspec.yaml`, then commits that back to `main` as `chore(release): Vellum vX.Y [skip ci]`.
3. Builds a release APK signed with the release key.
4. Publishes a GitHub release titled **Vellum vX.Y** (tag `vX.Y`) with `Vellum-vX.Y.apk`, its SHA-256 checksum and notes generated from the commits.

Versions only go up: v1.0, v1.1, v1.2, … Each version gets its own tag and release, so a release is never overwritten. The Android `versionCode` is `major * 10000 + minor`, so every release installs over the previous one.

- **Pull after pushing.** The workflow adds a version commit to `main`, so run `git pull` before your next push.
- **Push without releasing:** put `[skip ci]` in the commit message.
- **Major release:** run the *Release* workflow manually (Actions > Release > Run workflow) and choose `major`, or set `version: 2.0.0` in `pubspec.yaml` and push.
- Releases run one at a time; quick successive pushes queue instead of racing for the same version.

## Release signing (maintainers)

Release APKs are signed with an upload key that lives outside the repository. Two files in the project root make up the key; both are git-ignored:

| File | Contents |
| --- | --- |
| `vellum-release.jks` | the keystore (PKCS12, RSA 4096, alias `vellum`, valid until 2054) |
| `key.properties` | `storeFile`, `storePassword`, `keyAlias`, `keyPassword` |

> **Back both files up somewhere safe**, such as a password manager or encrypted storage. If the key is lost, new releases cannot update existing installs; users would have to uninstall first. If it leaks, anyone can sign an update that looks like yours.

### Using the key on another machine

1. Clone the repository and complete [Development setup](#development-setup).
2. Copy `vellum-release.jks` and `key.properties` from your backup into the project root, next to `pubspec.yaml`.
3. Leave `storeFile=vellum-release.jks` as is (it is resolved from the project root), or set it to an absolute path if you keep the keystore elsewhere.
4. Build: `flutter build apk --release`. The APK in `build/app/outputs/flutter-apk/` is now signed with the release key.
5. Confirm it matches the fingerprint in [Installing](#installing):
   ```bash
   keytool -list -v -keystore vellum-release.jks -alias vellum
   ```

### GitHub Actions secrets

The release workflow restores the key from four repository secrets (*Settings > Secrets and variables > Actions > New repository secret*):

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | the keystore file, base64-encoded |
| `KEYSTORE_PASSWORD` | `storePassword` from `key.properties` |
| `KEY_ALIAS` | `keyAlias` from `key.properties` |
| `KEY_PASSWORD` | `keyPassword` from `key.properties` |

Encode the keystore:

```powershell
# Windows PowerShell: copies the value to the clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vellum-release.jks")) | Set-Clipboard
```

```bash
base64 -w0 vellum-release.jks      # Linux
base64 -i vellum-release.jks       # macOS
```

Or set all four with the [GitHub CLI](https://cli.github.com/) from the project root:

```bash
base64 -w0 vellum-release.jks | gh secret set KEYSTORE_BASE64
gh secret set KEYSTORE_PASSWORD    # prompts for the value
gh secret set KEY_ALIAS --body vellum
gh secret set KEY_PASSWORD         # prompts for the value
```

If a secret is missing, the workflow stops before bumping the version, and the build refuses to fall back to the debug key.

## Permissions and privacy

| Permission | Why |
| --- | --- |
| Camera | live preview, tracking and time-lapse frames |
| Storage (Android 9 and older only) | saving time-lapse videos to the gallery |

The merged manifest also lists microphone (`RECORD_AUDIO`, declared by the CameraX plugin) and `ACCESS_NETWORK_STATE` (declared by AndroidX Media3). Vellum records video without sound and never asks for the microphone.

Vellum has no internet permission. Photos, camera frames and recordings are processed on the device and never leave it.
