# JuPrev

A minimal MacOS viewer for Jupyter Notebooks with Quick Look previews and
Finder thumbnails.
Press Space on a `.ipynb` file in Finder to read it, rendered, without starting
Jupyter or an editor.

- **Quick Look previews**: Markdown, LaTeX math (KaTeX), syntax-highlighted
  code and outputs (text, tables, images, plots, tracebacks) in light and dark
  mode.
- **Finder thumbnails**: the notebook's title, opening text and first plot.
- **Viewer app**: one quiet window per notebook, or a tabbed layout, that
  reloads live when the notebook changes on disk (keeping your place), with an
  outline sidebar, find, show/hide code and outputs, themes, zoom, and export to
  HTML and PDF.
- **Self-contained**: no Python, Jupyter or network connection needed.
  Notebooks are plain JSON, rendered by a bundled JavaScript renderer.

Requires MacOS 14 (Sonoma) or later on Apple Silicon or Intel.

## Install

> [!WARNING]
> **App signing and quarantine**
>
> JuPrev is signed ad hoc but not notarized by Apple, so the first time
> you open it MacOS says it cannot check it for malicious software.
> Either:
>
> - open it once, then go to **System Settings › Privacy & Security**,
>   scroll down and click **Open Anyway** next to the message about JuPrev; or
> - remove the quarantine attribute in Terminal:
>
>   ```sh
>   xattr -dr com.apple.quarantine /Applications/JuPrev.app
>   ```
>
> Homebrew removes the quarantine attribute after installing the app,
> so MacOS opens it without the warning.

### Manual

Download the zip on the [releases page][release] and install by moving
`JuPrev.app` to Applications, then:

```sh
xattr -dr com.apple.quarantine /Applications/JuPrev.app  # lets Gatekeeper open it
open /Applications/JuPrev.app                            # registers the Quick Look extensions
pkill -f com.apple.quicklook.ThumbnailsAgent             # allows thumbnails to appear
```

### Brew

```sh
brew tap So-Cool/tap
brew install --cask juprev
```

Then open JuPrev once, after every install or upgrade:
that registers its Quick Look previews and Finder thumbnails.
After a fresh install, thumbnails appear once you log out and back in, or
straight away after `pkill -f com.apple.quicklook.ThumbnailsAgent`.
Homebrew prints this reminder too.

## Use

- **Preview**:
  select a notebook in Finder and press Space.
- **Open**:
  right-click a notebook ▸ Open With ▸ JuPrev.
  JuPrev doesn't take over double-click from your current notebook app;
  to make it the default, use Get Info ▸ Open with ▸ Change All.
- **Settings** (JuPrev ▸ Settings…):
  the theme, whether code, outputs and stderr are shown, and whether images may load
  from parent folders and from the web (both off by default).
  Theme and show/hide choices apply to Quick Look too.

| Shortcut | In the viewer |
| -------- | ------------- |
| ⌃⌘S      | Show/hide the outline (remembered for new windows) |
| ⌘F, ⌘G, ⇧⌘G, ⌘E | Find, next/previous match, find the selection |
| ⌥⌘C, ⌥⌘O, ⌥⌘L | Show/hide code, outputs and stderr (warnings, progress bars, logs) in this window; Settings sets the default |
| ⌘R       | Reload (the notebook also reloads by itself when it changes on disk) |
| ⌘+, ⌘−, ⌘0 | Zoom |
| ⇧⌘E, ⌥⌘E | Export as HTML (static, no scripts) or PDF |
| ⌘P       | Print |

### Themes

