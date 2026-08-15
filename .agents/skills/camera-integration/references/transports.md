# Camera Transports — PTP, ImageCaptureCore, UVC, Vendor SDKs

**Purpose.** The candidate ways to move control commands and image data between AI Photographer and
an external camera, what each can and cannot do, and where each can run. Claims carry evidence
labels (see the parent SKILL.md).

**Last verified:** 2026-08-15.

---

## The platform problem

Sony provides **no iOS build** of the Camera Remote SDK — *confirmed* by its absence from Sony's
published platform list (Windows, macOS, Linux). This single fact shapes the architecture: an iPhone
cannot drive a Sony body through the official SDK, so External Camera Mode needs either a macOS
bridge or a non-SDK transport.

## Transport options

### 1. Sony Camera Remote SDK (CrSDK) on macOS

- **What it gives:** the vendor-supported control surface — live view, property read/write, focus,
  shutter, transfer. A7C II (ILCE-7CM2) is supported; support was added in SDK version 1.10 —
  *likely*, from Sony's published release notes; confirm against the current support matrix at
  integration time.
- **Where it runs:** macOS, Windows, Linux. **Not iOS.**
- **Language:** C++. Needs a C-compatible shim to reach Swift.
- **Licensing:** restrictive — see [licensing.md](licensing.md). Not redistributable.
- **Verdict:** the primary path for the macOS bridge. Highest fidelity, worst licensing.

### 2. Apple ImageCaptureCore (macOS)

- **What it gives:** `ICDeviceBrowser`, `ICCameraDevice`, `ICCameraFile` — device discovery, browsing
  the camera's filesystem, downloading images, and some capture triggering on supported devices.
  Apple's own PTP-backed layer.
- **Where it runs:** **macOS only.** The framework is unavailable on iOS.
- **What it does not give:** it is an *image capture* API, not a camera *control* API. Fine-grained
  exposure control and live view are outside its scope — *confirmed* by the framework's documented
  surface.
- **Verdict:** strong candidate for the download/retrieval half of the bridge (`downloadPreview`,
  `downloadOriginal`), and it is a first-party Apple framework with no licensing burden. Not
  sufficient alone for control.

### 3. USB Video Class (UVC) streaming

- **What it gives:** the A7C II supports USB streaming, presenting itself as a standard webcam over
  USB-C without vendor software — *likely*, per Sony's product documentation for recent Alpha bodies;
  **requires hardware verification** for exact resolutions and frame rates.
- **Where it runs:** macOS trivially (`AVCaptureDevice` sees it). On iPad, `AVCaptureDevice.DeviceType.external`
  (iOS/iPadOS 17+) exposes UVC devices. **Whether an iPhone exposes a UVC camera this way is
  unverified and must be tested on device.**
- **What it does not give:** any control. It is a video stream only.
- **Open question — important:** whether USB streaming and PC Remote control can operate
  simultaneously over the same USB connection, or whether the body's USB mode is exclusive.
  **Requires hardware verification.** If they can coexist, a UVC live view + separate control channel
  is markedly simpler than SDK live view.
- **Verdict:** potentially the cheapest live-view path, and if iPhone supports it, potentially removes
  the Mac from the live-view path entirely. Worth testing early because it would change the
  architecture.

### 4. libgphoto2 (PTP, independent open source)

- **What it gives:** broad multi-vendor PTP support including many Sony bodies, with capability
  varying by model. Fully open source.
- **Where it runs:** macOS, Linux. Not iOS.
- **License:** LGPL-2.1 — dynamic linking is fine; see [licensing.md](licensing.md) for the
  clean-room concern about mixing this with SDK work.
- **Status for A7C II:** coverage and control fidelity **require verification** against the current
  release. libusb is a dependency and is already commonly available.
- **Verdict:** the open-source fallback. Lower fidelity than CrSDK, dramatically better licensing.
  Keeping this path viable is what prevents the project from being hostage to a proprietary SDK.

### 5. Sony PC Remote over Wi-Fi

- **What it gives:** the A7C II supports PC Remote over both USB and Wi-Fi — *likely*, per Sony's
  Help Guide for the body. Reachable through CrSDK's Ethernet/IP transport.
- **Caveats:** pairing, latency, and reliability all **require hardware verification**. Wi-Fi live
  view is generally lower framerate and higher latency than USB.
- **Verdict:** convenience option, not the development baseline. Develop on USB.

### 6. Legacy Sony Camera Remote API (HTTP/JSON-RPC)

- The older SSDP-discovered HTTP API used by earlier bodies and the QX series. **Unsupported** on the
  A7C II. Listed here only so nobody rediscovers it and assumes it applies — it is a common source of
  outdated advice online.

## Recommended architecture given the above

```
iPhone app
   │  camera bridge protocol (our own, vendor-neutral)
   ▼
macOS bridge ── CrSDK (control + live view)      [licensing-restricted]
             ├─ ImageCaptureCore (retrieval)      [first-party, clean]
             └─ libgphoto2 (open fallback)        [LGPL]
                        │
                     Camera
```

The bridge protocol is **ours** and vendor-neutral. Everything vendor-specific stays on the Mac side
of it. That is what lets the iPhone code be identical whether the camera is a Sony, a Canon, or a
mock — and what lets the whole bridge be replaced if iPhone UVC support turns out to work.

Bridge transport recommendation: HTTP over a Bonjour-discovered local network connection, with MJPEG
for live view initially. It is debuggable with `curl`, needs no extra dependencies, and can be
replaced with something lower-latency if measurement shows it is the bottleneck. On iOS this requires
`NSLocalNetworkUsageDescription` and `NSBonjourServices` in `Info.plist`.

## Pitfalls

- Assuming a desktop SDK capability transfers to iOS. It does not; that is the whole reason the
  bridge exists.
- Treating "the camera is connected" as one boolean. USB connected, PC Remote enabled, and control
  accepted in the current body mode are three different things.
- Trusting forum claims about which PTP opcodes work. Label as empirical/unverified and test.
- Statically linking LGPL libraries without meeting the relinking requirement.
- Building the bridge protocol around CrSDK's data model. It must be shaped by our
  `CameraCapabilities`, or swapping the backing transport becomes a rewrite.

## Official sources

- Sony Camera Remote SDK: https://support.d-imaging.sony.co.jp/app/sdk/en/index.html
- Sony Camera Remote Toolkit: https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html
- Apple ImageCaptureCore: https://developer.apple.com/documentation/imagecapturecore
- `AVCaptureDevice.DeviceType.external`: https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype/external
- libgphoto2: http://www.gphoto.org/
- PTP is standardized as ISO 15740 / PIMA 15740; vendor extensions are not covered by the standard.

## Open questions

1. Does an **iPhone** on iOS 18 expose a USB-C UVC camera via `AVCaptureDevice.DeviceType.external`?
   Highest-leverage unknown in this document.
2. Can the A7C II do **USB streaming and PC Remote control simultaneously**?
3. Current libgphoto2 control coverage for ILCE-7CM2.
4. CrSDK live-view latency and frame rate over USB on Apple Silicon.
5. Whether CrSDK ships a native arm64 macOS build or requires Rosetta.
