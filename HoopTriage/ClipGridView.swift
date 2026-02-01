import SwiftUI

/// Grouping mode
enum GroupMode: String, CaseIterable {
    case none = "No Grouping"
    case rating = "By Rating"
    case category = "By Tag"
}

/// The main grid of clip thumbnails
struct ClipGridView: View {
    @ObservedObject var store: ClipStore
    let audioEnabled: Bool
    @State private var expandedClip: Clip? = nil
    @State private var selectedClipID: UUID? = nil
    @FocusState private var isGridFocused: Bool
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: store.gridColumns)
    }
    
    /// The flat list of clips currently displayed (for keyboard navigation indexing)
    private var displayedClips: [Clip] {
        store.sortedAndFilteredClips
    }
    
    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    if store.groupMode == .none {
                        flatGrid
                    } else {
                        groupedGrid
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .onEnded { value in
                            if value.magnification > 1.2 {
                                store.gridColumns = max(1, store.gridColumns - 1)
                            } else if value.magnification < 0.8 {
                                store.gridColumns = min(5, store.gridColumns + 1)
                            }
                        }
                )
                .onChange(of: selectedClipID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .focused($isGridFocused)
            
            // Expanded player overlay
            if let clip = expandedClip {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { expandedClip = nil }
                
                PlayerView(
                    clip: clip,
                    onRate: { rating in store.setRating(rating, for: clip.id) },
                    onTag: { tag in store.setCategory(tag, for: clip.id) },
                    availableTags: store.availableTags,
                    onAddTag: { tag in store.addTag(tag) }
                ) {
                    expandedClip = nil
                    isGridFocused = true
                }
                .frame(maxWidth: 1000, maxHeight: 700)
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedClip?.id)
        .animation(.easeInOut(duration: 0.15), value: store.gridColumns)
        .onKeyPress(.upArrow) { navigateClip(by: -store.gridColumns); return .handled }
        .onKeyPress(.downArrow) { navigateClip(by: store.gridColumns); return .handled }
        .onKeyPress(.leftArrow) { navigateClip(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigateClip(by: 1); return .handled }
        .onKeyPress(.return) {
            if expandedClip == nil, let id = selectedClipID,
               let clip = displayedClips.first(where: { $0.id == id }) {
                expandedClip = clip
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if expandedClip != nil {
                expandedClip = nil
                isGridFocused = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init("12345")) { press in
            guard expandedClip == nil else { return .ignored }
            if let digit = Int(String(press.characters)), (1...5).contains(digit),
               let id = selectedClipID {
                store.setRating(digit, for: id)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init("t")) { press in
            guard expandedClip == nil else { return .ignored }
            if let id = selectedClipID {
                store.showTagPickerForClipID = id
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            guard expandedClip == nil else { return .ignored }
            if let id = selectedClipID {
                removeSelectedClip(id: id)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.deleteForward) {
            guard expandedClip == nil else { return .ignored }
            if let id = selectedClipID {
                removeSelectedClip(id: id)
                return .handled
            }
            return .ignored
        }
        .onAppear {
            isGridFocused = true
            if selectedClipID == nil, let first = displayedClips.first {
                selectedClipID = first.id
            }
        }
    }
    
    // MARK: - Keyboard Navigation
    
    /// Remove clip and move selection to the next one
    private func removeSelectedClip(id: UUID) {
        let clips = displayedClips
        if let currentIndex = clips.firstIndex(where: { $0.id == id }) {
            // Move selection to next clip (or previous if at end)
            if clips.count > 1 {
                let nextIndex = currentIndex < clips.count - 1 ? currentIndex + 1 : currentIndex - 1
                selectedClipID = clips[nextIndex].id
            } else {
                selectedClipID = nil
            }
        }
        store.removeClip(id: id)
    }
    
    private func navigateClip(by offset: Int) {
        let clips = displayedClips
        guard !clips.isEmpty else { return }
        
        if let currentID = selectedClipID,
           let currentIndex = clips.firstIndex(where: { $0.id == currentID }) {
            let newIndex = max(0, min(clips.count - 1, currentIndex + offset))
            selectedClipID = clips[newIndex].id
        } else {
            selectedClipID = clips.first?.id
        }
    }
    
    // MARK: - Flat Grid
    
    private var flatGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(store.sortedAndFilteredClips) { clip in
                clipCard(clip)
            }
        }
        .padding(12)
    }
    
    // MARK: - Grouped Grid
    
    private var groupedGrid: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(groupedSections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    // Section header
                    HStack(spacing: 8) {
                        if store.groupMode == .rating {
                            ratingHeader(section.title)
                        } else {
                            Text(section.title)
                                .font(.headline)
                        }
                        
                        Text("\(section.clips.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    
                    // Clips in this section
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(section.clips) { clip in
                            clipCard(clip)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
    
    private func ratingHeader(_ title: String) -> some View {
        let scoreColors: [String: Color] = [
            "★★★★★": Color(red: 0.133, green: 0.773, blue: 0.369),
            "★★★★☆": Color(red: 0.518, green: 0.800, blue: 0.086),
            "★★★☆☆": Color(red: 0.918, green: 0.702, blue: 0.031),
            "★★☆☆☆": Color(red: 0.976, green: 0.451, blue: 0.086),
            "★☆☆☆☆": Color(red: 0.937, green: 0.267, blue: 0.267),
        ]
        let color = scoreColors[title] ?? .secondary
        
        return Text(title)
            .font(.headline)
            .foregroundColor(color)
    }
    
    // MARK: - Grouped Sections
    
    private struct ClipSection: Identifiable {
        let title: String
        let clips: [Clip]
        var id: String { title }
    }
    
    private var groupedSections: [ClipSection] {
        let clips = store.sortedAndFilteredClips
        
        switch store.groupMode {
        case .none:
            return [ClipSection(title: "All", clips: clips)]
            
        case .rating:
            var groups: [Int: [Clip]] = [:]
            for clip in clips {
                groups[clip.rating, default: []].append(clip)
            }
            return (0...5).reversed().compactMap { rating in
                guard let clipsInGroup = groups[rating], !clipsInGroup.isEmpty else { return nil }
                let title = rating == 0 ? "Unrated" : String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
                return ClipSection(title: title, clips: clipsInGroup)
            }
            
        case .category:
            var groups: [String: [Clip]] = [:]
            for clip in clips {
                let key = clip.category ?? "Untagged"
                groups[key, default: []].append(clip)
            }
            // Sort: tagged groups first (alphabetical), untagged last
            let sorted = groups.sorted { a, b in
                if a.key == "Untagged" { return false }
                if b.key == "Untagged" { return true }
                return a.key < b.key
            }
            return sorted.map { ClipSection(title: $0.key, clips: $0.value) }
        }
    }
    
    // MARK: - Clip Card
    
    private func clipCard(_ clip: Clip) -> some View {
        ClipThumbnailView(
            clip: clip,
            isSelected: selectedClipID == clip.id,
            showTagPickerBinding: Binding(
                get: { store.showTagPickerForClipID == clip.id },
                set: { if !$0 { store.showTagPickerForClipID = nil } }
            ),
            thumbnailGenerator: store.thumbnailGenerator,
            availableTags: store.availableTags,
            audioEnabled: audioEnabled,
            onRate: { rating in
                store.setRating(rating, for: clip.id)
            },
            onTag: { tag in
                store.setCategory(tag, for: clip.id)
            },
            onAddTag: { tag in
                store.addTag(tag)
            },
            onSelect: {
                selectedClipID = clip.id
            },
            onOpen: {
                selectedClipID = clip.id
                expandedClip = clip
            }
        )
        .id(clip.id)
    }
}
