import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

@MainActor @Observable final class ScreenshotHistory {
    private(set) var entries: [ScreenshotHistoryEntry] = []
    private(set) var notice: String?
    private(set) var syncing = false
    private(set) var loading = false
    var onNotice: (String) -> Void = { _ in }
    @ObservationIgnored private let disk: ScreenshotHistoryDisk
    @ObservationIgnored private let allowed: @MainActor @Sendable () -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let recognize: @Sendable (CGImage, [String]) async throws -> String
    @ObservationIgnored private var ocrQueue: [UUID] = []
    @ObservationIgnored private var ocrTask: Task<Void, Never>?
    @ObservationIgnored private var ocrProtection: Task<Void, Never>?
    @ObservationIgnored private var ocrGeneration = 0
    @ObservationIgnored private var edited = Set<UUID>()
    private var settings = ScreenshotSettings()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var ignored = Set<UUID>()
    @ObservationIgnored private var needsRestore = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var ending = false
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var discardArchive = false
    @ObservationIgnored private var retention: Task<Void, Never>?
    init(disk: ScreenshotHistoryDisk = ScreenshotHistoryDisk(), allowed: @escaping @MainActor @Sendable () -> Bool,
         now: @escaping () -> Date = Date.init,
         recognize: @escaping @Sendable (CGImage, [String]) async throws -> String = ScreenshotHistory.recognizeImage) {
        self.disk = disk; self.allowed = allowed; self.now = now; self.recognize = recognize
    }
    nonisolated private static func recognizeImage(_ image: CGImage, languages: [String]) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw OCR.Failure.invalidImage }
            return try await OCR().recognize(data, languages: languages).text
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    var onDisk: Bool { settings.historyOnDisk == true }
    var countLimit: Int { onDisk ? min(200, max(1, settings.historyDiskCount ?? 20)) : 20 }
    var days: Int { min(365, max(1, settings.historyDiskDays ?? 7)) }
    func start(_ settings: ScreenshotSettings) {
        guard !running else { configure(settings); return }
        running = true; ending = false; self.settings = settings
        if onDisk { restore() }
        retention = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.refresh()
            }
        }
    }
    func configure(_ value: ScreenshotSettings) {
        let wasOn = onDisk; settings = value
        guard running else { return }
        if onDisk && !wasOn { restore() }
        else if !onDisk && wasOn {
            discardArchive = true
            loadGeneration += 1; loadTask?.cancel(); loadTask = nil; loading = false; needsRestore = false
            prune(persistChanges: false); persist(forceClear: true)
        } else { prune() }
    }
    @discardableResult func record(_ image: CGImage) -> UUID? {
        guard running, !ending, allowed(), image.height > 0,
              image.width <= ScreenshotImageImport.maximumPixels / image.height,
              image.bytesPerRow * image.height <= 256 * 1024 * 1024 else { return nil }
        let entry = ScreenshotHistoryEntry(date: now(), image: image)
        guard entry.bytes <= 256 * 1024 * 1024 else { return nil }
        entries.insert(entry, at: 0); prune(persistChanges: false); persist()
        ocrQueue.append(entry.id); recognizeNext(); return entry.id
    }
    func updateText(_ text: String, id: UUID) {
        guard running, !ending, allowed(), let index = entries.firstIndex(where: { $0.id == id }) else { return }
        edited.insert(id)
        entries[index].text = ScreenshotHistoryEntry.cachedText(text); entries[index].recognized = true; prune(persistChanges: false); persist()
    }
    func remove(_ id: UUID) {
        if loading || needsRestore { ignored.insert(id) }; ocrQueue.removeAll { $0 == id }; entries.removeAll { $0.id == id }; persist()
    }
    func clear() {
        cancelOCR(); discardArchive = true; edited.removeAll(); ignored.removeAll()
        loadGeneration += 1; loadTask?.cancel(); loadTask = nil; loading = false; needsRestore = false
        entries.removeAll(); persist(forceClear: true)
    }
    func matches(_ query: String) -> [ScreenshotHistoryEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? entries : entries.filter { $0.text.localizedStandardContains(text) }
    }
    func refresh() {
        guard allowed() else { return }
        if needsRestore && !loading { restore() }
        else {
            prune()
            if dirty && task == nil { persist(forceClear: !onDisk) }
        }
    }
    func prune(persistChanges: Bool = true) {
        guard allowed() else { return }
        let old = entries.map(\.id), cutoff = now().addingTimeInterval(-Double(days) * 86400)
        if onDisk { entries.removeAll { $0.date < cutoff } }
        entries.sort { $0.date > $1.date }
        while entries.count > countLimit || entries.reduce(0, { $0 + $1.bytes }) > 256 * 1024 * 1024 { entries.removeLast() }
        edited.formIntersection(entries.map(\.id))
        if persistChanges && old != entries.map(\.id) { persist() }
    }
    private func restore() {
        if discardArchive { needsRestore = false; persist(forceClear: true); return }
        loadGeneration += 1; let current = loadGeneration
        loadTask?.cancel(); task?.cancel(); loading = true; syncing = false
        needsRestore = true
        loadTask = Task { [weak self, disk, allowed] in
            do {
                let restored = try await disk.load(allowed: allowed)
                guard let self, self.running, self.onDisk, current == self.loadGeneration, !Task.isCancelled else { return }
                guard self.allowed() else { self.loading = false; self.loadTask = nil; return }
                do {
                    let existing = Set(self.entries.map(\.id))
                    self.entries += restored.filter { !existing.contains($0.id) && !self.ignored.contains($0.id) }
                }
                self.loading = false; self.needsRestore = false; self.loadTask = nil; self.prune(persistChanges: false); self.persist()
                self.ocrQueue += self.entries.filter { !$0.recognized }.map(\.id); self.recognizeNext()
            } catch {
                guard let self, current == self.loadGeneration, !Task.isCancelled else { return }
                self.loading = false; self.loadTask = nil
                if !(error is CancellationError) { self.report("无法读取磁盘截图历史，请检查目录权限。") }
            }
        }
    }
    private func persist(forceClear: Bool = false) {
        guard running, !loading, onDisk || forceClear else { return }
        if onDisk && needsRestore { if allowed() { restore() }; return }
        dirty = true
        revision += 1; let current = revision, values = entries, enabled = onDisk
        task?.cancel(); syncing = true
        task = Task { [weak self, disk, allowed] in
            do {
                if enabled && !values.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
                try await disk.write(values, revision: current, enabled: enabled, allowed: allowed)
                guard let self, current == self.revision else { return }
                self.syncing = false; self.notice = nil; self.task = nil; self.dirty = false; self.discardArchive = false
            } catch {
                guard let self, current == self.revision, !Task.isCancelled else { return }
                self.syncing = false; self.task = nil
                if !(error is CancellationError) { self.report("截图历史磁盘同步失败；新增内容仅在内存，删除内容可能仍在磁盘，请检查目录权限后重试。") }
            }
        }
    }
    private func report(_ value: String) { if notice != value { notice = value; onNotice(value) } }
    func retryDisk() { if onDisk && needsRestore && !discardArchive { restore() } else { persist(forceClear: true) } }
    func flush(cancelRecognition: Bool = false) async {
        if cancelRecognition { ending = true; cancelOCR() }
        await loadTask?.value
        if dirty && task == nil && allowed() { persist(forceClear: !onDisk) }
        while let pending = task {
            let current = revision; await pending.value
            if current == revision { break }
        }
    }
    func stop() {
        running = false; cancelOCR(); loadGeneration += 1; loadTask?.cancel(); loadTask = nil
        retention?.cancel(); retention = nil; entries.removeAll()
        // An already-authorized serial disk flush may finish during ordinary shutdown.
    }
    private func recognizeNext() {
        guard running, !ending, allowed(), ocrTask == nil else { return }
        let ids = Set(entries.map(\.id)); ocrQueue.removeAll { !ids.contains($0) || edited.contains($0) }
        guard !ocrQueue.isEmpty else { ocrProtection?.cancel(); ocrProtection = nil; return }
        let id = ocrQueue.removeFirst()
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        ocrGeneration += 1; let current = ocrGeneration, languages = settings.ocrLanguages
        ocrTask = Task { [weak self, recognize] in
            let result = try? await recognize(entry.image, languages)
            guard let self, current == self.ocrGeneration else { return }
            if !Task.isCancelled, self.running, self.allowed(), !self.edited.contains(id), let result {
                self.updateText(result, id: id)
            }
            self.ocrTask = nil; self.recognizeNext()
        }
        if ocrProtection == nil {
            ocrProtection = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self else { return }
                    if !self.allowed() { self.cancelOCR(); return }
                }
            }
        }
    }
    private func cancelOCR() {
        ocrGeneration += 1; ocrTask?.cancel(); ocrTask = nil; ocrQueue.removeAll()
        ocrProtection?.cancel(); ocrProtection = nil
    }
    isolated deinit { task?.cancel(); loadTask?.cancel(); retention?.cancel(); ocrTask?.cancel(); ocrProtection?.cancel() }
}
