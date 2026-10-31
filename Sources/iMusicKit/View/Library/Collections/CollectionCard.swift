import SwiftUI

/// Shared artwork and text layout for collection navigation cards.
struct CollectionCard: View {
    /// Primary localized or user-provided collection title.
    let title: String
    /// Secondary collection description or count.
    let subtitle: String
    /// Representative track or custom playlist artwork placeholder.
    let track: Track?
    /// Managed artwork storage.
    let vault: MediaVault
    /// Renders one collection's visual summary.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(track: track, vault: vault, size: 144)
            Text(title).font(.headline).lineLimit(2)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

    }
}
