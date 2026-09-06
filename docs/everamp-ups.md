# Thelio UPS operations and recovery

Status: 2026-09-05. EverAmp 1500VA/1000W LiFePO4, USB monitoring.
**Initial deployment is observation-only. Automatic host shutdown is NOT armed.**

Activated successfully at 2026-09-05T10:28:22-04:00 without a reboot. Live NUT
reads OL/100%; status refreshes each polling cycle, TCP is loopback-only, and
no system units are failed. Startup initially preceded driver readiness by two
seconds, producing a communication-lost/restored pair. Logs confirmed Herdr
notices, mail acceptance, and durable project notes; human receipt of each
channel is not assumed. This was not a physical outage test.

## Why we do not switch the UPS off

The external storage enclosure's per-drive soft switches and its separate
USB-powered cooling fan do not remember their on-state after power loss.
Both stay on battery-backed outlets. A conventional NUT shutdown that finally
turns the UPS output off would strand the machine even after utility restoration.

Our controller requests only an orderly operating-system poweroff. It does not
send UPS `shutdown.return`, `load.off`, FSD, or `upsdrvctl -k`. NUT's upsmon
service and POWERDOWNFLAG are disabled; the UPS shutdown order is -1.

## Observe

```sh
ups-status
ups-status --json
ups-status --toml
ups-status --xml
ups-status --bash
ups-status --bash --export
systemctl status upsd upsdrv everamp-monitor.timer
journalctl -u upsdrv -u everamp-monitor --since today
journalctl --unit='everamp-notice@*' --since today
```

`ups-status` prints one sorted, pretty-printed JSON document with `nut` and
`monitor` namespaces and an `errors` array. NUT dotted keys become nested objects:
`battery.charge` becomes `.nut.battery.charge`. NUT values remain strings to
preserve identifiers, leading zeroes, and decimal precision; monitor JSON retains
its native types, including `.monitor.shutdown_enabled` as a Boolean. When a
key has both a scalar and children (e.g. `driver.version`), `_value` holds the
scalar alongside the children. `_value` is reserved by this representation.

Unavailable or malformed sources produce `null` in their namespace, structured
errors, and a nonzero command exit status, while preserving the other source.
Live NUT reads and the monitor's timestamped last observation are not an atomic
snapshot. Local unprivileged status queries need no sudo. The NUT
server listens only on 127.0.0.1:3493; no remote UPS command account is installed.

JSON is the default. TOML uses nested tables and omits null-valued fields;
`errors` explains unavailable sources. `key=` is not legal TOML. XML includes
type attributes to distinguish text, numbers, Booleans, arrays, and nulls.

For Bash, the command emits only shell-quoted `NAME=value` assignments using a
`UPS_STATUS_` namespace; e.g. `.nut.ups.status` becomes
`UPS_STATUS_NUT_UPS_STATUS`. Array members use numeric path components and
arrays include a `_LENGTH` variable, such as `UPS_STATUS_ERRORS_LENGTH`.
Names are capitalized and punctuation becomes underscores. Ambiguous normalized
names or NUL-containing values are rejected rather than silently corrupted.
There is no preamble, cleanup loop, or implicit export. `--bash --export` adds
`export ` to each assignment when child processes should inherit the values.
As usual in Bash, assigning an already-exported variable retains its export
attribute. Flags may appear in either order; `--export` requires Bash output.

Each assignment occupies one physical line; control characters use Bash ANSI-C
quoting. Values must be shell-decoded, not treated as raw `env` output, since
spaces, quotes and command substitutions must remain literal data when evaluated.
Nulls produce no assignment. Evaluating the output leaves all unmentioned
variables untouched, including readings from an earlier snapshot. Use a fresh
shell/subshell or explicitly manage that namespace when stale values matter.

```bash
if ups_env=$(ups-status --bash); then
  eval "$ups_env"
  printf 'UPS state: %s\n' "$UPS_STATUS_NUT_UPS_STATUS"
else
  printf 'UPS status unavailable; do not use earlier readings\n' >&2
fi
```

Do not rely on `eval "$(ups-status --bash)"` to propagate query failures:
`eval`'s success can mask the command substitution's failure. Capture and check
the command as above before consuming the snapshot. Quoting tests evaluate
metacharacters as literal values, never commands. Bash output requires Bash,
not a generic POSIX shell.

USB matching uses VID/PID 06da:ffff and manufacturer/product strings
`-BMS-` / `Smart-Battery`, never a USB bus/port. There is currently one matching
UPS. If another identical unit is added, disambiguate using its serial identity.

Initial raw HID inspection showed AC present, battery present, 100% charge;
UPower nevertheless showed `present: no`. The firmware also has inconsistent
voltage/runtime metadata. Do not infer a safe ten-minute runtime from its estimate.
The complete S5 wake path and actual mains-loss/restoration reporting remain
unverified until an attended test.

## Outage policy

| Confirmed outage duration | Action |
|---|---|
| First on-battery observation | Warn Peter and the fleet; start countdown |
| 300 seconds | Warn to checkpoint and stop builds; five minutes remain |
| 600 seconds | Warn and, only when armed, request orderly host poweroff |
| Confirmed utility restoration | Cancel the countdown |

Polling occurs every five seconds after the preceding invocation finishes.
Deadlines are relative to detection, so reporting/processing adds latency.
Poweroff initiation is not a guarantee that every service has stopped at precisely
ten minutes. Measure real battery endurance under load before choosing that deadline;
there is not yet an independently validated early low-battery override.

