# Neon Pup

A menu bar app for Macs in China. It sends all of your Mac's internet through your own servers outside China, so Google, Instagram, WhatsApp and Claude work, and it keeps Claude on the same server every time so your account doesn't see a China connection.

Download the signed and notarized app at **https://neonpup.bysa.app**.

## What you need

- A Mac with macOS 13 or newer (Apple silicon or Intel).
- [SFM](https://sing-box.sagernet.org/clients/apple/), the free macOS app of sing-box. Neon Pup's setup wizard
  downloads and installs the tested version for you.
- Your own servers. Neon Pup comes without any. You add them as share links that start with `vless://` (VLESS Reality or VLESS over WebSocket) or `hy2://` / `hysteria2://` (Hysteria2). Whoever runs your servers gives you these links, and apps like Shadowrocket and Clash Verge can export them.

The full user guide is in [docs/GUIDE.md](docs/GUIDE.md). The app shows the same guide under Help.
Developers: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the design and its decisions,
[docs/DEVELOPING.md](docs/DEVELOPING.md) covers building, testing and releasing.

## How it works

- The tunnel runs in **SFM**, sing-box's own NetworkExtension app. macOS then sends every app and every DNS lookup
  through it. Neon Pup builds the sing-box config, hands it to SFM over a local address, starts and stops SFM's
  tunnel, and steers the engine (servers, modes, health checks) through its local control API. Users only see
  Neon Pup; a first-run wizard walks them through installing and approving SFM.
- Claude's domains (claude.ai, claude.com, anthropic.com, claudeusercontent.com, clau.de) stay on the server Claude
  is using while it works, and otherwise take the first working server in your list. Their DNS goes the same way.
- China mode reconnects by itself when the tunnel drops, and "Go offline" turns Wi-Fi off.
- A small helper runs as root to install the tested SFM version (checked by hash, signature and notarization),
  to end the hotel login window even if the app crashes, and to swap a China, Hong Kong or Macau time zone to
  Singapore while connected. It only accepts requests from Neon Pup signed by the same Apple team.
- Server links are stored in the macOS Keychain, and SFM keeps its own copy to run them. Nothing about your servers
  is bundled with the app.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details and the open questions.

## Build it yourself

You need Xcode's command line tools (Swift 5.9 or newer) and, to run the helper, an Apple Developer ID.

```sh
swift test                      # unit tests
tools/build.sh                  # builds and signs build/Neon Pup.app
```

The helper only talks to an app signed by the team in `HelperConstants.teamID` (`Sources/NeonPupCore/HelperProtocol.swift`). To run your own build:

1. Change `teamID` to your Apple team id.
2. Run `IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/build.sh`.

`tools/release.sh` notarizes and zips the app; edit its `IDENTITY` and notary profile first.

## Licence

Neon Pup is MIT licensed (see [LICENSE](LICENSE)). The released app bundles sing-box (GPL-3.0) for its legacy engine; its source code is at https://github.com/SagerNet/sing-box (version 1.13.7). SFM is a separate app by the sing-box developers, licensed GPL-3.0, downloaded from their official release page during setup. The China rule sets come from [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip) and [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite).

Check the rules where you use it. Neon Pup comes with no warranty.
