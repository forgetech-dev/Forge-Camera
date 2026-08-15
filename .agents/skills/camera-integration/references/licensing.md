# Vendor SDK Licensing — Analysis and Repository Rules

**Purpose.** AI Photographer is open source and intends to integrate cameras whose SDKs are not.
This file records what the licenses actually say and the rules that follow. It is engineering
guidance, not legal advice — for anything consequential, get a lawyer.

**Last verified:** 2026-08-15 against the Sony Camera Remote SDK license agreement.

---

## Sony Camera Remote SDK — what the license says

Source: https://support.d-imaging.sony.co.jp/app/sdk/licenseagreement_d/en-US.html

The clauses that constrain this project:

**Redistribution of the SDK is not permitted.** The grant allows installing and using the SDK to
develop applications, and allows incorporating *a binary form of the library file* into your
application "in an inseparable way" for distribution to end users. It does not allow redistributing
the SDK itself — not its headers, not its libraries, not as a convenience copy in a repository.

**Reverse engineering is prohibited.** The agreement states you "may not attempt to derive source
code, modify, reverse engineer, decompile, or disassemble any of the SOFTWARE."

**Sublicensing is restricted.** Application software must be distributed subject to end-user
restrictions consistent with the agreement.

**Bundled open-source components** inside the SDK carry their own separate licenses (Sony references
oss.sony.net for these). Those terms are not the SDK terms.

## Consequences for this repository

### Hard rules

1. **Never commit the Sony SDK** — no headers, no `.dylib`/`.a`, no sample code, no extracted
   constants tables, in any branch, ever. Once committed it is in the history.
2. **The repo ships the adapter, not the SDK.** `ForgeCameraSony` (or equivalent) contains our
   original code written against the SDK's published interface. Obtaining the SDK is the
   contributor's own act, under their own acceptance of Sony's terms.
3. **Acquisition is a documented manual step**, not an automated download that silently accepts a
   license on the user's behalf. A setup script may *check for* the SDK at a configured path and
   print instructions; it must not fetch and unpack it as if it were an ordinary dependency.
4. **Vendor integration is an optional build.** The default build, `make build`, and CI must not
   require the SDK. This is already required by the hardware-free development rule
   (`goal.md` §14) and licensing makes it non-negotiable.
5. **Never mirror vendor documentation.** Link to official sources and write original summaries. The
   reference files in this skill are the pattern: our words, their links.

### The "inseparable way" clause and open-source distribution

The permission to redistribute is scoped to a *binary* library incorporated into application software
*inseparably*. An open-source repository distributes source and expects users to build. These are not
the same act, and the clause was written for a different distribution model.

Practical reading: distributing our source (which contains no SDK) is unaffected. Distributing a
**built binary** of the app that statically incorporates the SDK is the case the clause contemplates,
and anyone shipping such a build — TestFlight, App Store, a release artifact — should confirm they
are within terms for their own distribution. Note this in release documentation rather than assuming
it.

### The reverse-engineering clause is the subtle one

An open-source alternative path exists: `libgphoto2` and similar projects implement vendor PTP
extensions independently. Using such a library is fine — it is a separate project under its own
license (LGPL-2.1 for libgphoto2, so dynamic linking, no static linking without complying with the
LGPL's relinking requirements).

The trap is **personnel, not code**. A contributor who has accepted the Sony SDK license is bound by
its anti-reverse-engineering clause. If that same contributor then works on an independent
reverse-engineered Sony protocol implementation, the provenance of that work becomes questionable —
the classic clean-room problem.

Project rules that follow:

- Do not mix the two efforts in one change. A PR touches the SDK-based adapter or the independent
  PTP path, never both.
- Do not describe SDK internals, undocumented constants, or observed SDK wire behavior in issues,
  commits, or comments.
- Anything learned from the SDK stays behind the SDK-based adapter. Anything in the independent path
  must come from public specifications, published vendor documentation, or existing open-source
  projects.

### Third-party license hygiene generally

| Library | License | Constraint |
|---|---|---|
| Sony Camera Remote SDK | Proprietary | No redistribution, no reverse engineering. Optional, user-obtained. |
| libgphoto2 | LGPL-2.1 | Dynamic linking is fine. Static linking requires LGPL relinking compliance. Attribution required. |
| libusb | LGPL-2.1 | Same shape as above. |
| Apple frameworks | Apple SDK terms | No issue; preferred for exactly this reason. |

Every third-party dependency added to this project records: what it solves, why the platform cannot,
its license, its compatibility with the project's license, and the cost of removal. See
`opensource-quality`.

### Trademarks

"Sony", "Alpha", "Viltrox", and camera model names are trademarks of their owners. Use them only to
describe compatibility — factual, nominative use. Do not use them in the project name, logo, bundle
identifier, or in any way implying endorsement or partnership.

## Open questions

- Whether Sony's terms permit distributing a **TestFlight or App Store build** that incorporates the
  SDK from an open-source project. Reading suggests yes under the binary-incorporation clause, but
  this should be confirmed before the first public build ships, not after.
- Whether Sony offers alternative terms for open-source projects. Worth asking their developer
  support directly; the answer would change the integration strategy.
- Licensing posture of the other vendors (Canon EDSDK, Nikon SDK, Fujifilm SDK) — each will need the
  same analysis before that adapter is written. Do not assume they match Sony's.

## Official sources

- Sony Camera Remote SDK license agreement: https://support.d-imaging.sony.co.jp/app/sdk/licenseagreement_d/en-US.html
- Sony Camera Remote SDK / Camera Remote Toolkit: https://support.d-imaging.sony.co.jp/app/sdk/en/index.html
- Sony open-source component notices: https://oss.sony.net/
- libgphoto2: http://www.gphoto.org/ · https://github.com/gphoto/libgphoto2
