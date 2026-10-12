import SwiftUI
import RoarkTCore

struct ScreenshotHistoryView: View {
    @Bindable var history: ScreenshotHistory
    let open: (ScreenshotHistoryEntry) -> Void
    let action: (ScreenshotHistoryEntry, Action) -> Void
    let close: () -> Void
    var pinningAllowed: () -> Bool = { true }
    enum Action { case pin, copy, save }
    @State private var query = ""
    @State private var confirmClear = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ScreenshotLabel("截图历史", systemImage: ScreenshotSymbols.history).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(history.onDisk ? "已开启磁盘保存" : "仅本次运行").font(.system(size: 12)).foregroundStyle(p.secondary)
                Button("关闭", action: close).buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            HStack {
                TextField("搜索已识别的文字", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("搜索截图历史中的识别文字")
                Text("\(history.entries.count) 张").font(.system(size: 12)).monospacedDigit()
                Button("清空历史…") { confirmClear = true }.disabled(history.entries.isEmpty && !history.onDisk)
            }
            if history.loading || history.syncing { ProgressView(history.loading ? "正在读取历史…" : "正在同步截图历史…").controlSize(.small) }
            if let notice = history.notice {
                HStack { Text(notice).font(.system(size: 12)).foregroundStyle(p.warn); Button("重试") { history.retryDisk() } }
            }
            ScrollView {
                if history.matches(query).isEmpty {
                    VStack(spacing: 10) {
                        ScreenshotIcon(systemName: ScreenshotSymbols.stack).font(.system(size: 30))
                        Text(query.isEmpty ? "还没有截图历史" : "没有匹配的截图")
                        Text("完成截图后自动保留，并在本机识别文字供搜索。").font(.system(size: 12))
                    }.foregroundStyle(p.secondary).frame(maxWidth: .infinity).padding(.top, 90)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(history.matches(query)) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { open(entry) } label: {
                                Image(decorative: entry.thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity).frame(height: 118).background(p.canvas)
                            }.buttonStyle(.plain).accessibilityLabel("打开 \(entry.date.formatted()) 的截图")
                            Text(entry.date, format: .dateTime.month().day().hour().minute().second())
                                .font(.system(size: 11)).foregroundStyle(p.secondary)
                            Text(entry.text.isEmpty ? "暂无识别文字" : entry.text).font(.system(size: 12)).lineLimit(2).frame(height: 32, alignment: .top)
                            HStack(spacing: 8) {
                                Button("打开") { open(entry) }
                                Menu("操作") {
                                    if pinningAllowed() { Button { action(entry, .pin) } label: { ScreenshotLabel("贴图", systemImage: ScreenshotSymbols.pin) } }
                                    Button { action(entry, .copy) } label: { ScreenshotLabel("复制图片", systemImage: ScreenshotSymbols.copy) }
                                    Button { action(entry, .save) } label: { ScreenshotLabel("另存为…", systemImage: ScreenshotSymbols.save) }
                                    Divider()
                                    Button("删除", role: .destructive) { history.remove(entry.id) }
                                }
                            }.font(.system(size: 12))
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line, lineWidth: 1))
                    }
                }
            }
            Text("图片较大时可能提前移出历史；每张图片最多缓存前 64 KB 的识别文字供搜索。")
                .font(.system(size: 11)).foregroundStyle(p.secondary)
            Text(history.onDisk ? "最多 \(history.countLimit) 张，保留 \(history.days) 天；清空会删除磁盘副本。" : "默认最多 20 张；退出后清空。磁盘保存需在截图设置中开启。")
                .font(.system(size: 11)).foregroundStyle(p.secondary)
        }.padding(20).frame(minWidth: 500, minHeight: 400).modifier(DesignSurface())
            .onExitCommand(perform: close)
            .alert("清空全部截图历史？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { history.clear() }
            } message: { Text("将移除历史中的图片、识别文字缓存和已保存的磁盘副本。已另存到其他位置的文件不受影响。") }
    }
}

struct ScreenshotHistorySettings: View {
    @Binding var settings: RoarkTCore.ScreenshotSettings
    var body: some View {
        DesignSectionTitle(title: "截图历史")
        DesignCard {
            Toggle("保存到磁盘", isOn: Binding(get: { settings.historyOnDisk ?? false }, set: { settings.historyOnDisk = $0 }))
            Text("默认仅保留本次运行最近 20 张截图及识别文字缓存。开启后保存在本机 RockType 应用支持目录；关闭此选项会删除磁盘历史。")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if settings.historyOnDisk == true {
                Stepper("最多 \(min(200, max(1, settings.historyDiskCount ?? 20))) 张", value: Binding(get: { min(200, max(1, settings.historyDiskCount ?? 20)) }, set: { settings.historyDiskCount = $0 }), in: 1...200)
                Stepper("保留 \(min(365, max(1, settings.historyDiskDays ?? 7))) 天", value: Binding(get: { min(365, max(1, settings.historyDiskDays ?? 7)) }, set: { settings.historyDiskDays = $0 }), in: 1...365)
            }
        }
    }
}

@MainActor final class ScreenshotHistoryPanelController: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private var protection: Task<Void, Never>?
    let history: ScreenshotHistory
    let allowed: () -> Bool
    let open: (ScreenshotHistoryEntry) -> Void
    let action: (ScreenshotHistoryEntry, ScreenshotHistoryView.Action) -> Void
    let present: (NSPanel) -> Void
    let pinningAllowed: () -> Bool
    init(history: ScreenshotHistory, allowed: @escaping () -> Bool,
         open: @escaping (ScreenshotHistoryEntry) -> Void,
         action: @escaping (ScreenshotHistoryEntry, ScreenshotHistoryView.Action) -> Void,
         pinningAllowed: @escaping () -> Bool = { true },
         present: @escaping (NSPanel) -> Void = { $0.center(); $0.orderFrontRegardless(); $0.makeKey() }) {
        self.pinningAllowed = pinningAllowed
        self.history = history; self.allowed = allowed; self.open = open; self.action = action; self.present = present
    }
    func show() {
        guard allowed() else { close(); return }
        history.refresh()
        if let panel { present(panel); return }
        let panel = CapturePanel(contentRect: CGRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "截图历史"; panel.contentMinSize = CGSize(width: 500, height: 400)
        panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.delegate = self
        panel.contentView = NSHostingView(rootView: ScreenshotHistoryView(history: history, open: { [weak self] entry in
            guard let self, self.allowed() else { return }; self.close(); self.open(entry)
        }, action: { [weak self] entry, action in
            guard let self, self.allowed() else { return }; self.action(entry, action)
        }, close: { [weak self] in self?.close() }, pinningAllowed: pinningAllowed))
        self.panel = panel; present(panel)
        protection = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.close(); return }
            }
        }
    }
    func close() {
        let old = panel; panel = nil; old?.delegate = nil; old?.orderOut(nil); old?.contentView = nil; old?.close()
        protection?.cancel(); protection = nil
    }
    func windowWillClose(_ notification: Notification) { close() }
    isolated deinit { protection?.cancel() }
}
