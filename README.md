# Claude Usage — macOS widget

Unofficial, community-built. Not affiliated with or endorsed by Anthropic.

Native WidgetKit desktop/Notification Center widget showing Claude Code's
**session (5-hour) limit**, **weekly limit(s)**, and **tokens per model over the
last 7 days**, plus a menu-bar item with the same numbers.

<p align="center">
  <img src="docs/widget-small.png" width="194" alt="Small widget: session and weekly bars">
  <img src="docs/widget-medium.png" width="388" alt="Medium widget: limits plus per-model tokens">
</p>
<p align="center">
  <img src="docs/widget-large.png" width="388" alt="Large widget: limits and per-model detail">
</p>

## How it works

- `ClaudeUsage` (menu-bar app, unsandboxed): every 2 minutes reads Claude Code's
  OAuth token from the keychain (`security find-generic-password -s "Claude Code-credentials"`),
  calls the same usage endpoint `/usage` uses, sums per-model tokens from
  `~/.claude/projects/**/*.jsonl` (deduped by message id + request id — streamed
  chunks repeat the usage block), writes `usage.json` to the App Group container and
  asks WidgetKit to reload when anything changed.
- `ClaudeUsageWidget` (sandboxed extension): renders that snapshot in small,
  medium and large sizes. Widget extensions can't shell out or read `~/.claude`,
  which is why the app does the collecting — keep it running (there's a
  "Launch at Login" toggle in the menu).

Per-model **rate limits** are only shown if the API reports them (Max plans);
on Pro there is one all-models weekly limit, so the per-model section is a token
breakdown from local transcripts.

## Privacy & security

Read this before running it — the app touches two sensitive things on your Mac.

- **Your Claude Code login token.** The menu-bar app reads the OAuth access token
  Claude Code stores in the login keychain (item `Claude Code-credentials`) by
  running `/usr/bin/security find-generic-password`. macOS may ask you to allow
  this once. The token is held in memory only and sent to exactly one place,
  `https://api.anthropic.com/api/oauth/usage`, over HTTPS. It is never written
  to disk, logged, or included in the widget snapshot. The app never refreshes
  or modifies the token.
- **Your transcripts.** Per-model token counts are computed by scanning
  `~/.claude/projects/**/*.jsonl` locally. Only the `model` name and `usage`
  numbers of assistant messages are read; message content is never parsed or
  stored. Nothing from the transcripts leaves the machine.
- **What is stored.** A small JSON file with percentages, reset times, plan name,
  model names and token counts, at
  `~/Library/Containers/<bundle id>.widget/Data/Library/Application Support/ClaudeUsage/usage.json`.
- **Sandboxing and signing.** The widget extension is sandboxed with no network
  access. The menu-bar app is *not* sandboxed (it can't read the keychain item
  or `~/.claude` otherwise), runs with the hardened runtime, and carries no
  entitlements. Builds are ad-hoc signed and not notarized, so build it from
  source yourself rather than trusting a binary — Gatekeeper will (rightly)
  refuse a downloaded copy.
- **No dependencies.** System frameworks only; nothing is fetched at build time.
- **Unofficial endpoint.** The usage endpoint is the one Claude Code's `/usage`
  command calls, not a documented public API. It may change or stop working, and
  using your subscription token outside Anthropic's own tools is your call —
  check Anthropic's usage policies if that matters to you. This app only reads
  usage; it never performs inference with the token.

## Build

```sh
sudo xcodebuild -license accept   # once, if you haven't
./build.sh                        # builds Release, installs ~/Applications/ClaudeUsage.app, launches it
```

Then right-click the desktop (or open Notification Center) → **Edit Widgets** →
**Claude Code Usage**. The app must have been launched at least once for macOS
to register the widget.

Or open `ClaudeUsage.xcodeproj` in Xcode and run the `ClaudeUsage` scheme.
The project is signed "to run locally" (ad-hoc); pick your team under
Signing & Capabilities if you'd rather.

`tools/render-screenshots/render.sh` regenerates the images in `docs/` from the
widget's real SwiftUI views and your current snapshot.

Forking: change `bundleIdPrefix` / `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`
(the widget's id must stay the app's id + `.widget`).

`project.yml` is the source of truth for the Xcode project ([XcodeGen](https://github.com/yonaskolb/XcodeGen));
the generated `ClaudeUsage.xcodeproj` is committed so you don't need XcodeGen installed.

## License

MIT — see [LICENSE](LICENSE).