View ▸ Theme (or Settings) picks *Default*, *Serif*, *Compact*,
*Gruvbox Material Dark* or *Gruvbox Material Light* (the hard-contrast variants of
[gruvbox-material](https://github.com/sainnhe/gruvbox-material), with its exact colours).
For your own, put `.css` files in the folder that **View ▸ Theme ▸ Open Themes
Folder** opens (`~/Library/Application Support/JuPrev/Themes`); they're applied
after the default style and are listed by file name.
After editing one, View ▸ Reload (⌘R) applies it.
The simplest themes override the colour variables, for light and dark mode:

```css
:root {
  --text: #3b3a36; --background: #fdf6e3; --code-background: #f3ecd8;
  --link: #b58900; --rule: #e6dfca; --text-muted: #93a1a1;
}
@media (prefers-color-scheme: dark) {
  :root { --text: #d6d2c4; --background: #1f2327; --code-background: #2a2f34; }
}
```

Other variables: `--code-text`, `--stderr-background`, `--error-background`,
`--placeholder-text`, `--table-stripe` and `--ansi-{black,red,green,yellow,blue,magenta,cyan,white}`.
Typography and layout can be changed with ordinary CSS, e.g. `body { font-family: … }`
or `.notebook { max-width: 50em; }`.
Printing and PDF export always use the light colours.

## Privacy and security

Notebooks can contain anything, so JuPrev treats them as untrusted:

- **No scripts.**
  Pages are static:
  JavaScript is switched off and every network request is blocked.
  Exported or copied HTML also carries a strict Content Security Policy.
- **Interactive outputs** (widgets, Plotly, Bokeh…) show the static image the
  notebook saved or a placeholder.
  In the app, a bar offers **Allow Scripts** for that window only.
  It's never remembered and Quick Look never runs scripts.
- **Nothing from the Internet by default.**
  Images linked from the web load only if you turn on *Load remote images* and
  only in the app.
- **Local images** referenced from Markdown load only from the notebook's
  folder and its subfolders, unless you turn on
  *Load images from parent folders*.
  Symlinks are resolved before that check and absolute paths are never loaded.

The app and its extensions are sandboxed.
They read files outside the sandbox only to show images next to a notebook and
the rules above decide which ones.

## Limitations

- Notebooks in nbformat 4 (Jupyter 4.0 and later, from 2015) only.
- Widgets need a running kernel so they only ever show a placeholder or saved
  image.
- Thumbnails show raster plots (PNG, JPEG, GIF) only;
  notebooks whose plots are all SVG get a text-only thumbnail.
- Math macros defined outside the notebook aren't known.

## Develop

| Path                      | What |
| ------------------------- | ---- |
| `renderer/`               | JS renderer (markdown-it, KaTeX, highlight.js), the default stylesheet and the bundled themes; see [Renderer build](#renderer-build). |
| `Sources/NotebookKit/`    | Runs the JS bundle in JavaScriptCore and produces a self-contained static HTML page. Also owns the local-image policy, the shared settings file, the web view configuration and the thumbnail summary. |
| `Sources/juprev/`         | CLI: `juprev render notebook.ipynb -o out.html` |
| `QuickLook/`              | View-based Quick Look preview extension. |
| `Thumbnail/`              | Thumbnail extension, drawn from `NotebookSummary` (no web view). |
| `App/`                    | AppKit document-based viewer. Registers as an *alternate* handler for `org.jupyter.ipynb`. |
| `project.yml`             | XcodeGen spec for the app and extensions (`JuPrev.xcodeproj` is generated, not committed). |
| `Tests/NotebookKitTests/` | Swift Testing suite, fixture notebooks (`Fixtures/make_fixtures.py`) and HTML snapshots. |

```sh
swift build
swift test
swift run juprev render path/to/notebook.ipynb -o /tmp/out.html --time

# After changing renderer/src or renderer/styles:
(cd renderer && npm install && npm run build)

# After an intended rendering change:
JUPREV_RECORD_SNAPSHOTS=1 swift test

# Build, install to ~/Applications and register the extensions (needs xcodegen)
scripts/install-dev.sh
qlmanage -p path/to/notebook.ipynb
/usr/bin/log stream --predicate 'subsystem BEGINSWITH "me.kcpr.juprev"'
```

Settings live in `~/Library/Application Support/JuPrev/settings.json`,
shared by the app and the extensions (these are the defaults):

```json
{ "trustParentFolders": false,
  "loadRemoteImages": false,
  "showCode": true,
  "showOutputs": true,
  "showStderr": true,
  "theme": "default"
}
```

### Renderer build

`npm run build` in `renderer/` (`renderer/build.mjs`) turns the renderer's sources
into files that are committed, so building the Swift code never needs Node:

| Source | Output | How |
| ------ | ------ | --- |
| `renderer/src/*.js` | `Sources/NotebookKit/Resources/render.js` | Bundled and minified by esbuild |
| `renderer/styles/notebook.css` | `Sources/NotebookKit/Resources/style.css` | Combined with KaTeX's CSS (fonts inlined) and the highlight.js themes |
| `renderer/styles/themes/*.css` | `Sources/NotebookKit/Resources/themes/` | Copied as they are |
| Licence files of the bundled npm packages | `ACKNOWLEDGEMENTS.md`, `App/Credits.html` | Generated |

Edit only the sources, then run the build: the outputs are overwritten.
The **Test** workflow fails if the committed outputs don't match a fresh build.

## Release

Versions are `major.minor` (e.g. `0.1`, `0.2`, `1.0`).
Push a tag such as `v0.2`.
The **Release** workflow runs `scripts/release.sh`
(tests, then a universal ad-hoc signed build zipped into `dist/`),
publishes a GitHub release with the zip and
updates `version` and `sha256` in `Casks/juprev.rb` in [So-Cool/tap][tap].
The cask update needs a `TAP_GITHUB_TOKEN` secret:
a fine-grained token with *Contents: read and write* on the tap only.

The tag sets the version shown in the app.
Keep `MARKETING_VERSION` in `project.yml` in step:
it is the version for local builds (`scripts/release.sh` without `VERSION`).

The **Test** workflow runs on pushes to `master` and `dev` and on pull requests:
it checks that the committed renderer bundle and notices match `renderer/`,
runs `swift test` and builds the app with its extensions.

## Design notes

Why JuPrev is built the way it is (including the Quick Look, sandbox and
signing findings behind the current design).

### Spike results

| Question | Answer |
| -------- | ------ |
| Does JavaScript run in a data-based (`QLPreviewReply` HTML) preview? | **Yes.** The inline probe script ran in both `qlmanage -p` and Finder. |
| JavaScriptCore render speed | Context + 564 KB bundle load: 22--32 ms. Typical notebooks: 6--16 ms. 10 MB: 122 ms. 25 MB: ~400 ms. Inside the sandboxed extension, a cold render takes 35--45 ms for a small notebook and 443 ms for the 25 MB one. Previews feel instant and the 25 MB one scrolls smoothly. |
| Math | Pulling math out before markdown-it runs works: 61 and 76 equations rendered, 0 KaTeX errors. NUL placeholders break because markdown-it rewrites `\0`, so use private-use characters. |
| Does Finder use our extension? | **Yes.** An imported `org.jupyter.ipynb` type (conforms to `public.json`) takes over from the dynamic `dyn.*` type once the app is registered. Space in Finder shows our preview. No other app on this machine declares an ipynb type. |
| Ad-hoc signing + Homebrew-style quarantine | `spctl --assess` rejects the app whether or not it is quarantined (expected for non-notarized apps). After `xattr -dr com.apple.quarantine`, the app launches and the extension registers (`pluginkit -m`). The cask needs a postflight step that removes quarantine. |
| Images stored next to the notebook (`![](../img/x.png)`) | Blocked by the sandbox by default. **Allowed** with `com.apple.security.temporary-exception.files.home-relative-path.read-only = ["/"]`. Fine for Homebrew distribution; the App Store would reject it. |
| Sharing settings between the app and the extension | **App Groups don't work with ad-hoc signing.** Xcode refuses to build without a provisioning profile. Signing by hand builds, but on first launch macOS 15 shows "JuPrevSpike would like to access data from other apps" and the write never happens until it's answered. **A plain file works:** the app writes `~/Library/Application Support/<App>/settings.json` (read-write temporary exception for that folder only) and the extension reads it through its read-only exception. No dialog, verified. Note: inside the sandbox `NSHomeDirectory()` is the container, so the real home comes from `getpwuid(getuid())`. |

### Gotchas

- **`reply.stringEncoding = .utf8` is required.**
  Without it the HTML preview came up blank.
- `log` is a zsh builtin, so use
  `/usr/bin/log show --predicate 'subsystem == "…"'` to read extension logs.
- An old build in DerivedData stays registered with LaunchServices.
  Run `lsregister -u` on it so the installed copy is the one that's used.
- Bundle IDs:
  the extension's ID must start with the app's ID.

### Consequences drawn at the time

Items 2 and 4 have since been resolved:
see the phase 2 addendum below and `renderer/styles/notebook.css`.

1. **Keep the JavaScriptCore pre-render.**
   It's fast, produces one static HTML for the app, Quick Look and export and
   works without a DOM.
2. **Security: scripts in notebook outputs *will* run in Quick Look.**
   Phase 2 must add a CSP `<meta>` (`script-src 'none'`, no network) and
   verify that it actually blocks inline scripts.
3. **Images next to the notebook:**
   use the read-only temporary exception in both the extension and the app.
   Decide between home-relative and absolute paths since home-relative doesn't
   cover `/Volumes/...`.
4. **CSS:**
   markdown images need `max-width: 100%`.
   They currently overflow.

### Phase 2 addendum: Data-based previews ignore CSP

Tested in phase 2 with `Tests/NotebookKitTests/Fixtures/csp-probe.ipynb`.
In a data-based (`QLPreviewReply`) HTML preview, the page's
`<meta http-equiv="Content-Security-Policy">` is **ignored**:
`<script>`, `onload` and `ontoggle` all ran in Quick Look, though the same
page is protected in a regular WKWebView.
The extension is therefore **view-based**:
it hosts its own WKWebView with `allowsContentJavaScript = false` and a content
rule list that blocks all URL loads (now `NotebookKit/NotebookWebView.swift`).
Notes:

- A WKWebView in a sandboxed extension needs
  `com.apple.security.network.client` or its WebContent and Networking
  processes crash.
  The rule list still blocks every load.
- WebKit content-rule `url-filter` regexes don't support `|`;
  use one rule per scheme.
- Timings (Low Power Mode, on battery):
  about 260 ms until a typical notebook shows;
  about 1.3 s for the 25 MB one, returning from `preparePreviewOfFile` on
  `didCommit` so large pages paint progressively.

### Release addendum: What a Homebrew cask can and can't do

Learned from the first release (0.1, installed with Homebrew 7.0):

- Cask `postflight_steps` always run in Homebrew's sandbox.
  `xattr` works, but `open` fails with `kLSUnknownErr` (-10810,
  "Couldn't communicate with a helper application") and `pkill` can't signal
  the thumbnail service.
  Only `sudo` steps run outside the sandbox, which would mean a password prompt
  and launching the app as root.
- The extensions register only when the app is **launched**.
  Moving it to `/Applications` registers the app with LaunchServices but not
  its extensions and `lsregister -f` doesn't register them either.
  Replacing or unregistering the app drops them again,
  so they're gone after an upgrade until the next launch.
- The thumbnail service (`com.apple.quicklook.ThumbnailsAgent`) only picks up
  *new* thumbnail extensions when it restarts;
  it keeps known ones across reinstalls.
  `killall` can't match its name (process names are cut to 16 characters),
  so use `pkill -f` or `kill <pid>`.

So the cask only removes the quarantine attribute and uses `caveats` to ask
the user to open the app once and, after a fresh install, restart the
thumbnail service.

## License

MIT, see [LICENSE](LICENSE).
The bundled renderer includes third-party packages under the MIT, BSD-2-Clause
and BSD-3-Clause licences:
see [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md),
also shown in JuPrev ▸ About JuPrev.

[release]: https://github.com/So-Cool/JuPrev/releases
[tap]: https://github.com/So-Cool/homebrew-tap
