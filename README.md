# LinkRouter

A tiny macOS app that becomes your default browser and sends each link to the browser you choose, based on **which app the link came from** and/or **its domain**.

Examples: links from Slack open in Vivaldi, `github.com` always opens in Chrome, everything else goes to Safari.

## Install

**Download:** grab `LinkRouter.zip` from the [Releases](../../releases) page, unzip, and drag `LinkRouter.app` to `/Applications`.

The app is ad-hoc signed, not notarized, so macOS will warn on first launch. Right-click the app, choose **Open**, then **Open** again. Or run:

```bash
xattr -dr com.apple.quarantine /Applications/LinkRouter.app
```

Then open **System Settings → Desktop & Dock → Default web browser** and pick LinkRouter.

**Build from source** (needs Xcode command line tools):

```bash
./build.sh   # builds to ~/Applications/LinkRouter.app
```

## Use

Open LinkRouter to set a default browser and add rules. A rule can match the source app, a domain, or both; the first matching rule wins. Rules live in `~/.config/linkrouter/rules.json` and are re-read on every link, so edits apply immediately.

```json
{
  "fallback": "com.apple.Safari",
  "rules": [
    { "app": "com.tinyspeck.slackmacgap", "browser": "com.vivaldi.Vivaldi" },
    { "domain": "github.com", "browser": "com.google.Chrome" }
  ]
}
```

`app` and `browser` are macOS bundle identifiers.

## Requirements

macOS, Swift toolchain to build. No dependencies, no network access, no telemetry.

## License

MIT, see [LICENSE](LICENSE).
