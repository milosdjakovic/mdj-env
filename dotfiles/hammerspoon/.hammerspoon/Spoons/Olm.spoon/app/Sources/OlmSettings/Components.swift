// The parts every page of Olm Settings is built from, so a row, a page and the way between them look
// and behave alike wherever they appear. docs/DESIGN-APP-SETTINGS.md, under Parts, states the rules,
// asked by Milos on 2026-11-24. A page needing something these do not cover adds a part here and to
// that list, never a one off in its own file.
//
// A row's right group is always, in this order, the undo, then the gear when the row has a page of
// its own, then the control, each in a column that keeps its place when its part is hidden.

import SwiftUI

/// Undo, the first of a row's actions on the right. Puts the row back to the value in the config
/// files, or takes off what this window set. Kept in place while hidden, so it appearing moves
/// nothing.
struct UndoButton: View {
  let shown: Bool
  var help: String = "Back to the value in the config files"
  let action: () -> Void

  var body: some View {
    Button(action: action) { Image(systemName: "arrow.uturn.backward").frame(width: Space.mark) }
      .buttonStyle(.borderless)
      .help(help)
      .opacity(shown ? 1 : 0)
      .disabled(!shown)
  }
}

/// The gear, after the undo and before the control, opening the row's own page inside the window,
/// a plugin's settings or an application's. Drawn in the accent when that page holds anything set,
/// the rule every set value follows.
struct PageButton: View {
  let set: Bool
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "gearshape")
        .foregroundStyle(set ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: Space.mark)
    }
    .buttonStyle(.borderless)
    .help(help)
  }
}

/// Back, at the top left of a page a gear opened, naming the page it returns to, a glass button as
/// the system draws one, asked by Milos on 2026-11-24, the bordered one before macOS 26.
struct BackButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    if #available(macOS 26, *) {
      button.buttonStyle(.glass)
    } else {
      button.buttonStyle(.bordered)
    }
  }

  private var button: some View {
    Button(action: action) { Label(title, systemImage: "chevron.left") }
      .help("Back to \(title)")
  }
}

/// A page's header, its picture in a glass circle, its title and the line under it, and the note
/// at its right when there is something to say. The height is fixed, so the note coming and going
/// moves nothing.
struct PageHeader<Picture: View>: View {
  let title: String
  let subtitle: String
  var note: (text: String, symbol: String)? = nil
  @ViewBuilder let picture: Picture

  var body: some View {
    HStack(spacing: Space.pad + 4) {
      picture
        .frame(width: SectionPage.header, height: SectionPage.header)
        .glassCircle()
      VStack(alignment: .leading, spacing: Space.row) {
        Text(title).font(.largeTitle.weight(.semibold))
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.group)
      if let note, !note.text.isEmpty { Note(text: note.text, symbol: note.symbol) }
    }
    .frame(height: SectionPage.header)
  }
}

/// A section's symbol as a header's picture.
struct SectionSymbol: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      // look-exempt, the section's picture in its glass circle, sized as System Settings does.
      .font(.system(size: 26, weight: .medium))
      .foregroundStyle(.tint)
  }
}
