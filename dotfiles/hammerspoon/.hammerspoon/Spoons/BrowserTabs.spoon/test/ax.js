// The outside witness. It reads which application is frontmost and which window of a named
// application the accessibility layer has in front, through System Events, in a process that is
// not Hammerspoon and does not use Hammerspoon's window bindings.
//
// This independence is the whole point. The tool under test writes to the accessibility layer and
// also reads it back through the same bindings it wrote with, so asking Hammerspoon whether the
// right window is focused lets one mistaken assumption answer for both. System Events is a
// separate reader with a separate implementation.
//
// It reports position and size rather than only a title. Titles are decorated differently by each
// browser, repeat across windows showing the same page, and change under you when a page finishes
// loading. A frame is a number, it belongs to exactly one window, and matching it against the
// frame the browser reports for the window holding the selected tab is what actually proves the
// two layers are talking about the same window.
//
// Called as osascript -l JavaScript ax.js <processName> answering one JSON object.

function run(argv) {
  const se = Application("System Events");
  const out = { ok: true, front: null, window: null, windows: [] };

  try {
    const proc = se.applicationProcesses.whose({ frontmost: true })[0];
    out.front = { name: proc.name(), bundleID: proc.bundleIdentifier() };
  } catch (e) {
    out.front = null;
  }

  const want = argv[0];
  if (!want) return JSON.stringify(out);

  let proc = null;
  try { proc = se.applicationProcesses.byName(want); proc.name(); } catch (e) { proc = null; }
  if (!proc) return JSON.stringify(out);

  // System Events orders a process's windows front to back, so windows[0] is that process's
  // frontmost window whether or not the process itself is frontmost. Every window is reported as
  // well, since some cases need to know a window exists and is not the one in front.
  try {
    const wins = proc.windows;
    for (let i = 0; i < wins.length; i++) {
      const w = { index: i + 1, name: null, position: null, size: null, subrole: null };
      try { w.name = wins[i].name(); } catch (e) {}
      try { const p = wins[i].position(); w.position = { x: p[0], y: p[1] }; } catch (e) {}
      try { const s = wins[i].size(); w.size = { w: s[0], h: s[1] }; } catch (e) {}
      try { w.subrole = wins[i].subrole(); } catch (e) {}
      out.windows.push(w);
    }
    // The front window is the first ordinary one, not simply the first. Chrome in full screen puts
    // an extra accessibility window in front of its content, the auto hiding toolbar, which has no
    // name and is the width of the screen by thirty three points tall. Taking it as the front
    // window made a round where the tool had done everything right read as the two layers
    // disagreeing. Anything that is not a standard window is recorded but never chosen.
    for (let i = 0; i < out.windows.length; i++) {
      if (out.windows[i].subrole === "AXStandardWindow") { out.window = out.windows[i]; break; }
    }
    if (!out.window && out.windows.length > 0) out.window = out.windows[0];
  } catch (e) {}

  return JSON.stringify(out);
}
