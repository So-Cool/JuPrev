# JuPrev

A minimal native macOS viewer and Quick Look extension for Jupyter notebooks.

Status: phase 2 of 5 — the shared renderer (`NotebookKit`), the `juprev` CLI and the
Quick Look extension. The viewer app comes next (`App/` is a placeholder for now). `spike/` holds the throwaway
feasibility spike; see `spike/FINDINGS.md`.

## Layout

| Path | What |
|---|---|
| `renderer/` | JS renderer (markdown-it, KaTeX, highlight.js) and the default stylesheet. `npm run build` writes `Sources/NotebookKit/Resources/{render.js,style.css}`, which are committed so Swift builds don't need Node. |
| `Sources/NotebookKit/` | Runs the JS bundle in JavaScriptCore and produces a self-contained static HTML page (strict CSP, images and fonts inlined). Also owns the local-image folder policy and the shared settings file. |
| `Sources/juprev/` | CLI: `juprev render notebook.ipynb -o out.html` |
| `QuickLook/` | View-based Quick Look extension: JavaScript off, network blocked (`StaticWebView`). |
| `App/` | Host app (placeholder until phase 3); declares the `org.jupyter.ipynb` type. |
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

# build, install to ~/Applications and register the Quick Look extension (needs xcodegen)
scripts/install-dev.sh
qlmanage -p path/to/notebook.ipynb
/usr/bin/log stream --predicate 'subsystem == "ch.usi.kacper.juprev.quicklook"'
```

## Local images

Markdown images such as `![](img/plot.png)` load only from the notebook's folder
and its subfolders (symlinks are resolved first, absolute paths are refused).
The **trust parent folders** setting also allows `../` paths. Settings live in
`~/Library/Application Support/JuPrev/settings.json`, which the app and the Quick
Look extension share:

```json
{ "trustParentFolders": true }
```
