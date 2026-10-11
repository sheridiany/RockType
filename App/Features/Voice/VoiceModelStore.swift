import Foundation
import Combine
import RoarkTCore

@MainActor
final class VoiceModelStore: ObservableObject {
    static let shared = VoiceModelStore()
    static let willDelete = Notification.Name("RoarkTVoiceModelWillDelete")
    @Published private(set) var progress: Double?
    @Published private(set) var message = "模型仅在点击下载后获取，每个文件均校验 SHA-256。"
    @Published private(set) var busy = false
    @Published private(set) var revision = 0
    private var task: Task<Void, Never>?
    let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Identifiers.applicationSupportFolder + "/VoiceModels", isDirectory: true)) {
        self.root = root
    }
    func directory(for model: VoiceModel) -> URL { root.appendingPathComponent(model.rawValue, isDirectory: true) }
    func isPresent(_ model: VoiceModel) -> Bool {
        model.files.allSatisfy {
            let size = try? directory(for: model).appendingPathComponent($0.name).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return Int64(size ?? -1) == $0.bytes
        }
    }
    /// Size alone is only a UI hint. Every load must pass this gate.
    func validate(_ model: VoiceModel) async throws -> URL {
        let folder = directory(for: model)
        let check = Task.detached(priority: .utility) {
            guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for file in model.files { try Task.checkCancellation(); try file.validate(at: folder.appendingPathComponent(file.name)) }
        }
        try await withTaskCancellationHandler { try await check.value } onCancel: { check.cancel() }
        try Task.checkCancellation()
        return folder
    }
    func cancel() {
        task?.cancel()
        // Keep the slot occupied until the writer has closed its file handles.
        message = "正在取消下载…"
    }
    func download(_ model: VoiceModel) {
        guard !busy else { return }
        busy = true; progress = 0
        task = Task {
            defer { busy = false; progress = nil; task = nil; revision += 1 }
            do {
                let folder = directory(for: model)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                let total = model.files.reduce(Int64(0)) { $0 + $1.bytes }
                let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage ?? Int64.max
                // Conservative: require enough room for a complete replacement plus download overhead.
                guard available > total + 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
                var completed: Int64 = 0
                for file in model.files {
                    try Task.checkCancellation()
                    let destination = folder.appendingPathComponent(file.name)
                    let before = completed
                    let source = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/\(file.name)")!
                    try await VoiceFileDownloader().download(file, from: [source], to: destination) { [weak self] event in
                        Task { @MainActor in
                            guard let self, self.busy else { return }
                            switch event {
                            case .transferring(let bytes, _):
                                self.progress = Double(before + bytes) / Double(total)
                                self.message = "正在下载 \(file.name)"
                            case .retrying: self.message = "连接失败，正在重试；可取消后重新下载。"
                            case .verifying: self.message = "正在校验 \(file.name)…"
                            }
                        }
                    }
                    completed += file.bytes
                }
                _ = try await validate(model)
                message = "下载完成，SHA-256 校验通过。"
            } catch is CancellationError {
                message = "已取消；已完成的分块保留，下载可重试。"
            } catch {
                if (error as NSError).code == CocoaError.fileWriteOutOfSpace.rawValue {
                    message = "磁盘空间不足，请释放空间后重试。"
                } else if (error as NSError).code == CocoaError.fileReadCorruptFile.rawValue {
                    message = "模型校验失败，禁止加载；请重新下载。"
                } else {
                    message = "下载未完成，请检查网络或磁盘权限后重试。"
                }
            }
        }
    }
    func remove(_ model: VoiceModel) {
        guard !busy else { return }
        NotificationCenter.default.post(name: Self.willDelete, object: model.rawValue)
        do {
            let folder = directory(for: model)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            message = "已删除此模型；其他模型与个人数据保留。"
        } catch { message = "无法删除模型，请检查文件权限。" }
        revision += 1
    }
}

extension VoiceModel {
    init(_ setting: VoiceSettings.Model) { self = setting == .small ? .small : .large }
}
