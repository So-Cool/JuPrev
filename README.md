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
  outline sidebar, find, show/hide code and outputs, themes, zoom as well as
  HTML and PDF export.
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
> - remove the quarantine attribute in Terminal to let Gatekeeper open the app:
>
>   ```sh
>   xattr -dr com.apple.quarantine /Applications/JuPrev.app
>   ```
>
>
> Homebrew removes the quarantine attribute after installing the app,
> so MacOS opens it without the warning.

> [!NOTE]
> **Quick Look previews and Finder thumbnails**
>
> To register JuPrev's Quick Look extension and let Finder generate `.jpnyb`
> thumbnails open JuPrev once after every install or upgrade:
>
> ```sh
> open /Applications/JuPrev.app
> ```
>
> After a fresh install, thumbnails appear once you log out and back in or
> straight away after:
>
> ```sh
> pkill -f com.apple.quicklook.ThumbnailsAgent
> ```
>
> Homebrew prints this reminder too.

### Manual

Download the zip from the [releases page][release] and install `JuPrev.app` by
moving it to the Applications folder.

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
  the theme, whether code, outputs and stderr are shown, and whether images
  may load from parent folders and from the web (both off by default).
  Theme and show/hide choices apply to Quick Look too.

| Shortcut                                                 | In the viewer |
| -------------------------------------------------------- | ------------- |
| <kbd>⌃⌘S</kbd>                                           | Show/hide the outline (remembered for new windows). |
| <kbd>⌘F</kbd> <kbd>⌘G</kbd> <kbd>⇧⌘G</kbd> <kbd>⌘E</kbd> | Find, next/previous match, find the selection. |
| <kbd>⌥⌘C</kbd> <kbd>⌥⌘O</kbd> <kbd>⌥⌘L</kbd>             | Show/hide code, outputs and stderr (warnings, progress bars, logs) in this window; Settings sets the default. |
| <kbd>⌘R</kbd>                                            | Reload (the notebook also reloads by itself when it changes on disk). |
| <kbd>⌘+</kbd> <kbd>⌘−</kbd> <kbd>⌘0</kbd>                | Zoom. |
| <kbd>⇧⌘E</kbd> <kbd>⌥⌘E</kbd>                            | Export as HTML (static, no scripts) or PDF. |
| <kbd>⌘P</kbd>                                            | Print. |

### Themes

View ▸ Theme (or Settings) picks *Default*, *Serif*, *Compact*,
*Gruvbox Material Dark* or *Gruvbox Material Light*
(the hard-contrast variants of [gruvbox-material][gruvbox]).
For your own, put `.css` files in the folder that
**View ▸ Theme ▸ Open Themes Folder** opens
(`~/Library/Application Support/JuPrev/Themes`);
they're applied after the default style and are listed by file name.
After editing one, View ▸ Reload (⌘R) applies it.
The simplest themes override the colour variables for light and dark mode:

```css
:root {
  --text: #3b3a36; --background: #fdf6e3; --code-background: #f3ecd8;
  --link: #b58900; --rule: #e6dfca; --text-muted: #93a1a1;
}
@media screen and (prefers-color-scheme: dark) {
  :root { --text: #d6d2c4; --background: #1f2327; --code-background: #2a2f34; }
}
```

Other variables:
`--code-text`, `--stderr-background`, `--error-background`,
`--placeholder-text`, `--table-stripe` and
`--ansi-{black,red,green,yellow,blue,magenta,cyan,white}`.
Typography and layout can be changed with ordinary CSS, e.g.,
`body { font-family: … }` or `.notebook { max-width: 50em; }`.
Printing and PDF export use the light colours:
keep a theme's dark colours inside `@media screen`, as above,
so they don't reach the page.

## Privacy and security

Notebooks can contain anything, so JuPrev treats them as untrusted:

- **No scripts.**
  Pages are static:
  JavaScript is switched off and every network request is blocked.
  HTML saved with File ▸ Export as HTML also carries a strict Content Security
  Policy so it stays inert in a browser.
- **Interactive outputs** (widgets, Plotly, Bokeh…) show the static image the
  notebook saved or a placeholder.
  In the app, a bar offers **Allow Scripts** for that window only.
  It's never remembered, it's switched off again when the notebook changes on
  disk or is reloaded (<kbd>⌘R</kbd>) and Quick Look never runs scripts.
- **Nothing from the Internet by default.**
  Images linked from the web load only if you turn on *Load remote images* and
  then only in the app and in HTML it exports (or `juprev render` writes);
  Quick Look never loads them.
- **Local images** referenced from Markdown load only from the notebook's
  folder and its subfolders.
  *Load images from parent folders* lifts that limit for relative paths such
  as `../figures/plot.png`:
  since `..` can be repeated, they can then reach any image on the disk.
  Symlinks are resolved before the folder check and absolute paths are never
  loaded.
- **Load once.**
  With either image setting off, a bar (and View ▸ Load Images from
  Parent Folders / Load Remote Images) offers to load the images it left
  out, for that window only, cleared like Allow Scripts.
  Plain `http://` images never load.

The app and its extensions are sandboxed.
Outside the sandbox they read only images next to a notebook
(the rules above decide which ones) and JuPrev's own settings and custom themes
in `~/Library/Application Support/JuPrev`, which only the app writes to;
exports go where you choose in the save panel.

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

# Build, install to ~/Applications and register the extensions (needs xcodegen).
# If JuPrev is also installed with Homebrew, both copies register the same
# extensions:
# open notebooks with the dev copy by path and remove it when done.
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

`npm run build` in `renderer/` (`renderer/build.mjs`) turns the renderer's
sources into files that are committed,
so building the Swift code never needs Node:

| Source                                   | Output | How |
| ---------------------------------------- | ------ | --- |
| `renderer/src/*.js`                      | `Sources/NotebookKit/Resources/render.js`  | Bundled and minified by esbuild. |
| `renderer/styles/notebook.css`           | `Sources/NotebookKit/Resources/style.css`  | Combined with KaTeX's CSS (fonts inlined) and the highlight.js themes. |
| `renderer/styles/themes/*.css`            | `Sources/NotebookKit/Resources/themes/`   | Copied as they are. |
| Licence files of the bundled npm packages | `ACKNOWLEDGEMENTS.md`, `App/Credits.html` | Generated. |

Edit only the sources, then run the build:
the outputs are overwritten.
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

The **Test** workflow runs on pushes to `master` and on pull requests:
it checks that the committed renderer bundle and notices match `renderer/`,
runs `swift test` and builds the app with its extensions.

## License

MIT, see [LICENSE](LICENSE).
The bundled renderer includes third-party packages under the MIT, BSD-2-Clause
and BSD-3-Clause licences:
see [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md),
also shown in JuPrev ▸ About JuPrev.

[release]: https://github.com/So-Cool/JuPrev/releases
[tap]: https://github.com/So-Cool/homebrew-tap
[gruvbox]: https://github.com/sainnhe/gruvbox-material