The pure LuaJIT policy takes injected monotonic seconds and boot identity. The
runtime uses /proc/uptime, persists state only on meaningful changes under
/var/lib/everamp-monitor, and writes fresh status to /run/everamp-monitor.
Service restarts retain an outage deadline; a new boot discards the old monotonic
timeline. USB loss alone is **not** treated as an outage. If an outage was already
confirmed, losing USB does not silently cancel it: the deadline continues. That
can cause a conservative shutdown if mains returns while telemetry is unavailable.
Restored telemetry showing online cancels it.

Warnings go to the journal, Peter-owned terminal PTYs (output, never typed input),
GNOME, Herdr, mail to `peter` and `einstein`, and durable inbox notes for live Herdr
project roots. Delivery is best-effort; hooks may not wake idle agents. Nothing
promises that an agent saved its context merely because a notice was written.
The event outbox retries failed local enqueue operations. Notification transports
have timeouts and must not block an armed shutdown. Queued final notices may be
cut short by shutdown; earlier warnings are the time to checkpoint.

## Attended commissioning, then arming

1. Confirm the physical outlets keep the enclosure **and fan** battery-backed.
2. Keep observation mode on. Have Peter present with local access and saved work.
3. Disconnect only the UPS's **upstream mains**, not its outputs or USB. Observe
   `ups-status` changing OL to OB and the first warning. Restore mains promptly;
   verify OL and countdown cancellation. Do not start with a ten-minute drain.
4. Repeat with sufficient battery and controlled load to verify the five-minute
   warning and ten-minute shadow event; restore mains before low charge. Check
   battery endurance independently. Avoid games and large builds for this test.
5. Commission a separate wake helper (below), snapshot agent sessions, then perform
   an attended host-only shutdown and Wake-on-LAN test while leaving UPS output on.
6. To arm, set `services.everamp-monitor.shutdownEnabled = true;` in the Thelio
   config. Deliberately update the observation-default assertion in
   `tests/ups_config_test.sh` only after documenting the successful physical tests.
   Build, inspect `dry-activate`, and apply the canonical flake with
   `SWITCH_NOW=1 ixnay reify --no-update`. No reboot is required to change the policy.

For emergency suspension of the controller (not UPS output):

```sh
sudo systemctl stop everamp-monitor.timer everamp-monitor.service
```

This removes automatic protection until restarted. It cannot retract a shutdown
already accepted by systemd. Restore the timer after resolving the problem.

## Restart after mains restoration: still needs an external observer

BIOS "power on after AC loss" cannot detect restored wall power when the UPS
never stopped supplying AC. The powered-off host cannot observe USB or send its
own wake packet. Whole-UPS cycling is incompatible with the enclosure/fan.

Preferred option: another independently powered LAN device observes mains
restoration and sends Wake-on-LAN. Thelio's wired `enp68s0` adapter currently
reports magic-packet support and `Wake-on: g`. This establishes NIC configuration,
**not** proof of firmware/S5 behavior. A same-LAN helper is required; Tailscale on
the powered-off host is unavailable.

The Framework could be a suitable observer if it remains at home, powered on,
has battery endurance, observes its own charger connected to non-UPS mains, and
can reach the Thelio's LAN after restoration. Router/switch availability also
matters. A helper must remember an outage and retry wake after connectivity
returns; "host not pingable" is not evidence of restored utility power. It must
also handle restoration just before the Thelio finishes shutting down. A sustained
online grace interval and bounded retries can close that race. Do not wake the
host repeatedly while mains is absent.

Alternative: a separately controllable outlet for **only the host**, plus a
controller that sees mains restoration and deliberately cycles that outlet.
Do not put the enclosure/fan on that switched outlet. Requires actual hardware
and an attended test. RTC periodic wake is a less attractive fallback: firmware
support varies and booting repeatedly on battery consumes the reserve.

The UPS descriptor exposed global startup/shutdown delay fields, but that is not
proof of independently switchable outlet groups. No outlet-specific paths were
observed. Do not assume vendor software controls imply safe per-outlet control.

Live `upscmd -l everamp@127.0.0.1` at 2026-09-05T10:28:37-04:00 listed
load.off/on (immediate/delayed), shutdown.return/stayoff/stop/default, and driver
reload/killpower commands. Listing is read-only. **None were executed.**
`driver.flag.allow_killpower` reads 0, and no authenticated command user is
configured. Advertised command support is not proof of correct firmware behavior.

## Tests and references

Run `bash tests/ups_policy_test.sh`, `bash tests/ups_config_test.sh`, or `bash test`.
Policy tests use injected times; runtime tests replace file/process boundaries
so they cannot accidentally power off the host. These are regression/contract
checks, not substitutes for independent physical commissioning.

- [EverAmp official manual page](https://everamppower.com/pages/product-manual)
- [NUT usbhid-ups documentation](https://networkupstools.org/docs/man/usbhid-ups.html)
- [NUT FAQ: shutdown and power-return races](https://networkupstools.org/docs/FAQ.html)
- [Related -BMS- firmware telemetry report](https://github.com/networkupstools/nut/issues/3501)
- [Upstream related hardware support changes](https://github.com/networkupstools/nut/pull/3502)

Hardware observations are timestamped, not immutable promises; keep the private
Obsidian hardware inventory updated when wiring, firmware, or devices change.
