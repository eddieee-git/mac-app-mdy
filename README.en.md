<p align="center"><img src="docs/images/icon.png" width="96" alt="Mdy icon"></p>

<h1 align="center">Mdy</h1>

<p align="center">A macOS Markdown viewer and editor that opens with a double-click in Finder<br>Source on the left, polished preview on the right. Edit either side and the other follows.</p>

<p align="center">
  <a href="https://github.com/eddieee-git/mac-app-mdy/releases/latest">Download the latest version</a> ·
  <a href="#install">Install</a> ·
  <a href="#how-to-use">How to use</a> ·
  <a href="#shortcuts">Shortcuts</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="CHANGELOG.en.md">Changelog</a> ·
  <a href="README.md">한국어</a>
</p>

## Features

- **Double-click to open**: Mdy becomes the default app for `.md` files, and pressing Space in Finder previews them in Mdy's style.
- **Source and preview side by side**: change the width with the ratio buttons (1:3 · 1:1 · 3:1) or the divider, or collapse either side.
- **Both sides follow each other**: place the cursor or select text on one side and the same spot is highlighted on the other; scrolling moves together too.
- **Edit right in the preview**: double-click the preview and that block becomes a Markdown box. Checklist boxes can be ticked right there.
- **Comfortable writing**: syntax coloring, formatting shortcuts, list and table continuation, auto-closing brackets, folding headings, line numbers, focus mode.
- **Paste and copy**: formatting copied from the web, Google Docs or Word comes in as Markdown, and Excel cells become a table. Copy from the preview to paste with formatting into Mail or Slack. Images are saved next to the document.
- **Several documents**: folder sidebar, Open Quickly, search across a folder, links between documents with back and forward, templates.
- **GitHub-style syntax**: tables, checklists, footnotes, alerts, code coloring, `[TOC]`, math (KaTeX) and diagrams (Mermaid), all rendered offline.
- **Export**: HTML, PDF, Word, RTF and print.
- **Changed lines**: documents in a git repository show lines added, modified or deleted since the last commit. Files changed by other apps are reloaded.
- **Safe viewing**: scripts inside documents never run, and links to executables aren't opened. Remote images can be blocked.
- **In-app updates**: Mdy tells you about new versions and swaps them in after checking the signature.
- **Korean and English**: follows your Mac's language at first; change it in Settings.

## Install

Requires macOS 14 (Sonoma) or later. Both Apple silicon and Intel Macs are supported.

