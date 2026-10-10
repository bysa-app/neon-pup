# Neon Pup

A menu bar app for Macs in China. It sends all of your Mac's internet through your own servers outside China, so Google, Instagram, WhatsApp and Claude work, and it keeps Claude on the same server every time so your account doesn't see a China connection.

Download the signed and notarized app at **https://neonpup.bysa.app**.

## What you need

- A Mac with macOS 13 or newer (Apple silicon or Intel).
- Your own servers. Neon Pup comes without any. You add them as share links that start with `vless://` (VLESS Reality or VLESS over WebSocket) or `hy2://` / `hysteria2://` (Hysteria2). Whoever runs your servers gives you these links, and apps like Shadowrocket and Clash Verge can export them.

The full user guide is in [docs/GUIDE.md](docs/GUIDE.md). The app shows the same guide under Help.

## How it works

- The engine is [sing-box](https://github.com/SagerNet/sing-box) 1.13.7 in TUN mode. Every app's traffic goes through it, including the terminal.
- A small helper runs as root to start the engine and to change the firewall. It only accepts requests from Neon Pup signed by the same Apple team, copies the app into a root-only folder and checks its signature before running anything, and builds the engine config itself from validated server fields.
- If the connection drops, a pf firewall rule blocks the internet instead of letting apps fall back to the local connection. China mode keeps that block on whenever Neon Pup isn't connected, including after a crash or a restart.
- Claude's domains (claude.ai, claude.com, anthropic.com, claudeusercontent.com, clau.de) always use the first working server in your list, in every mode, and their DNS lookups go the same way.
- If the Mac's time zone is set to China, Hong Kong or Macau, Neon Pup switches it to Singapore (same clock time) while connected and switches it back afterwards.
- Server links are stored in the macOS Keychain. Nothing about your servers is bundled with the app.

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

Neon Pup is MIT licensed (see [LICENSE](LICENSE)). The released app bundles sing-box, which is licensed under GPL-3.0; its source code is at https://github.com/SagerNet/sing-box (version 1.13.7). The China rule sets come from [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip) and [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite).

Check the rules where you use it. Neon Pup comes with no warranty.
