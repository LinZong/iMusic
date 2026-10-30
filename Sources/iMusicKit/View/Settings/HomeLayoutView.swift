import SwiftUI

struct HomeLayoutView: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @Bindable var model: PreferencesViewModel
  /// Renders home-section visibility and ordering controls backed by persistent preferences.
  var body: some View {
    List {
      ForEach($model.homeSections) { $section in
        HStack {
          Toggle(section.title, isOn: $section.enabled)
          #if os(macOS)
            Button {
              move(section.id, delta: -1)
            } label: {
              Image(systemName: "chevron.up")
            }.buttonStyle(.borderless)
            Button {
              move(section.id, delta: 1)
            } label: {
              Image(systemName: "chevron.down")
            }.buttonStyle(.borderless)
          #endif
        }
      }.onMove { model.homeSections.move(fromOffsets: $0, toOffset: $1) }
      Button(L10n.text("Restore Default Layout")) {
        model.homeSections = HomeSectionOption.defaults
      }
    }.navigationTitle(L10n.text("Customize Home"))
      #if os(iOS)
        .toolbar { EditButton() }
      #endif
  }
  private func move(_ id: String, delta: Int) {
    guard let index = model.homeSections.firstIndex(where: { $0.id == id }),
      model.homeSections.indices.contains(index + delta)
    else { return }
    model.homeSections.swapAt(index, index + delta)
  }
}
