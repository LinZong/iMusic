import SwiftUI

struct PlayerControlButton: View {
  /// Familiar SF Symbol representing the action or its current playback state.
  let symbol: String
  /// Localized action description shared by VoiceOver and pointer tooltips.
  let label: String
  /// Visual symbol size in points, independent of the minimum interactive target.
  var symbolSize: CGFloat = 19
  /// Square hit-region edge length in points; never rendered smaller than 44 points.
  var targetSize: CGFloat = 44
  /// Whether a persistent mode is active and needs a selected background and accessibility trait.
  var isSelected = false
  /// Whether this is a primary transport action rather than a secondary utility action.
  var isProminent = false
  /// Existing playback or library action invoked by the control.
  let action: () -> Void
  /// Renders the symbol and selected state without introducing an always-filled play/pause button.
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: symbolSize, weight: .semibold))
        .foregroundStyle(
          isSelected ? Color.accentColor : isProminent ? Color.primary : Color.secondary
        )
        .frame(width: max(44, targetSize), height: max(44, targetSize))
        .background(
          isSelected ? Color.accentColor.opacity(0.12) : .clear,
          in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(PlayerControlStyle())
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .help(label)
  }
}
