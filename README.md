# Stickies

Sticky notes for iOS and macOS that live as plain markdown files in a folder
you choose — so you can put that folder in iCloud Drive, Dropbox or Google
Drive and have the same stickies on every device. Pin any note to your Home
Screen, desktop or Lock Screen with a widget.

<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon-mac-256x256@1x.png" width="128" alt="Stickies app icon">
</p>

## What it does

- **Notes are files.** One `.md` file per sticky, in a folder you pick. Edit
  them in Stickies, in Obsidian, in TextEdit, or over SSH — the app keeps up.
- **Always in sync with the folder.** A directory watch catches local edits
  immediately; a background poll catches files that a cloud service
  materialises without an event. Nothing is cached as the source of truth.
- **Write it, set it, see it.** The editor is a text box, the options that
  apply to the whole sticky, and live previews of all three widget sizes
  underneath — so the question "will that fit on the small one?" is answered
  while you're still typing. The sidebar is the same preview at small-widget
  size: a board of the widgets themselves rather than a list of titles.
- **Markdown, rendered.** Headings, `**bold**`, `*italic*`, `~~strike~~`,
  `` `code` ``, `[links](…)`, `<u>underline</u>`, bullets, numbered lists, task
  lists, quotes and rules — in the app *and* in the widgets, from one parser
  they both use.
- **Per-note formatting.** Text size, horizontal and vertical alignment, and
  bold / italic / underline across the whole note — the settings markdown has
  no syntax for. They're stored in the file, so the widget sets the note
  exactly the way the editor did.
- **A countdown, in the sentence.** Give a note a date and write
  `{{countdown}}` wherever the time left belongs: *"Ship in {{countdown}}"*.
  Choose which fields it shows — months, weeks, days, hours, minutes, seconds —
  and whether it reads as words, compact, or digits.
- **400 characters.** Enough for a real note, short enough to stay legible in
  a widget. Longer files that arrive from elsewhere are shown and flagged, not
  truncated.
- **Six classic sticky colours**, stored in the file so they travel with it.

### Widgets

| Widget | Sizes | What it shows |
| --- | --- | --- |
| **Sticky Note** | small, medium, large (+ extra large on macOS) | One note, filling the widget |
| **Two Stickies** | small, medium, large (+ extra large on macOS) | Two notes stacked with a gap, at a smaller text size |
| **Sticky on the Lock Screen** *(iOS)* | inline, rectangular | One note, shrunk until as much text as possible fits |

Each widget is configured by long-pressing it and choosing **Edit Widget**,
then picking which sticky it should show. Everything else about how it looks —
colour, text size, alignment, emphasis, any countdown — belongs to the note, so
changing it in the app changes every widget showing that note at once.

The Lock Screen widget renders in the system's single-tint mode, so sticky
colour is deliberately dropped there and the space goes to text instead. The
inline family is the strip directly above the clock; the rectangular family is
the larger slot below it.

## Building it

Requirements: **Xcode 15 or later**, iOS 17+, macOS 14+.

**The project does not build as checked out.** The placeholder identifiers are
examples; bundle IDs are unique across every Apple developer account, and the
obvious ones are taken. Step 2 is mandatory.

