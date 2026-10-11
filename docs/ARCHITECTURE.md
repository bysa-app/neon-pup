# How Neon Pup works

Neon Pup is a macOS menu bar app that sends a Mac's internet through the user's own servers outside China. It
keeps Claude (claude.ai, the Claude desktop app, Claude Code) on one server at a time, in the order the user
chose, so Claude never sees a China address while Neon Pup is connected.

This page is for developers. The user guide is [GUIDE.md](GUIDE.md).

## The two apps

Neon Pup runs on top of **SFM**, the standalone macOS app of [sing-box](https://github.com/SagerNet/sing-box),
made by sing-box's own developers.

| | Neon Pup | SFM |
|---|---|---|
| What the user sees | the butterfly, the panel, the setup wizard, the guide | nothing after setup |
| Owns | servers (Keychain), modes, Claude's server, China mode, hotel window, time zone, health checks | the tunnel (a NetworkExtension packet tunnel), system DNS while connected |
| Talks to the other through | a local profile address, `scutil --nc`, the engine's control API | fetches its profile from Neon Pup |

Why SFM: a plain TUN interface (what Neon Pup used before) cannot capture macOS's own DNS. macOS keeps sending
lookups to the LAN resolver, which leaks names to the local network and, in China, returns poisoned answers that
break blocked sites even through the tunnel. Apple's NetworkExtension routes system DNS into the tunnel and tears
everything down with the tunnel. SFM already is a signed, notarized NetworkExtension client for sing-box, so Neon
Pup uses it instead of shipping its own system extension. See "Decisions" below.

## Moving parts

```
 Neon Pup app (SwiftUI, user)                     Neon Pup helper (launchd daemon, root)
  AppModel ── state machine, Claude policy          SFMInstaller: pinned SFM package, checked
  SFMHost  ── start/stop via scutil --nc            HotelExpiry: ends the hotel window if the app dies
  ProfileServer ── 127.0.0.1:47322/<secret>.json    TimeZoneManager: China/HK/Macau zone -> Singapore
  EngineAPI ── 127.0.0.1:47321 (Clash API)                  ▲
       │                ▲                                   │ XPC, only from Neon Pup signed by team 43YSGDB8TC
       ▼                │ fetches profile
  SFM (NetworkExtension, io.nekohasekai.sfamt.system) runs sing-box 1.14.3 with Neon Pup's config
```

- **Profile.** `ConfigTemplate.build(roads:options:)` with `platform: .sfm` builds the whole sing-box config from
  the user's servers (`RoadSpec`, validated twice). `ProfileServer` serves it on 127.0.0.1 only, at a path with a
  32-hex-digit secret. SFM imports it once as a "remote profile" (`sing-box://import-remote-profile?url=...`) and
  re-fetches it on its own schedule (its window's refresh button, or its hourly auto-update while SFM runs).
- **Fingerprint.** The profile contains an unused outbound named `np-<12 hex>`, a SHA-256 over the server list
  (`ConfigTemplate.fingerprintTag`). After every check Neon Pup asks the engine whether that outbound exists. If
  not, SFM runs an older list and the panel says "Your server list changed. Press refresh in SFM" instead of
  Connected. This exists because Neon Pup cannot make SFM reload a profile.
- **Start and stop.** `SFMHost` finds SFM's VPN service by its provider id in `scutil --nc list` (never by its
  editable name) and runs `scutil --nc start/stop <id>`. This works only after SFM has started the tunnel once
  from its own window; SFM then saves its start options. The wizard's last step does that.
- **Control.** The profile turns on sing-box's Clash API on 127.0.0.1:47321 with a per-install secret. Neon Pup
  uses it exactly as it used its own engine before: delay tests per server, the `choice` and `claude` selectors,
  and the engine mode.
- **Modes.** Engine mode `Rule` sends China IPs and domains direct (and resolves China names with AliDNS); `Global`
  ("Send Chinese sites through my servers") turns those rules off; `Direct` is the hotel window, where everything
  except Claude goes out directly for at most 5 minutes. Claude's domain rules come before all of these.

## Claude's server

`RoadPolicy.selection` picks Claude's server: the server Claude is on keeps it while it answers, otherwise the
first answering server in the user's order. `AppModel` adds a one-miss grace (a single failed check does not move
Claude) and remembers Claude's server across restarts. Falling back from Singapore to the US happens
automatically (owner's decision). A failed selector switch never shows Connected.

## China mode

- Neon Pup reconnects SFM by itself when the tunnel drops (up to three times between good checks), in every mode.
- "Go offline" turns Wi-Fi off and leaves the tunnel running. Wake me up turns Wi-Fi back on into the running
  tunnel. Measured 2026-10-12: zero direct readings this way. The tunnel can't start without a network, so
  stopping it on Go offline meant Wi-Fi had to come back first and traffic went out directly for seconds.
- A relaunch while offline stays offline; turning China mode off while offline stops the tunnel first.
- Quitting Neon Pup leaves the tunnel running.
- SFM's `includeAllNetworks` setting (turned on during setup) keeps all traffic inside the tunnel while it runs.
- A China time zone is swapped for Singapore while connected. macOS puts the local zone back about 4 s after a
  network change (it locates the Mac from nearby Wi-Fi, even with "set automatically" written off), so Neon Pup
  re-applies the swap 5 and 10 s after a network change and on every check.

## Security model

- The helper accepts XPC only from Neon Pup signed by team `43YSGDB8TC` (`HelperConstants.clientRequirement`).
- `SFMInstaller` downloads only the pinned URL, checks its SHA-256, checks `pkgutil --check-signature` for SFM's
  Developer ID Installer team (`P8XK3KHB48`) and notarization, then runs `installer`. It never replaces an SFM the
  user already has.
- `SFMBridge.appTrusted()` checks SFM's code signature against its bundle id and team before Neon Pup opens it or
  hands it a link.
- The profile holds credentials. It is served on loopback only, behind a secret path; reports never include it.
  Server addresses, passwords and keys are redacted from reports, and any IP address in a report is masked.
- `HotelExpiry` in the helper only accepts a local port, a short secret and the modes `Rule` or `Global`.

## Decisions (and what was rejected)

| Decision | Why |
|---|---|
| Use SFM for the tunnel | Plain TUN can't capture system DNS; NetworkExtension can. Building our own system extension is weeks of work. |
| Host routes for LAN resolvers into the TUN | Rejected: link-local IPv6 resolvers can't be routed that way, renewals race, cleanup isn't guaranteed. |
| Rewrite macOS DNS in the dynamic store | Rejected: renewals race against the override; a crash leaves DNS pointing at a dead address. |
| Pre-fill SFM's database or click through SFM with Accessibility | Rejected: fragile and writes into another team's app data. The wizard shows each click instead. |
| Static profile per trip, fingerprint check | SFM has no "reload now" a third party can trigger. |

## Measured limits (live tests 2026-10-12)

What still lets traffic out directly, and why it stays:

1. Tunnel crash: about 1 to 2 s. `includeAllNetworks` blocks for about 6 s, then macOS drops the dead tunnel and
   lifts the block before anything can restart it. Neon Pup reconnects within about 10 s.
2. After a restart: Wi-Fi joins about 10 s after boot, before login, so macOS services go online directly until
   Neon Pup starts at login and (in China mode) turns Wi-Fi off within 2 to 3 s. Turning Wi-Fi off on
   `willPowerOffNotification` did not survive the restart (the notification arrives; the quit step never runs),
   so that was removed.
3. The first Wake me up after a restart or crash: 2 to 5 s, because the tunnel is down and can't start until Wi-Fi
   has joined. Neon Pup asks for the start every half second so it comes up as soon as it can.

Closing these needs a firewall rule that only lets traffic out toward the servers (the old engine's pf seal), which
is exactly what can lock a Mac out of the internet. Decision (the maintainer, 2026-10-12): live with them.

Still to measure: an overnight (deep) sleep, and the hotel login window at a real login page.

`tools/sfm-test.sh` runs the checks that don't need root; the drills in `tools/` need `sudo`.
