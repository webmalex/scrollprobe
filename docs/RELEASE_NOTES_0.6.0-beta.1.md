ScrollProbe is an experimental macOS menu bar workaround for severe trackpad
scroll freezes in VMware Horizon running inside a UTM macOS guest.

One physical gesture in the reproduced setup can be amplified into tens of
thousands of zero-delta `scrollPhase=changed` events. ScrollProbe drops only
that event class while preserving real movement, momentum, and gesture
lifecycle events.

Tested topology:

- Apple Silicon host and guest running macOS 15.7.7
- UTM 4.7.5 with Apple Virtualization.framework
- VMware Horizon Client 2312.1 (`8.12.1`)
- Ubuntu 20.04.6 and Windows Server 2019 VDI targets
- UTM Mac Trackpad and Generic Mouse pointer modes

Highlights:

- background menu bar Protection without input logging or network access
- opt-in Launch at Login
- bounded event-tap recovery and lifecycle counters
- privacy-safe Copy Status report
- opt-in advanced Diagnostics for reproducible measurements

This is a beta for a specific reproduced virtualization path, not a universal
Horizon fix. Other macOS, UTM, and Horizon versions need independent testing.

This beta is ad-hoc signed and is not Apple-notarized. macOS requires explicit
approval through **System Settings > Privacy & Security > Open Anyway** on first
launch. Do not disable Gatekeeper or remove quarantine attributes.

Installation, Accessibility rationale, privacy behavior, known limitations, and
source-build instructions are documented in the repository README.

Download both the ZIP and its `.sha256` asset, then verify them:

```sh
shasum -a 256 -c ScrollProbe-0.6.0-macos-arm64.zip.sha256
gh attestation verify ScrollProbe-0.6.0-macos-arm64.zip \
  --repo webmalex/scrollprobe \
  --signer-workflow webmalex/scrollprobe/.github/workflows/ci.yml \
  --deny-self-hosted-runners
```
