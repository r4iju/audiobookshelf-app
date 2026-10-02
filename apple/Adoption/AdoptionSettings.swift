import Foundation

/// Legacy preferences become native ones only where this app has none yet; values without a
/// native equivalent, or out of the native range, stay in the outcome and are listed as retained.
///
/// Only the network policies reach running services here: written to the standard defaults, they
/// are announced through `AppleNetworkPolicy.changed`, as the settings screen does, so downloads
/// and playback re-check their consent. Services that read other keys once at launch do not see
/// the new values until the app sets them (see `APPLE-MIGRATION-ADOPTION.md`).
extension NativeMigrationAdoption {
    /// The native EPUB reader's stored preferences (`EPUBReader.swift`), all nine keys.
    private struct EPUBPreferences: Codable {
        var theme = "dark"
        var font = "serif"
        var scale = 100.0
        var spacing = 160.0
        var stroke = 0.0
        var spread = "auto"
        var keepAwake = false
        var volume = "enabled"
        var volumeWhileListening = false
    }

    func applySettings(_ settings: MigratedSettings) -> AdoptionReport.Settings {
        var result = AdoptionReport.Settings()
        func offer(_ key: String, _ value: Any?, legacy: String, alsoSetBy older: String? = nil) {
            guard let value else { result.retained.append(legacy); return }
            if defaults.object(forKey: key) != nil || older.map({ defaults.object(forKey: $0) != nil }) == true {
                result.keptNative.append(key)
                return
            }
            defaults.set(value, forKey: key)
            result.applied.append(key)
            // `AppleNetworkPolicy` reads the standard defaults; other defaults reach no running service.
            if [AppleNetworkPolicy.downloadsKey, AppleNetworkPolicy.streamingKey].contains(key), defaults === UserDefaults.standard {
                NotificationCenter.default.post(name: AppleNetworkPolicy.changed, object: key)
            }
        }
        func option(_ raw: String, _ allowed: Set<String>) -> String? {
            let value = raw.lowercased()
            return allowed.contains(value) ? value : nil
        }
        let intervals: Set<Int> = [5, 10, 15, 30, 45, 60]
        let networks: Set<String> = ["ask", "always", "never"]

        if let device = settings.device {
            offer("previewSkipForward", intervals.contains(device.jumpForwardTime) ? device.jumpForwardTime : nil, legacy: "jumpForwardTime")
            offer("previewSkipBackward", intervals.contains(device.jumpBackwardsTime) ? device.jumpBackwardsTime : nil, legacy: "jumpBackwardsTime")
            offer("previewHaptic", option(device.hapticFeedback, ["off", "light", "medium", "heavy"]), legacy: "hapticFeedback")
            offer(AppleNetworkPolicy.downloadsKey, option(device.downloadUsingCellular, networks), legacy: "downloadUsingCellular", alsoSetBy: "previewDownloadCellular")
            offer(AppleNetworkPolicy.streamingKey, option(device.streamingUsingCellular, networks), legacy: "streamingUsingCellular")
            offer("previewResumeRewind", !device.disableAutoRewind, legacy: "disableAutoRewind")
            offer("previewMediaSeeking", device.allowSeekingOnMediaControls, legacy: "allowSeekingOnMediaControls")
            offer("previewSleepFade", !device.disableSleepTimerFadeOut, legacy: "disableSleepTimerFadeOut")
            // `languageCode` waits for the native language setting (`previewLanguage`).
            result.retained += ["languageCode", "lockOrientation", "enableAltView"]
        }
        if let player = settings.player {
            offer("previewPlaybackSpeed", player.playbackRate.isFinite && (0.5...10).contains(player.playbackRate) ? player.playbackRate : nil, legacy: "playbackRate")
        }
        let (display, unusedDisplay) = playerDisplay(settings)
        result.retained += unusedDisplay
        for choice in display { offer(choice.key, choice.value, legacy: choice.legacy) }
        for (key, value) in settings.preferences.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "playerSettings": continue
            case "theme": offer("previewTheme", option(value, ["system", "light", "dark", "black"]), legacy: key)
            case "bookshelfListView":
                let list: Bool? = ["1", "true"].contains(value.lowercased()) ? true : ["0", "false"].contains(value.lowercased()) ? false : nil
                offer("previewListLayout", list, legacy: key)
            default: result.retained.append(key)
            }
        }
        for (key, value) in settings.webStorage.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "ereaderSettings":
                let (preferences, unused) = readerPreferences(value)
                result.retained += unused
                offer("previewEPUBPreferences", preferences, legacy: key)
            case "absDeviceId": offer("nativeDeviceID", value.isEmpty ? nil : value, legacy: key)
            default: result.retained.append(key)
            }
        }
        return result
    }

    /// The legacy player's display choices (`components/app/AudioPlayer.vue`). Its `playerSettings`
    /// JSON is what the user chose in the player; the Realm `chapterTrack` is only the copy it
    /// handed to the iOS player and is used when the JSON has no valid choice. Only booleans are
    /// used, and never so that the chapter and total tracks would both be off, which the legacy
    /// player does not allow either.
    private func playerDisplay(_ settings: MigratedSettings) -> ([(key: String, value: Bool, legacy: String)], [String]) {
        let keys = ["useChapterTrack": "previewChapterTrack", "useTotalTrack": "previewTotalTrack",
                    "scaleElapsedTimeBySpeed": "previewScaleElapsedBySpeed", "lockUi": "previewLockPlayerControls"]
        var choices: [String: (value: Bool, legacy: String)] = [:], unused: [String] = []
        if let raw = settings.preferences["playerSettings"] {
            if let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] {
                for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                    // JSON `true`/`false` only; `1` or `"yes"` are kept as they are.
                    if keys[key] != nil, let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                        choices[key] = (number.boolValue, "playerSettings." + key)
                    } else {
                        unused.append("playerSettings." + key)
                    }
                }
            } else {
                unused.append("playerSettings")
            }
        }
        if let player = settings.player {
            if choices["useChapterTrack"] == nil { choices["useChapterTrack"] = (player.chapterTrack, "chapterTrack") } else { unused.append("chapterTrack") }
        }
        func native(_ key: String) -> Bool? { defaults.object(forKey: keys[key]!) as? Bool }
        if !(native("useChapterTrack") ?? choices["useChapterTrack"]?.value ?? true), !(native("useTotalTrack") ?? choices["useTotalTrack"]?.value ?? true) {
            for key in ["useChapterTrack", "useTotalTrack"] where native(key) == nil {
                if let choice = choices.removeValue(forKey: key) { unused.append(choice.legacy) }
            }
        }
        return (choices.sorted(by: { $0.key < $1.key }).map { (keys[$0.key]!, $0.value.value, $0.value.legacy) }, unused)
    }

    /// The legacy `ereaderSettings` as native EPUB preferences, and the legacy fields that could
    /// not be used. Unusable fields keep the native default.
    private func readerPreferences(_ raw: String) -> (Data?, [String]) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { return (nil, []) }
        var preferences = EPUBPreferences()
        var unused: [String] = []
        func text(_ key: String, _ allowed: Set<String>) -> String? { (object[key] as? String).flatMap { allowed.contains($0) ? $0 : nil } }
        func number(_ key: String, _ range: ClosedRange<Double>) -> Double? { (object[key] as? Double).flatMap { $0.isFinite && range.contains($0) ? $0 : nil } }
        func flag(_ key: String) -> Bool? { object[key] as? Bool }
        func take<T>(_ value: T?, _ legacyKey: String, _ assign: (T) -> Void) {
            if let value { assign(value) } else if object[legacyKey] != nil { unused.append("ereaderSettings." + legacyKey) }
        }
        take(text("theme", ["light", "dark", "black"]), "theme") { preferences.theme = $0 }
        take(text("font", ["serif", "sans-serif", "monospace"]), "font") { preferences.font = $0 }
        take(number("fontScale", 5...300), "fontScale") { preferences.scale = $0 }
        take(number("lineSpacing", 100...300), "lineSpacing") { preferences.spacing = $0 }
        take(number("textStroke", 0...300), "textStroke") { preferences.stroke = $0 }
        take(text("spread", ["auto", "none", "always"]), "spread") { preferences.spread = $0 }
        take(flag("keepScreenAwake"), "keepScreenAwake") { preferences.keepAwake = $0 }
        take(text("navigateWithVolume", ["enabled", "mirrored", "none"]), "navigateWithVolume") { preferences.volume = $0 }
        take(flag("navigateWithVolumeWhilePlaying"), "navigateWithVolumeWhilePlaying") { preferences.volumeWhileListening = $0 }
        return (try? JSONEncoder().encode(preferences), unused)
    }
}
