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
>
> Public beta archives are ad-hoc signed and are not Apple-notarized. GitHub
> Actions signs their build provenance instead. macOS therefore requires an
> explicit **Open Anyway** approval on first launch.

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

1. Download `ScrollProbe-<version>-macos-arm64.zip` and its `.sha256` file.
2. From the download directory, verify the archive checksum:

   ```sh
   shasum -a 256 -c ScrollProbe-0.6.0-macos-arm64.zip.sha256
   ```

3. Optionally verify that GitHub Actions built this exact archive:

   ```sh
   gh attestation verify ScrollProbe-0.6.0-macos-arm64.zip \
     --repo webmalex/scrollprobe \
     --signer-workflow webmalex/scrollprobe/.github/workflows/ci.yml \
     --deny-self-hosted-runners
   ```

4. Extract the ZIP and move `ScrollProbe.app` to `/Applications` or
   `~/Applications`.
5. Try to open the app. After macOS blocks the unnotarized beta, open **System
   Settings > Privacy & Security**, scroll to **Security**, and click **Open
   Anyway**. Authenticate, then confirm **Open**.
6. Choose `Enable Protection` and grant ScrollProbe access in **System Settings
   > Privacy & Security > Accessibility**.
7. Confirm that the menu bar shield reports `Protection: Active`.
8. Optionally enable `Launch at Login` from the menu.

Do not disable Gatekeeper or strip quarantine attributes. The app does not
require a separate Input Monitoring permission. A managed Mac may prohibit
unnotarized applications entirely; building from source remains the fallback.

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
dist/ScrollProbe-0.6.0-macos-arm64.zip.sha256
```

Install repository hooks with `make hooks` and run all checks with `make lint`.
See [CONTRIBUTING.md](CONTRIBUTING.md) for commit conventions.

## Attested beta builds

Every push to `master` is built on GitHub's hosted macOS runner. The workflow
creates an ad-hoc signed ZIP and checksum, then issues a Sigstore-backed GitHub
artifact attestation for the ZIP. Release assets are copied from that completed
workflow rather than rebuilt locally. See [docs/RELEASING.md](docs/RELEASING.md)
for the exact maintainer procedure.

This provenance proves which repository workflow produced the archive; it is
not a substitute for Apple notarization. Developer ID distribution can be
added later if access to the Apple service becomes available.

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