1. Download `Mdy-x.y.z.dmg` from [Releases](https://github.com/eddieee-git/mac-app-mdy/releases/latest) and open it.
2. Drag **Mdy** into the **Applications** folder.
3. Open Mdy. It isn't signed by an Apple developer, so macOS refuses the first launch. Click **Done**, then:
   - **macOS 15 (Sequoia) or later**: scroll to the bottom of System Settings → Privacy & Security, click **Open Anyway** next to Mdy, then **Open** once more.
   - **macOS 14 (Sonoma)**: in the Applications folder, **right-click Mdy → Open**.

   If you prefer Terminal, run `xattr -dr com.apple.quarantine /Applications/Mdy.app`.
4. If double-clicking a `.md` file opens another app, select a `.md` file in Finder, press ⌘I, choose Mdy under **Open with**, and click **Change All**.

## How to use

1. Double-click a `.md` file in Finder. Opening Mdy without a document shows the **start window** with new document, recent documents and templates.
2. Write in the source on the left, or double-click the preview on the right to edit in place. Edits are saved automatically.
3. Use the **sidebar** button at the left of the toolbar for the outline, files and search, and the ratio buttons on the right to resize the panes.
4. See **Help → Mdy Help** (⌘?) for details. The help document itself is an example of every supported syntax.

## Shortcuts

| Keys | Action |
|---|---|
| ⌘1 · ⌘2 · ⌘3 | Source only · side by side · preview only |
| ⌥⌘1 · ⌥⌘2 · ⌥⌘3 | Source : preview ratio 1:3 · 1:1 · 3:1 |
| ⌃⌘S | Sidebar (outline · files · search) |
| ⇧⌘O | Open Quickly |
| ⇧⌘F | Find in folder |
| ⌘F · ⌘G · ⇧⌘G | Find · next · previous (source and preview) |
| ⌘B · ⌘I · ⌘K | Bold · italic · link |
| ⇧⌘K · ⇧⌘X · ⇧⌘H | Code · strikethrough · highlight |
| ⌃⌘1–6 · ⌃⌘0 | Heading 1–6 · body text |
| ⇧⌘T | Align table |
| ⌥⌘← · ⌥⌘→ | Fold · unfold heading |
| ⌘[ · ⌘] | Back · forward between linked documents |
| ⌥⇧⌘C | Copy as rich text |
| ⇧⌘J | Focus mode |
| ⌥⌘L | Sync scrolling |
| ⇧⌘E · ⌥⌘P | Export as HTML · PDF |
| ⌘? | Help |

## Settings

| Setting | Description |
|---|---|
| Appearance | Match system / light / dark |
| View when opening a document | Source only / side by side / preview only (default: the last mode you used) |
| Open documents as tabs in one window | Gathers documents as tabs (on by default) |
| Workspace folder | Folder used by the sidebar, Open Quickly and search (default: the current document's folder) |
| Editor | Font and size, syntax coloring, spell check, auto-continue, auto-close, paste conversion, line numbers, changed lines, image folder name |
| Preview | Font, text width, theme (GitHub / paper), math and diagrams, block remote images (off by default) |
| Open at login | Start Mdy when you log in (off by default) |
| Language | System / 한국어 / English |
| Check for updates automatically | Checks GitHub for a new version once a day (on by default) |
| Install updates automatically | Installs a found update while you're not using Mdy, then reopens it (on by default) |

## FAQ

**What information does Mdy send?**
Only one request to the public GitHub API asking for the latest release when checking for updates. Document contents are never sent anywhere. Turn off automatic checks in Settings to stop that too. If a document contains images from web addresses, those images load from there; turn on Settings → Preview → **Block remote images** to load them only when you click **Load** for a document.

**Is it safe to open Markdown files I received?**
The preview never runs scripts inside documents. Links to executables such as apps or scripts aren't opened, and Mdy asks before opening addresses that launch other apps. For documents in a git repository, git is run so that the repository's settings can't run other commands.

**macOS asks for access to my Documents or Desktop folder.**
The sidebar's file list and folder search read that folder. You can open and edit documents without allowing it.

**Math or diagrams show up as plain text.**
Check that Settings → Preview → **Render math and diagrams** is on. Quick Look (Space in Finder) doesn't run scripts, so it shows the source.

**Diagrams are missing when I export to Word.**
Word can't take the diagram images, so they're left out, and math becomes TeX text. Export as PDF to keep everything as it looks.

## Uninstall

1. Mdy menu → **Quit Mdy**
2. Move Mdy from the Applications folder to the Trash
3. (Optional) To remove settings too, run `defaults delete com.eddieee.Mdy`; templates and the help copy are in `~/Library/Application Support/Mdy`

## Build it yourself

Requires macOS 14 or later and the Xcode Command Line Tools (Xcode itself isn't needed).

```bash
./scripts/test.sh        # self-test
./scripts/build-app.sh   # build/Mdy.app + build/Mdy-<version>.dmg (Apple silicon + Intel)
./build.sh install       # install on this Mac and make it the default app for .md
```

## License

[MIT](LICENSE). The bundled [KaTeX](https://katex.org) and [Mermaid](https://mermaid.js.org) are MIT-licensed too (`Resources/vendor`).

<!-- more-apps:start -->
## More apps

| | App | |
|---|---|---|
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-epp/main/docs/images/icon.png" width="32" alt=""> | [Epp](https://github.com/eddieee-git/mac-app-epp) | Clipboard, menu bar, stickies, timer and capture in one menu bar app |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-gitty/main/docs/images/icon.png" width="32" alt=""> | [Gitty](https://github.com/eddieee-git/mac-app-gitty) | Work with Git repositories like a file manager |
<!-- more-apps:end -->
