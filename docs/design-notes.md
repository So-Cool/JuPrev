# Design notes

Why JuPrev is built the way it is. Recorded from a feasibility spike and the early
phases (2026-11-22, macOS 15.5, Xcode 16.4); the spike's code is in git history.

## Spike results

| Question | Answer |
|---|---|
| Does JavaScript run in a data-based (`QLPreviewReply` HTML) preview? | **Yes.** The inline probe script ran in both `qlmanage -p` and Finder. |
| JavaScriptCore render speed | Context + 564 KB bundle load: 22–32 ms. Typical notebooks: 6–16 ms. 10 MB: 122 ms. 25 MB: ~400 ms. Inside the sandboxed extension, a cold render takes 35–45 ms for a small notebook and 443 ms for the 25 MB one. Previews feel instant, and the 25 MB one scrolls smoothly. |
| Math | Pulling math out before markdown-it runs works: 61 and 76 equations rendered, 0 KaTeX errors. NUL placeholders break because markdown-it rewrites `\0`, so use private-use characters. |
| Does Finder use our extension? | **Yes.** An imported `org.jupyter.ipynb` type (conforms to `public.json`) takes over from the dynamic `dyn.*` type once the app is registered. Space in Finder shows our preview. No other app on this machine declares an ipynb type. |
| Ad-hoc signing + Homebrew-style quarantine | `spctl --assess` rejects the app whether or not it is quarantined (expected for non-notarized apps). After `xattr -dr com.apple.quarantine`, the app launches and the extension registers (`pluginkit -m`). The cask needs a postflight step that removes quarantine. |
| Images stored next to the notebook (`![](../img/x.png)`) | Blocked by the sandbox by default. **Allowed** with `com.apple.security.temporary-exception.files.home-relative-path.read-only = ["/"]`. Fine for Homebrew distribution; the App Store would reject it. |
| Sharing settings between the app and the extension | **App Groups don't work with ad-hoc signing.** Xcode refuses to build without a provisioning profile. Signing by hand builds, but on first launch macOS 15 shows "JuPrevSpike would like to access data from other apps", and the write never happens until it's answered. **A plain file works:** the app writes `~/Library/Application Support/<App>/settings.json` (read-write temporary exception for that folder only), and the extension reads it through its read-only exception. No dialog, verified. Note: inside the sandbox `NSHomeDirectory()` is the container, so the real home comes from `getpwuid(getuid())`. |

## Gotchas

- **`reply.stringEncoding = .utf8` is required.** Without it the HTML preview came up blank.
- `log` is a zsh builtin, so use `/usr/bin/log show --predicate 'subsystem == "…"'` to read extension logs.
- An old build in DerivedData stays registered with LaunchServices. Run `lsregister -u` on it so the installed copy is the one that's used.
- Bundle IDs: the extension's ID must start with the app's ID.

## Consequences drawn at the time

Items 2 and 4 have since been resolved: see the phase 2 addendum below and `renderer/styles/notebook.css`.

1. **Keep the JavaScriptCore pre-render.** It's fast, produces one static HTML for the app, Quick Look and export, and works without a DOM.
2. **Security: scripts in notebook outputs *will* run in Quick Look.** Phase 2 must add a CSP `<meta>` (`script-src 'none'`, no network) and verify that it actually blocks inline scripts.
3. **Images next to the notebook:** use the read-only temporary exception in both the extension and the app. Decide between home-relative and absolute paths, since home-relative doesn't cover `/Volumes/...`.
4. **CSS:** markdown images need `max-width: 100%`. They currently overflow.

## Phase 2 addendum: data-based previews ignore CSP

Tested in phase 2 with `Tests/NotebookKitTests/Fixtures/csp-probe.ipynb`. In a data-based
(`QLPreviewReply`) HTML preview, the page's `<meta http-equiv="Content-Security-Policy">`
is **ignored**: `<script>`, `onload` and `ontoggle` all ran in Quick Look, though the same
page is protected in a regular WKWebView. The extension is therefore **view-based**: it hosts
its own WKWebView with `allowsContentJavaScript = false` and a content rule list that blocks
all URL loads (now `NotebookKit/NotebookWebView.swift`). Notes:

- A WKWebView in a sandboxed extension needs `com.apple.security.network.client`, or its
  WebContent and Networking processes crash. The rule list still blocks every load.
- WebKit content-rule `url-filter` regexes don't support `|`; use one rule per scheme.
- Timings (Low Power Mode, on battery): about 260 ms until a typical notebook shows; about 1.3 s for the 25 MB one,
  returning from `preparePreviewOfFile` on `didCommit` so large pages paint progressively.
