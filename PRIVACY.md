# Privacy

ScrollProbe is designed to solve a local input-event amplification problem
without collecting user data.

## Protection mode

Background Protection:

- does not use the network;
- does not include telemetry, analytics, or crash reporting;
- does not write input events or diagnostic logs;
- does not record keystrokes, pointer positions, window contents, or remote
  desktop contents;
- keeps only aggregate scroll-event and lifecycle counters in memory.

The app stores the user's explicit Protection and Launch at Login choices using
macOS system services. It also creates an empty process-lock file under
`~/Library/Caches/io.github.webmalex.ScrollProbe` to prevent two copies from
installing competing event taps.

`Copy Status` writes a report to the clipboard only when selected. The report
contains the app and macOS versions, permission and login-item states, aggregate
counters, tap uptime/recovery information, and the last internal error. It does
not contain the hostname, user paths, event deltas, or input contents.

## Diagnostics mode

Diagnostics run only after an explicit user action and write JSONL files to the
selected local directory. Depending on the chosen experiment, these files can
contain:

- hostname, OS version, app version, process ID, and scenario labels;
- scroll timing, delta, phase, momentum, and source/target process ID metrics;
- event-tap inventory including process names and executable paths;
- local error and lifecycle messages.

ScrollProbe does not upload these files. They remain on the Mac until the user
moves or deletes them. Diagnostic logs may reveal usernames through executable
paths and may identify security, VPN, or remote-desktop software. Review and
redact every diagnostic file before sharing it publicly.

The default diagnostic log directory is:

```text
~/Library/Logs/ScrollProbe
```

## Accessibility permission

Protection requires Accessibility permission because it uses a Core Graphics
HID event tap to inspect scroll-wheel events and remove the narrowly defined
pathological events. The same permission allows Diagnostics to observe scroll
events and inspect registered event taps.

ScrollProbe does not use Accessibility to read UI text, control other apps, or
capture keyboard events.
