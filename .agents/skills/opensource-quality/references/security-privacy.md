# Security and Privacy — Project Reference

**Purpose.** This app holds camera access, user photographs, and API credentials. `goal.md` §16 sets
the policy; this file makes it concrete.

**Last verified:** 2026-08-15.

---

## Secrets

API keys and tokens must **never** be:

- hardcoded in source
- committed to git (including in history, including in a deleted file)
- printed in logs or console output
- stored in plaintext configuration, `UserDefaults`, or a plist
- included in analytics, telemetry, or crash reports
- passed as a command-line argument (visible in process listings)

On iOS, use the **Keychain**. Read at the point of use; do not hold a key in a long-lived property
where it can end up in a memory dump or a debug description.

Practical measures:

- A `Redacted`-style wrapper whose `description` and `debugDescription` return `"<redacted>"`, so a
  key cannot be logged by accident through string interpolation.
- A secret-scanning step in CI.
- `.gitignore` covering local config, `*.env`, and any local SDK path file — **before** the first
  commit, not after.
- If a key is ever committed, rotate it. Removing it from history does not un-leak it.

## Logging

`OSLog`, one subsystem, one category per module.

- **Default to `privacy: .private`.** `.public` is opt-in and must be provably non-sensitive.
- Never log: credentials, image data or buffers, file paths containing user content, precise
  location, or full AI request/response bodies.
- Structured logging over string concatenation — it redacts properly and is queryable in Console.
- Log *decisions and transitions*, not per-frame data. A per-frame log is a performance problem and a
  privacy problem at once.
- Debug logging that dumps a `SceneState` is a privacy leak: it contains people's positions and poses.
  Gate it behind a debug build **and** an explicit opt-in.

## User photographs

The strongest privacy commitment this project makes is that it does not need the cloud to work.

- **Do not store** captured images beyond what the feature requires. Post-shot review needs the image
  for the duration of the review, not forever.
- **Do not transmit** unnecessarily. Realtime perception is entirely local; that is an architectural
  requirement (`goal.md` §11), and privacy is one of its main payoffs.
- **No continuous video upload, ever.** Not as an option, not as a "high accuracy mode".
- Writing to the photo library requires `NSPhotoLibraryAddUsageDescription` and should use the
  add-only authorization level, which does not grant read access to the user's library.

## Data sent to an AI provider

Send the minimum that the request needs:

- Structured `SceneState` where it suffices — often it does.
- When an image is needed: **one** image, downscaled (longest edge ~1024 px), re-encoded, with
  **EXIF and GPS stripped**. Re-encoding from pixel data rather than forwarding the original file is
  the reliable way to guarantee metadata is gone.
- Never send: location, device identifiers, contacts, the photo library, or previously captured
  images unrelated to the request.

Requirements:

- A **structured-state-only mode** (no images) must exist and be honored end to end.
- The user must be able to see which backend is in use and what is sent. A backend selector that does
  not disclose this is not enough.
- Backend choice is the user's: local Mac, managed cloud, BYOK, self-hosted, or on-device
  (`goal.md` §10). Each has a different privacy profile and the interface should not obscure that.

## Permissions

| Key | Why |
|---|---|
| `NSCameraUsageDescription` | Camera capture. Required. |
| `NSPhotoLibraryAddUsageDescription` | Saving captures. Add-only. |
| `NSLocalNetworkUsageDescription` | Mac bridge / camera bridge discovery. |
| `NSBonjourServices` | Must declare the specific service types used. |
| `NSMotionUsageDescription` | CoreMotion, if required for the configuration. |

Write purpose strings a user can actually evaluate: what is accessed and what it is used for. "This
app needs camera access" is a bad string; naming the feature is a good one.

Handle denial as a normal state with a route to Settings, never a dead end (`goal.md` §17).

## Network

- HTTPS for anything leaving the device. Certificate pinning only if there is a threat model that
  justifies the operational cost.
- The **local network bridge** is the weak point: a plaintext HTTP service on a shared Wi-Fi network
  can be reached by other devices. Require a pairing step, use a per-session token, and bind
  deliberately. Do not assume "it is only on my LAN" — coffee-shop Wi-Fi is a LAN.
- Never disable ATS wholesale to make local development easier. Scope any exception narrowly.

## Threat model, briefly

Realistic risks, in order:

1. **Accidental key leakage** through logs, screenshots, git history, or a crash report. Most likely
   by a wide margin.
2. **Unintended image transmission** — a debug path or an error handler that uploads more than
   intended.
3. **Local network exposure** of the camera bridge.
4. **Dependency supply chain** — every dependency is code running with the app's permissions. Another
   reason the target is zero.

Not in the threat model: a determined attacker with physical device access, or platform compromise.

## Open source specifics

- Never commit vendor SDKs, licensed material, or proprietary documentation (see `camera-integration`
  → `references/licensing.md`).
- Sample and fixture data must not contain identifiable people without consent. Recorded sessions used
  as test fixtures are photographs of real humans — get permission before committing them, and prefer
  fixtures made by contributors of themselves.
- Issue templates and CONTRIBUTING should tell people not to paste API keys or full logs into issues,
  because they will otherwise.

## Official sources

- Keychain services: https://developer.apple.com/documentation/security/keychain_services
- `OSLog` privacy: https://developer.apple.com/documentation/os/logger
- Protecting user privacy: https://developer.apple.com/documentation/uikit/protecting_the_user_s_privacy
- App Transport Security: https://developer.apple.com/documentation/security/preventing_insecure_network_connections
- Bonjour / local network privacy: https://developer.apple.com/documentation/network/bonjour

## Open questions

- Should the local camera bridge use TLS with a self-signed certificate plus pinning, or a
  pre-shared pairing token over plain HTTP? The second is far simpler; decide before the bridge ships.
- What retention does post-shot review need — in-memory only, or a temporary file for the duration of
  the session?
- Should the app show a persistent indicator when a remote backend is active, the way the OS shows a
  camera indicator? It would make the privacy posture continuously visible.
