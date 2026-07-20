# ScrollProbe

ScrollProbe is an experimental macOS menu bar app that prevents severe trackpad
scroll freezes in a specific nested UTM and VMware Horizon setup.

It was built for this confirmed path:

```text
Apple Silicon Mac
  -> UTM macOS guest (Apple Virtualization.framework)
    -> VPN
      -> VMware Horizon Client
        -> Ubuntu or Windows VDI
```

One physical trackpad gesture can become tens of thousands of zero-delta
`scrollPhase=changed` events inside the macOS guest. Horizon then becomes
unresponsive for seconds, and the VDI connection can degrade or reconnect.
ScrollProbe removes only that pathological event class before it reaches
Horizon.

> [!WARNING]
> ScrollProbe is an experimental workaround for a reproduced virtualization
> bug, not a universal Horizon or scrolling fix. Read the compatibility and
> privacy sections before enabling it.

## What it does

Protection mode installs one active Core Graphics HID event tap and drops an
event only when all of the following are true:

- all integer, fixed-point, and point deltas on all three axes are zero;
- `scrollPhase` is `changed`;
- momentum phase is absent.

Events carrying real movement, momentum, or gesture lifecycle phases are passed
unchanged. ScrollProbe never synthesizes input and does not rewrite scroll
distance or direction.

The filter reduced tested guest streams from tens of thousands of events to
normal tens or hundreds without freezes:

| UTM pointer | VDI target | Guest ingress | Dropped | Passed downstream |
|---|---|---:|---:|---:|
| Generic Mouse | Windows | 41,495 | 41,425 | 70 |
| Mac Trackpad | Windows | 17,184 | 17,118 | 66 |
| Mac Trackpad | Ubuntu stress run | 40,615 | 40,137 | 472 |
| Mac Trackpad | Windows stress run | 35,250 | 34,311 | 932 |

## Compatibility

Confirmed configuration:

- Apple Silicon host;
- host and UTM guest running macOS 15.7.7;
- UTM 4.7.5 using Apple Virtualization.framework;
- VMware Horizon Client 2312.1 (`8.12.1`) inside the guest;
- Ubuntu 20.04.6 and Windows Server 2019 VDI targets;
- both UTM `Mac Trackpad` and `Generic Mouse` pointer modes.

The app has not yet been independently tested with other macOS, UTM, or Horizon
versions. Bluetooth mouse scrolling is expected to remain unaffected, but the
formal control matrix is not complete.

## Install a release

Public release archives will be attached to the
[GitHub Releases](https://github.com/webmalex/scrollprobe/releases) page.

1. Download `ScrollProbe-<version>-macos-arm64.zip` and extract it.
2. Move `ScrollProbe.app` to `/Applications` or `~/Applications`.
3. Open the app and choose `Enable Protection`.
4. Grant ScrollProbe access in **System Settings > Privacy & Security >
   Accessibility**.
5. Confirm that the menu bar shield reports `Protection: Active`.
6. Optionally enable `Launch at Login` from the menu.

The app does not require a separate Input Monitoring permission.

### Migrating from pre-public builds

Version `0.6.0` adopts the final public bundle identifier
`io.github.webmalex.ScrollProbe`. If you used build 9 or earlier:

1. In the old ScrollProbe menu, disable `Launch at Login`.
2. Quit the old app.
3. Remove the old ScrollProbe entry from Accessibility settings.
4. Replace the app and launch the new build.
5. Grant Accessibility and enable `Launch at Login` again.

This is a one-time migration. Future builds will keep the public identifier.

## Using Protection

The menu bar shield shows the actual service state, filtered/passed counters,
tap uptime, generation, and recovery counts. Counters refresh once per second
only while the menu is open.

`Copy Status` creates a clipboard report suitable for an issue. It contains
version, OS, permission state, aggregate counters, and lifecycle information;
it does not contain a hostname, user paths, or input contents.

Protection runs without a window, network access, telemetry, or diagnostic log.
If macOS disables its event tap, ScrollProbe attempts bounded recovery and
reports `Failed` rather than retrying forever.

## Diagnostics

`Open Diagnostics...` exposes the research tools used to validate the filter:

- paired ingress/downstream monitoring;
- targeted zero-delta filtering;
- a time-limited experimental drop-all mode;
- event-tap inventory and JSONL metrics.

Diagnostics are opt-in and separate from background Protection. Diagnostic logs
can contain a hostname, process identifiers, executable paths, and detailed
scroll timing/delta metadata. Review and redact them before sharing. See
[PRIVACY.md](PRIVACY.md) for the complete data behavior.

The investigation history, measurements, hypotheses, and remaining lifecycle
tests are maintained in [PLAN.md](PLAN.md).

## Build from source

Requirements: macOS 15+, Apple Silicon, Xcode with its license accepted, and
Swift 6.

```sh
make test
make app
make package
```

The local development build is ad-hoc signed. Output:

```text
dist/ScrollProbe.app
dist/ScrollProbe-0.6.0-macos-arm64.zip
```

Install repository hooks with `make hooks` and run all checks with `make lint`.
See [CONTRIBUTING.md](CONTRIBUTING.md) for commit conventions.

## Maintainer release build

A public binary must use a Developer ID Application certificate, Hardened
Runtime, a secure timestamp, and Apple notarization. Store notarization
credentials in Keychain, then run:

```sh
make test lint
make release-package \
  SIGN_IDENTITY="Developer ID Application: Example Name (TEAMID)" \
  NOTARY_PROFILE="scrollprobe-notary"
```

The target signs the app, submits a temporary ZIP to the Apple notary service,
staples and validates the ticket, checks Gatekeeper acceptance, creates the
final ZIP, and prints its SHA-256 checksum. Credentials and private keys are
never stored in the repository.

## Uninstall

1. Disable `Launch at Login` in the ScrollProbe menu.
2. Choose `Quit ScrollProbe`.
3. Move `ScrollProbe.app` to Trash.
4. Remove ScrollProbe from Accessibility settings.
5. Optionally remove its preference domain, cache directory, and diagnostic
   logs:

```sh
defaults delete io.github.webmalex.ScrollProbe
rm -r "$HOME/Library/Caches/io.github.webmalex.ScrollProbe"
rm -r "$HOME/Library/Logs/ScrollProbe"
```

The last command deletes only explicitly created Diagnostics logs. Protection
mode does not create them.

## License

ScrollProbe is available under the [MIT License](LICENSE).
