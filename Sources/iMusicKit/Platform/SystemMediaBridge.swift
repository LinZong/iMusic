import AVFAudio
import Foundation
import MediaPlayer
import Observation

#if os(macOS)
import AppKit
import CoreAudio
#else
import UIKit
#endif

@MainActor
public final class SystemMediaBridge {
    /// Main-actor playback coordinator controlled by remote commands and system audio events.
    private let playback: PlaybackCoordinator
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// Notification tokens retained for interruption, route-change, and audio-service reset
    /// handling.
    private var observers: [NSObjectProtocol] = []
    /// Whether playback was active before an interruption and may be eligible to resume.
    private var interruptedPlayback = false
    /// Current artwork file name used as the system cover cache key.
    private var artworkHash: String?
    /// Decoded system Now Playing cover reused until its cache key changes.
    private var cachedArtwork: MPMediaItemArtwork?
    /// Registers remote playback commands and audio lifecycle observers, configures the iOS
    /// playback session, and publishes the initial Now Playing snapshot.
    public init(playback: PlaybackCoordinator, vault: MediaVault) {
        self.playback = playback
        self.vault = vault
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak playback] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = event.positionTime
            Task { @MainActor in playback?.seek(to: time) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.skip(seconds: 10) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak playback] _ in
            Task { @MainActor in playback?.skip(seconds: -10) }
            return .success
        }
        playback.onSnapshot = { [weak self] in self?.publish() }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch { playback.report(error) }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                let options = AVAudioSession.InterruptionOptions(
                    rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                )
                Task { @MainActor in
                    guard let self else { return }
                    if type == .began {
                        self.interruptedPlayback = self.playback.saveAndPauseForInterruption()
                    } else if type == .ended {
                        self.playback.resumeAfterInterruption(
                            allowed: self.interruptedPlayback && options.contains(.shouldResume)
                        )
                        self.interruptedPlayback = false
                    }
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let previous =
                    note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                    as? AVAudioSessionRouteDescription
                let removedHeadphones =
                    previous?.outputs
                    .contains { [.headphones, .bluetoothA2DP, .bluetoothLE].contains($0.portType) }
                    ?? false
                Task { @MainActor in
                    guard let self else { return }
                    if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        && removedHeadphones
                    {
                        self.playback.pause()
                    }
                    self.updateRoute()
                    self.playback.persist()
                    self.publish()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    do {
                        try AVAudioSession.sharedInstance()
                            .setCategory(.playback, mode: .default, policy: .longFormAudio)
                    } catch { self.playback.report(error) }
                    self.playback.recoverAudioService()
                }
            }
        )
        #else
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.updateRoute() }
        }
        #endif
        updateRoute()
        publish()
    }
    /// Publishes current metadata, validated elapsed time, artwork, and playback rate to Now
    /// Playing, and enables remote seeking only when supported.
    public func publish() {
        guard let track = playback.track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if artworkHash != track.artworkName {
            artworkHash = track.artworkName
            cachedArtwork = nil
            if let url = vault.artworkURL(track.artworkName), let data = try? Data(contentsOf: url)
            {
                #if os(macOS)
                if let image = NSImage(data: data) {
                    cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
                #else
                if let image = UIImage(data: data) {
                    cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
                #endif
            }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.timeline.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? playback.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playback.rate,
        ]
        if let duration = playback.timeline.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = cachedArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = playback.canSeek
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = playback.isPlaying ? .playing : .paused
        #endif
    }
    private func updateRoute() {
        #if os(iOS)
        playback.routeName = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName)
            .joined(separator: "、")
        #else
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr {
            var name: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            address.mSelector = kAudioObjectPropertyName
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name
            {
                playback.routeName = name.takeRetainedValue() as String
            }
        }
        #endif
    }
}
