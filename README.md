# JuPrev

A minimal native macOS viewer and Quick Look extension for Jupyter notebooks.

Status: phase 4 of 5 — renderer (`NotebookKit`), `juprev` CLI, Quick Look previews and
Finder thumbnails, a minimal viewer app, and Homebrew packaging. Marked-style features
(live reload, outline, themes, export) come next.

## Install

```sh
brew tap So-Cool/tap
brew install --cask juprev
```

JuPrev is ad-hoc signed, not notarized; the cask removes the quarantine flag so
Gatekeeper lets it run, registers the Quick Look extensions and restarts the
thumbnail service. Requires macOS 14 (Sonoma) or later. `spike/` holds the throwaway
feasibility spike; see `spike/FINDINGS.md`.

## Layout

| Path | What |
|---|---|
| `renderer/` | JS renderer (markdown-it, KaTeX, highlight.js) and the default stylesheet. `npm run build` writes `Sources/NotebookKit/Resources/{render.js,style.css}`, which are committed so Swift builds don't need Node. |
| `Sources/NotebookKit/` | Runs the JS bundle in JavaScriptCore and produces a self-contained static HTML page (strict CSP, images and fonts inlined). Also owns the local-image folder policy and the shared settings file. |
| `Sources/juprev/` | CLI: `juprev render notebook.ipynb -o out.html` |
| `QuickLook/` | View-based Quick Look extension: JavaScript off, network blocked (`NotebookWebView`). |
| `Thumbnail/` | Finder thumbnails: title, opening text and first plot, drawn from `NotebookSummary` (no web view). |
| `App/` | AppKit document-based viewer: one window per notebook, "Allow Scripts" bar for interactive outputs, Settings window. Registers as an *alternate* handler for `org.jupyter.ipynb`. |
| `project.yml` | XcodeGen spec for the app and extension (`JuPrev.xcodeproj` is generated, not committed). |
| `Tests/NotebookKitTests/` | Swift Testing suite, fixture notebooks (`Fixtures/make_fixtures.py`) and HTML snapshots. |

## Develop

```sh
swift build
swift test
swift run juprev render path/to/notebook.ipynb -o /tmp/out.html --time

# after changing renderer/src or renderer/styles
(cd renderer && npm install && npm run build)

# after an intended rendering change
JUPREV_RECORD_SNAPSHOTS=1 swift test

# build, install to ~/Applications and register the Quick Look extensions (needs xcodegen)
scripts/install-dev.sh
qlmanage -p path/to/notebook.ipynb
/usr/bin/log stream --predicate 'subsystem == "me.kcpr.juprev.quicklook"'
```

## Release

1. Bump `MARKETING_VERSION` in `project.yml`.
2. `scripts/release.sh` runs the tests, builds a universal ad-hoc signed app into
   `dist/JuPrev-<version>.zip` and prints its sha256 plus the tag/release commands.
3. Update `version` and `sha256` in `Casks/juprev.rb` in
   [So-Cool/homebrew-tap](https://github.com/So-Cool/homebrew-tap).

## Scripts and remote content

Notebooks are untrusted, so pages are static: JavaScript is off and every network load
is blocked (`NotebookWebView`), with a strict CSP as a second layer for exported HTML.
When a notebook has interactive outputs (widgets, Plotly, SHAP…), the app shows a bar
offering **Allow Scripts** for that window only; it is never remembered. Quick Look
never runs scripts or loads anything from the network.

## Local images

Markdown images such as `![](img/plot.png)` load only from the notebook's folder
and its subfolders (symlinks are resolved first, absolute paths are refused).
The **trust parent folders** setting also allows `../` paths. Settings live in
`~/Library/Application Support/JuPrev/settings.json`, which the app and the Quick
Look extension share:

```json
{ "trustParentFolders": true, "loadRemoteImages": false }
```

Both are also in JuPrev ▸ Settings. `loadRemoteImages` (https images) applies to the app only.
