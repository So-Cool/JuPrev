# JuPrev

A minimal MacOS viewer for Jupyter Notebooks with Quick Look previews and
Finder thumbnails.
Press Space on a `.ipynb` file in Finder to read it, rendered, without starting
Jupyter or an editor.

- **Quick Look previews**: Markdown, LaTeX math (KaTeX), syntax-highlighted
  code and outputs (text, tables, images, plots, tracebacks) in light and dark
  mode.
- **Finder thumbnails**: the notebook's title, opening text and first plot.
- **Viewer app**: one quiet window per notebook, or a tabbed layout, with zoom
  and Open Recent.
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
> so MacOS opens it without the warning;
> it also registers the Quick Look extensions and restarts the thumbnail
> service.

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

## Use

- **Preview**:
  select a notebook in Finder and press Space.
- **Open**:
  right-click a notebook ▸ Open With ▸ JuPrev.
  JuPrev doesn't take over double-click from your current notebook app;
  to make it the default, use Get Info ▸ Open with ▸ Change All.
- **Settings** (JuPrev ▸ Settings…):
  whether images may load from parent folders and from the web
  (both off by default).

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

## To do

- [ ] Confirm the WebKit security tests (`ContentSecurityPolicyTests`) pass on
      GitHub's macOS runners.
- [ ] Confirm the cask's `open` and `pkill` install steps work inside
      Homebrew's sandbox on the first real install
      (both are allowed to fail so they can't break it).
- [ ] Marked-style features:
      live reload, an outline sidebar, show/hide code and outputs, themes,
      HTML/PDF export.

## Develop

| Path                      | What |
| ------------------------- | ---- |
| `renderer/`               | JS renderer (markdown-it, KaTeX, highlight.js) and the default stylesheet. `npm run build` writes `Sources/NotebookKit/Resources/{render.js,style.css}`, `ACKNOWLEDGEMENTS.md` and `App/Credits.html`, all committed so Swift builds don't need Node. |
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
shared by the app and the extensions:

```json
{ "trustParentFolders": false,
  "loadRemoteImages": false
}
```

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

Why JuPrev is built the way it is, including the Quick Look, sandbox and signing
findings behind the current design, is recorded in
[docs/design-notes.md](docs/design-notes.md).

## License

MIT, see [LICENSE](LICENSE).
The bundled renderer includes third-party packages under the MIT, BSD-2-Clause
and BSD-3-Clause licences:
see [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md),
also shown in JuPrev ▸ About JuPrev.

[release]: https://github.com/So-Cool/JuPrev/releases
[tap]: https://github.com/So-Cool/homebrew-tap