1. Open `Stickies.xcodeproj`.
2. Open `Config/Base.xcconfig` and replace the placeholders:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   APP_BUNDLE_ID    = com.yourname.iosstickies
   APP_GROUP_ID     = group.com.yourname.iosstickies
   ```

   Change the bundle identifier **here and nowhere else**. The widget's
   identifier is derived from it, and the two have to stay in step; typing a
   new one into Xcode's Signing & Capabilities pane writes a per-target
   override that renames the app but not the widget.

   `APP_BUNDLE_ID` doesn't need to be a domain you own, but it does have to be
   unique across all of Apple's developer accounts — put your own name in it.
   `APP_GROUP_ID` must start with `group.`. To keep your identifiers out of git,
   put the same settings in `Config/Local.xcconfig` instead; it's ignored by git
   and included last, so it wins.
3. Register the App Group (see below).
4. Pick the **Stickies** scheme and run on an iOS or macOS destination.

Everything else — both bundle identifiers, both platforms' entitlements, the
widget extension's Info.plist — is derived from those values, so there is
nothing else to keep in sync.

### Registering the App Group

The App Group is how the widget extension finds the folder bookmark and the
cached note list. Without it the app itself works fine and every widget comes up
blank — Settings ▸ Widgets tells you whether the group is resolving.

Easiest path, per target (**Stickies** *and* **StickiesWidgets**):

1. Select the target ▸ **Signing & Capabilities**.
2. The **App Groups** section is already there, populated from the entitlements
   file. Tick your group, or hit the refresh arrow if Xcode shows it as
   unregistered — Xcode will create it and add it to both App IDs.

If Xcode won't do it, create it by hand at
[developer.apple.com ▸ Identifiers ▸ App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup),
then enable the **App Groups** capability on both the `com.yourname.stickies`
and `com.yourname.stickies.widgets` App IDs and select the group in each.

> **Never put your team ID in the App Group entitlement**, on either platform.
> Apple's portal stores a group's identifier without the prefix (it keeps the
> prefix in a separate field) and rejects anything not starting with `group.`.
> A team-prefixed literal in an entitlements file makes Xcode try to register a
> group under that name and fail with *"Application Group identifiers should
> start with 'group.'"* — and because one multiplatform target gets a single
> `UNIVERSAL` App ID, a macOS-only entitlement leaks into iOS builds too.
>
> macOS does still keep its group container under `~/Library/Group
> Containers/<team>.<group>`. `AppGroup.swift` handles that at runtime: the
> team ID reaches the app through Info.plist, and the container lookup tries
> the bare identifier first, then the prefixed one. Nothing to configure.

### If the build fails

| Error | Cause |
| --- | --- |
| `The app identifier "com.example.stickies" cannot be registered to your development team` | Step 2 wasn't done. `com.example.*` can't be registered by anyone. |
| `No profiles for 'com.example.stickies' were found` | Same cause — the App ID doesn't exist, so there's nothing to make a profile from. |
| `Provisioning profile … doesn't support the ….group.… App Group` | The App Group isn't registered, or isn't enabled on that target's App ID. It has to be on **both** the app and the widget. |
| `Communication with Apple failed. (Application Group identifiers should start with 'group.')` | Something put a team-prefixed identifier in an entitlements file. `APP_GROUP_ID` must be the bare `group.…` form — see the note above. |
| `Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier` | The app's identifier was changed somewhere that doesn't feed the widget's. Set `APP_BUNDLE_ID` in the xcconfig, then check the app target's Build Settings for a bold (overridden) **Product Bundle Identifier** and delete it so it reads `$(APP_BUNDLE_ID)` again. |
| `Disabling hardened runtime with ad-hoc codesigning` | Only a note, not an error. It appears on macOS when no team is set yet. |

Xcode registers identifiers on your account as it goes, so a failed attempt can
leave a stale bundle ID or App Group behind. They're harmless, but you can tidy
them up under [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
once you're building.

None of this is about the name **Stickies** — it isn't reserved, and the target
name doesn't collide with the Stickies app that ships with macOS (that one is
`com.apple.Stickies`). If you'd rather not share the name anyway, set
`APP_DISPLAY_NAME` in the xcconfig; it changes the name under the icon without
touching the project.

## How a note is stored

A note is just markdown. Anything Stickies adds goes in optional front matter,
so a file written by hand is a perfectly valid sticky:

```markdown
---
color: yellow
created: 2026-08-25T09:41:00Z
---
# Milk
- oat
- **not** skim
```

- `color` — one of `yellow`, `pink`, `blue`, `green`, `orange`, `purple`.
  Missing? A colour is derived from the file name, stably.
- `created` — ISO 8601. Missing? The file's creation date is used.
- `size` — `x-small`, `small`, `medium`, `large`, `x-large`. It's a multiplier,
  not a point size, so the same note still reads correctly at every widget size.
- `align` — `left`, `center`, `right`.
- `valign` — `top`, `middle`, `bottom`. Where the text sits on the paper.
- `style` — any of `bold`, `italic`, `underline`, comma separated. This is on
  top of the note's markdown, never instead of it.
- `countdown` — the date `{{countdown}}` counts to. Written with the local
  offset; a bare `2026-12-25` typed in by hand is read too.
- `countdown-units` — which fields show, from `years`, `months`, `weeks`,
  `days`, `hours`, `minutes`, `seconds`. Default: `days, hours, minutes`.
- `countdown-style` — `full` (*2 days, 4 hours*), `short` (*2d 4h*) or `digits`
  (*2:04*).
- Only settings that differ from the default are written, so a note nobody has
  restyled stays exactly as plain as it was.
- Front matter keys Stickies doesn't recognise are preserved on save, so other
  tools can annotate the same files. So is a key Stickies *does* recognise but
  can't parse — a `size: enormous` stays in the file rather than being dropped.
