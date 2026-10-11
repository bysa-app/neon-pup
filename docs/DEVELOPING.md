# Developing Neon Pup

How to build, test and release Neon Pup. Read [ARCHITECTURE.md](ARCHITECTURE.md) first.

## Requirements

- macOS 13 or newer, Xcode's command line tools (Swift 5.9 or newer).
- An Apple Developer ID to sign builds that run the helper. Without one you can still run the tests.
- SFM, installed through the app's setup wizard or with `brew install --cask sfm` (the wizard pins version
  `SFMStatus.pinnedVersion`).

## Layout

| Folder | What's in it |
|---|---|
| `Sources/NeonPupCore` | Pure logic, no UI: config builder, share-link parser, server policy, state machine, SFM status parsers, kill switch rules, diagnostics. Most tests live here. |
| `Sources/NeonPupKit` | The app: `AppModel`, SwiftUI views, the setup wizard, `SFMHost`/`SFMBridge`/`ProfileServer`, the helper client. |
| `Sources/NeonPupHelper` | The root helper (launchd daemon): SFM install, hotel expiry, time zone, and the legacy engine and pf kill switch. |
| `Sources/NeonPup` | The executable's entry point. |
| `Tests/` | XCTest suites. `Fakes.swift` has the fake helper and engine used by the app tests. |
| `tools/` | Build, release, drills and the public-copy export. |
| `web/` | The download page (a Cloudflare Worker serving the zip from R2). |
| `docs/` | This page, ARCHITECTURE.md, and GUIDE.md (generated from `HelpGuide.swift`). |

## Build and test

```sh
swift test                       # all unit tests, about 2 seconds
tools/build.sh                   # signs build/Neon Pup.app with the Developer ID in IDENTITY
```

- To build your own copy, set `IDENTITY="Developer ID Application: Your Name (TEAMID)"` and change
  `HelperConstants.teamID` in `Sources/NeonPupCore/HelperProtocol.swift` to your team id. The helper only accepts
  an app signed by that team.
- The build downloads sing-box (for the legacy engine) and the China rule sets into `build/cache`.
- Some tests check the built app's signature; they skip until `tools/build.sh` has run once.

## Look at the UI without clicking

```sh
"build/Neon Pup.app/Contents/MacOS/NeonPup" --render-gallery build/gallery
```

Renders every panel state, the server window, the help guide and every setup wizard page as PNGs. SwiftUI can't
render text fields, menus or spinners into images; those show as placeholders.

## The user guide

`Sources/NeonPupKit/HelpGuide.swift` is the source. `docs/GUIDE.md` must match it; a test fails otherwise.
Regenerate with:

```sh
NEONPUP_WRITE_GUIDE=1 swift test --filter HelpGuideTests
```

Tests also check that every status message the app can show is explained in the guide, that the example links
import, that the health check never touches a Claude page, and that the emergency command keeps its order.

Copy rules: plain words, no em dashes, no curly quotes. Write for someone with no context.

## Maintenance commands

The app binary has a maintenance mode (`--spike`), used by the drills:

| Command | Does |
|---|---|
| `--spike reinstall` | re-registers the helper (after replacing the app) |
| `--spike status` | the legacy engine's state |
| `--spike export-profile <file>` | writes the SFM profile Neon Pup would serve, plus the control port and secret |
| `--spike killswitch on/off/report` | the legacy pf block |
| `--spike tz-apply / tz-restore` | the time zone swap |

## Updating the pinned SFM version

1. `brew info --cask sfm --json=v2` gives the new version, URL and SHA-256.
2. Update `pinnedVersion`, `packageURL` and `packageSHA256` in `Sources/NeonPupCore/SFMStatus.swift`.
3. Export a profile (`--spike export-profile`) and start it in the new SFM. Watch for warning popups: SFM shows
   deprecation warnings as dialogs. `sing-box check` does not print them.
4. Run the live tests below on a real Mac before releasing.

## Live tests

Unit tests can't prove kernel or NetworkExtension behaviour. Before a release, on a real Mac:

- `tools/sfm-test.sh`: connect, exit country, Claude's server, system DNS through the tunnel, IPv6, the fingerprint.
- Sleep and wake, switch Wi-Fi to a phone hotspot, leave it overnight.
- Hotel window: open it, quit Neon Pup, check that the helper ends it after 5 minutes.
- `tools/emergency-drill.sh` and `tools/boot-seal-drill.sh` (need `sudo`).

## Release

```sh
tools/release.sh                 # build, notarize, staple, zip into build/Neon-Pup.zip
```

Needs the notary profile `neonpup-notary` in the login Keychain. Then upload the zip to the download page (see
`web/`) and update the public repository with `tools/export-public.sh` and `tools/scan-public.sh`. The scan must
report 0 hits, and its positive control must pass, before anything is pushed.

## Security rules

- Never commit credentials, including as test fixtures. Fixtures use made-up values and `192.0.2.x` addresses.
- Bump `HelperConstants.version` on every helper change: a running helper is replaced only when the version differs.
- User input reaches root only as validated `RoadSpec` fields. No user string becomes a config key.
- Never edit SFM's own data or click through SFM on the user's behalf.
