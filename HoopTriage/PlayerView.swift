import SwiftUI
import AVKit

/// Playback speed levels for JKL scrubbing
private let speedLevels: [Float] = [1, 2, 4, 8]

/// Expanded video player with JKL scrubbing and keyboard controls
struct PlayerView: View {
    let clip: Clip
    let onRate: (Int) -> Void
    let onTag: (String?) -> Void
    let availableTags: [String]
    let onAddTag: (String) -> Void
    let onClose: () -> Void
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackDirection: Int = 0  // -1 = reverse, 0 = paused, 1 = forward
    @State private var speedIndex: Int = 0  // index into speedLevels
    @State private var currentTime: Double = 0
    @State private var showTagPicker = false
    @State private var newTagText = ""
    @State private var hoveredStar: Int = 0
    @FocusState private var isFocused: Bool
    
    // Timer for reverse playback and time tracking
    @State private var reverseTimer: Timer? = nil
    @State private var timeObserver: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.filename)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(clip.url.deletingLastPathComponent().path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .foregroundColor(.secondary)
                    
                    // Metadata row
                    HStack(spacing: 16) {
                        metaItem(icon: "clock", value: clip.durationFormatted)
                        
                        if clip.width > 0 && clip.height > 0 {
                            metaItem(icon: "rectangle", value: "\(clip.width)×\(clip.height)")
                        }
                        
                        if clip.fileSizeFormatted != nil {
                            metaItem(icon: "doc", value: clip.fileSizeFormatted!)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    
                    // Rating + tag row
                    HStack(spacing: 16) {
                        playerStarRating
                        playerTagButton
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 12) {
                        // Reveal in Finder
                        Button(action: {
                            NSWorkspace.shared.selectFile(clip.url.path, inFileViewerRootedAtPath: clip.url.deletingLastPathComponent().path)
                        }) {
                            Image(systemName: "arrow.right.circle")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                        
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Playback status indicator
                    playbackIndicator
                }
            }
            .padding(20)
            
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .frame(minHeight: 400, maxHeight: 600)
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            
            // Keyboard shortcut hints
            keyboardHints
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
        .focused($isFocused)
        .onKeyPress(.space) { togglePlayPause(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "l")) { _ in handleL(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "j")) { _ in handleJ(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "k")) { _ in handleK(); return .handled }
        .onKeyPress(characters: .init(charactersIn: ",")) { _ in stepFrame(forward: false); return .handled }
        .onKeyPress(characters: .init(charactersIn: ".")) { _ in stepFrame(forward: true); return .handled }
        .onKeyPress(characters: .init(charactersIn: "[")) { _ in jumpTime(by: -5); return .handled }
        .onKeyPress(characters: .init(charactersIn: "]")) { _ in jumpTime(by: 5); return .handled }
        .onKeyPress(characters: .init(charactersIn: "12345")) { press in
            if let digit = Int(String(press.characters)), (1...5).contains(digit) {
                onRate(digit)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "t")) { _ in
            showTagPicker.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            if showTagPicker {
                showTagPicker = false
                return .handled
            }
            onClose()
            return .handled
        }
        .onAppear {
            let p = AVPlayer(url: clip.url)
            player = p
            p.play()
            isPlaying = true
            playbackDirection = 1
            speedIndex = 0
            isFocused = true
            
            // Periodic time observer
            timeObserver = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { time in
                currentTime = CMTimeGetSeconds(time)
            }
        }
        .onDisappear {
            reverseTimer?.invalidate()
            reverseTimer = nil
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            player?.pause()
            player = nil
        }
    }
    
    // MARK: - JKL Scrubbing
    
    /// L key: play forward, accelerate with each press
    private func handleL() {
        stopReversePlayback()
        guard let player = player else { return }
        
        if playbackDirection == 1 {
            // Already going forward — speed up
            speedIndex = min(speedIndex + 1, speedLevels.count - 1)
        } else {
            // Was paused or reverse — start forward at 1x
            playbackDirection = 1
            speedIndex = 0
        }
        
        player.rate = speedLevels[speedIndex]
        isPlaying = true
    }
    
    /// J key: play reverse, accelerate with each press
    private func handleJ() {
        guard let player = player else { return }
        
        if playbackDirection == -1 {
            // Already going reverse — speed up
            speedIndex = min(speedIndex + 1, speedLevels.count - 1)
        } else {
            // Was paused or forward — start reverse at 1x
            player.pause()
            playbackDirection = -1
            speedIndex = 0
        }
        
        // AVPlayer doesn't natively support reverse at arbitrary speeds,
        // so we use a timer-based approach for reverse scrub
        startReversePlayback(speed: speedLevels[speedIndex])
        isPlaying = true
    }
    
    /// K key: pause. If held with J or L, frame step (handled by , and . keys)
    private func handleK() {
        stopReversePlayback()
        player?.pause()
        playbackDirection = 0
        speedIndex = 0
        isPlaying = false
    }
    
    /// Frame step forward or backward
    private func stepFrame(forward: Bool) {
        stopReversePlayback()
        guard let player = player else { return }
        player.pause()
        playbackDirection = 0
        isPlaying = false
        
        // Step by ~1 frame (assuming ~30fps → ~0.033s)
        let frameTime = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        if forward {
            player.seek(to: CMTimeAdd(player.currentTime(), frameTime), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: CMTimeSubtract(player.currentTime(), frameTime), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    /// Jump forward/backward by seconds
    private func jumpTime(by seconds: Double) {
        guard let player = player else { return }
        let target = CMTimeGetSeconds(player.currentTime()) + seconds
        let clamped = max(0, min(target, clip.duration))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Toggle play/pause with Space
    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            handleK()
        } else {
            stopReversePlayback()
            player.play()
            playbackDirection = 1
            speedIndex = 0
            isPlaying = true
        }
    }
    
    // MARK: - Reverse Playback (timer-based)
    
    private func startReversePlayback(speed: Float) {
        reverseTimer?.invalidate()
        guard let player = player else { return }
        
        // Seek backward at intervals to simulate reverse playback
        let interval = 1.0 / 30.0  // ~30fps
        let seekStep = Double(speed) * interval
        
        reverseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let current = CMTimeGetSeconds(player.currentTime())
            let target = max(0, current - seekStep)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if target <= 0 {
                self.stopReversePlayback()
                self.playbackDirection = 0
                self.isPlaying = false
            }
        }
    }
    
    private func stopReversePlayback() {
        reverseTimer?.invalidate()
        reverseTimer = nil
    }
    
    // MARK: - Playback Indicator
    
    private var playbackIndicator: some View {
        Group {
            if playbackDirection != 0 {
                HStack(spacing: 4) {
                    if playbackDirection == -1 {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 10))
                    } else {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                    }
                    Text("\(Int(speedLevels[speedIndex]))×")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(8)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                    Text(formatTime(currentTime))
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Keyboard Hints
    
    private var keyboardHints: some View {
        HStack(spacing: 16) {
            keyHint("J", "Rev")
            keyHint("K", "Pause")
            keyHint("L", "Fwd")
            Divider().frame(height: 14)
            keyHint(",", "← Frame")
            keyHint(".", "Frame →")
            Divider().frame(height: 14)
            keyHint("[", "-5s")
            keyHint("]", "+5s")
            Divider().frame(height: 14)
            keyHint("Space", "Play/Pause")
            keyHint("1-5", "Rate")
            keyHint("T", "Tag")
            keyHint("Esc", "Close")
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.7))
    }
    
    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(3)
            Text(label)
                .font(.system(size: 9))
        }
    }
    
    // MARK: - Star Rating (in player)
    
    private var playerStarRating: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(playerStarColor(for: star))
                    .scaleEffect(hoveredStar == star ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: hoveredStar)
                    .onHover { isOver in
                        hoveredStar = isOver ? star : 0
                    }
                    .onTapGesture {
                        onRate(star)
                    }
            }
            
            // Show keyboard hint
            Text("(1-5)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.leading, 4)
        }
    }
    
    private func playerStarColor(for star: Int) -> Color {
        if hoveredStar > 0 {
            return star <= hoveredStar ? .orange : Color.gray.opacity(0.25)
        }
        return star <= clip.rating ? .yellow : Color.gray.opacity(0.25)
    }
    
    // MARK: - Tag Button (in player)
    
    private var playerTagButton: some View {
        Group {
            if let tag = clip.category {
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tagColor(for: tag))
                    .cornerRadius(10)
                    .onTapGesture { showTagPicker.toggle() }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 12))
                    Text("Add tag (T)")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .onTapGesture { showTagPicker.toggle() }
            }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            playerTagPickerContent
        }
    }
    
    private var playerTagPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button(action: {
                    onTag(clip.category == tag ? nil : tag)
                    showTagPicker = false
                }) {
                    HStack {
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 8, height: 8)
                        Text(tag)
                            .font(.system(size: 12))
                        Spacer()
                        if clip.category == tag {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack(spacing: 4) {
                TextField("New tag...", text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        let tag = newTagText.trimmingCharacters(in: .whitespaces)
                        if !tag.isEmpty {
                            onAddTag(tag)
                            onTag(tag)
                            newTagText = ""
                            showTagPicker = false
                        }
                    }
                
                Button(action: {
                    let tag = newTagText.trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty {
                        onAddTag(tag)
                        onTag(tag)
                        newTagText = ""
                        showTagPicker = false
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            if clip.category != nil {
                Divider()
                Button(action: {
                    onTag(nil)
                    showTagPicker = false
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Remove tag")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(6)
        .frame(width: 180)
    }
    
    // MARK: - Helpers
    
    private func metaItem(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}
