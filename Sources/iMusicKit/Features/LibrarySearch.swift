import SwiftUI

enum LibrarySearch {
    static func isEmpty(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func matches(_ query: String, in values: [String]) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).searchKey
        return normalized.isEmpty || values.contains { $0.searchKey.contains(normalized) }
    }

    static func matches(_ query: String, track: Track) -> Bool {
        matches(query, in: [track.title, track.artist, track.album, track.albumArtist, track.originalFilename, track.genre])
    }
}

extension View {
    @ViewBuilder func librarySearch(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        #else
        searchable(text: text, prompt: Text(prompt))
        #endif
    }
}