- The note's **title** is its first meaningful line, with markdown stripped.
- `.md`, `.markdown`, `.txt`, `.text` and `.mdown` files are all picked up.
  Sub-folders are ignored — a board is one flat folder.

A new note's file is named after its first line the first time you type one,
and never renamed behind your back after that. Renaming is explicit, under
**Rename File…**.

### Countdowns

`{{countdown}}`, anywhere in a note, becomes the time between now and the
note's `countdown` date — in a heading, mid-sentence, or on a line of its own:

```markdown
---
color: pink
countdown: 2026-12-25T09:00:00+01:00
countdown-units: weeks, days
---
# Christmas
{{countdown}} to go
```

- A single tag can override the note's own settings, for itself only:
  `{{countdown days}}`, `{{countdown: hours, minutes}}`, `{{countdown short}}`.
- Leading zero fields are dropped — *3 days, 0 hours* reads as *3 days* — and
  the smallest field always survives, so a finished countdown says *0 minutes*
  rather than nothing.
- Once the date has passed the same fields count up instead: *2 days ago*.
- A `{{countdown}}` in a note with no date shows an em dash. Braces that aren't
  a tag Stickies knows are left exactly as typed.

## How it fits together

```
Config/Base.xcconfig     Team, bundle ID and App Group — the only things to edit

Shared/                  Compiled into both the app and the widget extension
  Model/                 Note, sticky palette, per-note formatting, the
                         countdown and its tags, the file format
  Storage/               Folder bookmark, coordinated file IO, folder watcher,
                         widget snapshot cache, the app's observable store
  Markdown/              Block parser, inline parser, and their renderer
  UI/                    The sticky itself, and the widget-sized preview of it
                         — used by widgets, by the sidebar and by the editor,
                         so they can't drift apart

App/                     SwiftUI app: onboarding, list, editor, settings
Widgets/                 Widget bundle, AppIntents note picker, three widgets
Tools/                   Project and icon generators
```

Two details worth knowing:

- **One markdown renderer.** Inline emphasis is parsed into spans that carry
  concrete fonts rather than `AttributedString` presentation intents, which a
  `.font()` modifier downstream would flatten. Every sticky sets its own font
  size, so spans are the only way the app and the widgets can agree. A note's
  own bold / italic / underline is merged into every span as it's resolved,
  which is why *set the note in bold* and `**bold**` compose instead of
  cancelling out.
- **Previews are the widget, scaled.** A preview is laid out at the real
  widget's point size and then scaled as one piece, rather than being squeezed
  into a smaller box with the type left where it was. It has to be: the whole
  point of the preview is how much of the note fits.
- **File access.** The folder is reached through a security-scoped bookmark
  stored in the App Group. Every read and write goes through `NSFileCoordinator`
  so a cloud provider writing from another device and the app reading take
  turns rather than colliding.
- **Widgets read the folder first**, and fall back to a JSON snapshot the app
  leaves in the App Group container. That fallback is what keeps widgets
  populated when the extension can't resolve the bookmark itself or the cloud
  files aren't downloaded yet.

### Regenerating the project

`Stickies.xcodeproj` is generated and committed. After adding, removing or
moving files:

```sh
python3 Tools/generate_xcodeproj.py
```

Object IDs are hashes of each object's role, so an unchanged project
regenerates byte-identically. The app icon is generated too — `python3
Tools/generate_icons.py` redraws it after a palette change. Neither script
needs any third-party packages.

## Known limits

- A widget remembers a note by file name. Rename a file outside the app and
  the widget falls back to matching on title; if that fails too, the widget
  says so and asks you to pick the note again.
- Widgets refresh when you edit a sticky on that device, and roughly every 15
  minutes otherwise. A change made on another device appears at the next
  refresh, not instantly — that's a WidgetKit budget, not a choice.
- Two devices editing the same note at the same moment is last-write-wins at
  the file level. The app detects a file changing underneath an open editor
  and asks which version you want rather than silently picking one.
- A countdown in a widget is drawn in advance: the extension isn't running when
  the number changes, so a countdown down to minutes ships an hour of
  minute-by-minute entries at a time. A countdown showing **seconds** is
  rendered but not ticked — WidgetKit won't wake anything that often, so on a
  widget it moves once a minute. In the app it moves every second.
- The Lock Screen sticky keeps the note's emphasis and alignment but not its
  text size: that widget's job is shrinking the note until it fits a slot it
  can't grow.
