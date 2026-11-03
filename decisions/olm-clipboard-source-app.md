# Olm clipboard source app

Status. A clipboard row shows the icon of the app that was frontmost when the copy landed, and a screenshot is credited to that app rather than to the screenshot tool, on purpose.

## Now

`plugins/clipboard/manager/monitor.lua` stamps every captured entry with the bundle id of the
frontmost application at the poll that saw the change, and the list and the preview pane draw
that app's icon and name. That is right for any copy a person makes inside an app, and wrong
for a screenshot, since neither the native screenshot keys nor macshot come to the front while
they capture. A screenshot taken over Ghostty shows Ghostty. That is accepted, because every
way found to name the real writer is either a clue that holds for one tool or a timing guess,
and a label that is consistently the frontmost app is better than one that is sometimes right.

## Rejected

- 2026-11-03, asking macOS which process wrote the pasteboard. There is no such API. The
  pasteboard carries its data, its types and a change count, nothing about the writer.
- 2026-11-03, a screenshot app list keyed on the frontmost app, so a copy made while a listed
  app was frontmost, or was activated a few seconds before, credits that app. Measured with an
  application watcher across a real macshot or native capture, no application was activated at
  all and Ghostty stayed frontmost throughout, so the list would never match.
- 2026-11-03, a source marker on the pasteboard, the `org.nspasteboard.source` convention.
  macshot's binary names no such type, and the image copy observed carried only `public.png`
  and `public.tiff`.
- 2026-11-03, the native screenshot stamp alone, `<exif:UserComment>Screenshot</exif:UserComment>`
  in the PNG's XMP, credited to `com.apple.screenshot.launcher`, the Screenshot app. A capture
  from `screencapture -c -x` carries it, but the one interactive image copy observed carried no
  stamp, and which tool made it was never settled, so the stamp is not proven for the keys a
  person actually presses. Fixing native alone would also leave macshot and any later tool on
  the old label, two rules for one kind of copy.
- 2026-11-03, inferring the tool from what it is doing at the moment of the copy, a selection
  overlay window on screen or a file landing in its history folder. Not measured. It is a
  timing guess per tool, likely to break on an update of the tool or of macOS, and each new
  tool would need its own signal rather than one line in a list.

## Log

### 2026-11-03 13:54

Milos asked why screenshots in the clipboard list show the Ghostty icon. Found in
`monitor.lua` that the source is the frontmost app. macshot was installed as a cask but had
never launched and was not running, so every capture key had fallen back to the native tool.
Its URL scheme was switched on by writing `urlSchemeEnabled = true` into its defaults domain
and relaunching it, after which the capture provider's own availability check answered true.
A native `screencapture -c -x` left only `public.png`, with the Screenshot stamp in its XMP.
Time anchored to the saved probe image.

### 2026-11-03 14:16

A temporary watcher, an application watcher plus a changeCount poll at a tenth of a second,
ran in Hammerspoon's console state, never in the config. It saw one image copy, types
`public.png` and `public.tiff`, no stamp, Ghostty frontmost, and no activation of any app. Which
tool made it was not confirmed. Milos chose to leave the source as the frontmost app, the
watcher was stopped and removed, and nothing in the plugin changed. Time estimated from the
clock when this file was written.
