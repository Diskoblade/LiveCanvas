import Foundation
import Observation

/// Owns AppSettings, persists on change (debounced), tolerant of missing/corrupt files.
@MainActor
@Observable
final class PreferencesStore {
    private(set) var settings: AppSettings
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    var lastError: Error?

    init(fileURL: URL = AppDirectories.settingsFile) {
        self.fileURL = fileURL
        self.settings = AppSettings()
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONCoding.decoder()
            settings = try decoder.decode(AppSettings.self, from: data)
            Log.persistence.info("Loaded settings from \(self.fileURL.path, privacy: .public)")
        } catch {
            Log.persistence.error("Settings unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            lastError = LiveCanvasError.persistenceFailed("Settings file could not be read; defaults are in use.")
        }
    }

    /// Mutate settings in place; the change is persisted shortly afterwards.
    func update(_ body: (inout AppSettings) -> Void) {
        var copy = settings
        body(&copy)
        guard copy != settings else { return }
        settings = copy
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            let data = try JSONCoding.encoder().encode(settings)
            try AtomicFileWriter.write(data, to: fileURL)
        } catch {
            Log.persistence.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
            lastError = LiveCanvasError.persistenceFailed(error.localizedDescription)
        }
    }
}
