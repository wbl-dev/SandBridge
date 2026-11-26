import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var devices: [IOSDevice] = []
    @Published var selectedDevice: IOSDevice?
    @Published var apps: [IOSAppInfo] = []
    @Published var selectedApp: IOSAppInfo?
    @Published var devOnly: Bool = true
    @Published var appSearch: String = ""

    @Published var currentPath: String = "Documents"
    @Published var entries: [SandboxEntry] = []
    @Published var fileFilter: String = ""
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "就绪"
    @Published var errorMessage: String?
    @Published var fileLoadError: String?
    @Published var appIcons: [String: NSImage] = [:]

    // 文本预览弹窗
    @Published var previewTitle: String?
    @Published var previewText: String?

    // 音频播放器
    @Published var playingEntry: SandboxEntry?
    @Published var isPlaying: Bool = false
    @Published var audioProgress: Double = 0
    @Published var audioDuration: Double = 0
    @Published var pcmSampleRate: Int = 48000
    @Published var pcmChannels: Int = 1

    private var audioPlayer: AVAudioPlayer?
    private var cachedPcmData: Data?
    private var progressTimer: Timer?
    private let service = DeviceCtlService.shared

    var filteredApps: [IOSAppInfo] {
        let kw = appSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(kw) || $0.bundleId.lowercased().contains(kw) }
    }

    var filteredEntries: [SandboxEntry] {
        let kw = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !kw.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(kw) }
    }

    func refreshDevices() async {
        isLoading = true
        statusMessage = "正在扫描已连接 iPhone..."
        errorMessage = nil
        do {
            let list = try await service.listDevices()
            devices = list
            if let cur = selectedDevice, list.contains(where: { $0.id == cur.id }) {
                // keep
            } else {
                selectedDevice = list.first
                if selectedDevice != nil {
                    await refreshApps()
                } else {
                    apps = []
                    entries = []
                }
            }
            statusMessage = list.isEmpty ? "未检测到已连接真机（请插 USB 或保持同 Wi-Fi）" : "已发现 \(list.count) 台设备"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "扫描失败"
        }
        isLoading = false
    }

    func selectDevice(_ dev: IOSDevice) async {
        selectedDevice = dev
        selectedApp = nil
        entries = []
        await refreshApps()
    }

    func refreshApps() async {
        guard let dev = selectedDevice else { return }
        isLoading = true
        statusMessage = "正在读取 App 列表..."
        errorMessage = nil
        do {
            let list = try await service.listApps(deviceId: dev.id, devOnly: devOnly)
            apps = list
            statusMessage = "共 \(list.count) 个 App"
            prefetchAppIcons(for: list)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "读取 App 失败"
        }
        isLoading = false
    }

    func selectApp(_ app: IOSAppInfo) async {
        selectedApp = app
        currentPath = "Documents"
        await refreshFiles()
    }

    func openPath(_ path: String) async {
        currentPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        await refreshFiles()
    }

    func refreshFiles() async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        isLoading = true
        statusMessage = "正在加载 /\(currentPath)..."
        fileLoadError = nil
        do {
            entries = try await service.listFiles(deviceId: dev.id, bundleId: app.bundleId, subdir: currentPath)
            statusMessage = "\(app.name) · /\(currentPath)（\(entries.count) 项）"
        } catch {
            entries = []
            let raw = error.localizedDescription
            if raw.contains("not allowed") || raw.contains("permission") || raw.contains("denied") || raw.contains("container") || !app.builtByDeveloper {
                fileLoadError = "无沙盒访问权限（仅开发签名 App 或支持容器访问的 App 可查看）\n\n详情：\(raw)"
            } else {
                fileLoadError = raw
            }
            statusMessage = "无权限或目录不可访问"
        }
        isLoading = false
    }

    // MARK: - 异步拉取 App 图标（带磁盘缓存）

    private var iconCacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SandBridgeIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func prefetchAppIcons(for appList: [IOSAppInfo]) {
        for app in appList {
            let bid = app.bundleId
            if appIcons[bid] != nil { continue }
            let cacheFile = iconCacheDir.appendingPathComponent("\(bid).png")
            if let img = NSImage(contentsOf: cacheFile) {
                appIcons[bid] = img
                continue
            }
            Task.detached(priority: .utility) { [weak self] in
                guard let imgData = await Self.fetchItunesIconData(bundleId: bid),
                      let img = NSImage(data: imgData) else { return }
                try? imgData.write(to: cacheFile)
                await MainActor.run {
                    self?.appIcons[bid] = img
                }
            }
        }
    }

    private static func fetchItunesIconData(bundleId: String) async -> Data? {
        var candidates = [bundleId]
        // 兼容开发版后缀（如 com.tencent.QQKSongDev -> com.tencent.QQKSong）
        for suffix in ["Dev", "Debug", ".dev", ".debug", "Beta"] {
            if bundleId.hasSuffix(suffix) {
                candidates.append(String(bundleId.dropLast(suffix.count)))
            }
        }
        for cid in candidates {
            for country in ["cn", "us"] {
                guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&country=\(country)") else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = obj["results"] as? [[String: Any]],
                       let first = results.first,
                       let artStr = (first["artworkUrl100"] as? String) ?? (first["artworkUrl60"] as? String),
                       let artURL = URL(string: artStr) {
                        let (imgData, _) = try await URLSession.shared.data(from: artURL)
                        if !imgData.isEmpty { return imgData }
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    // MARK: - 下载、上传、删除、Finder 打开

    func exportEntry(_ entry: SandboxEntry) async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        isLoading = true
        statusMessage = "正在导出 \(entry.name)..."
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try await service.copyFromDevice(deviceId: dev.id, bundleId: app.bundleId, remotePath: entry.path, destination: dest)
            statusMessage = "已导出到 \(dest.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func openInFinder(_ entry: SandboxEntry) async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        isLoading = true
        statusMessage = "正在拉取 \(entry.name)..."
        do {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SandBridgeCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let dest = tmpDir.appendingPathComponent(entry.name)
            try? FileManager.default.removeItem(at: dest)
            try await service.copyFromDevice(deviceId: dev.id, bundleId: app.bundleId, remotePath: entry.path, destination: dest)
            NSWorkspace.shared.open(dest)
            statusMessage = "已打开 \(entry.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func pickAndUploadFiles() async {
        guard selectedDevice != nil, selectedApp != nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        await uploadURLs(panel.urls)
    }

    func makeDragItemProvider(for entry: SandboxEntry) -> NSItemProvider {
        guard let dev = selectedDevice, let app = selectedApp else {
            return NSItemProvider()
        }
        let deviceId = dev.id
        let bundleId = app.bundleId
        let remotePath = entry.path
        let fileName = entry.name
        let isDir = entry.isDir

        let ext = URL(fileURLWithPath: fileName).pathExtension
        let contentType: UTType = isDir ? .folder : (UTType(filenameExtension: ext) ?? .data)

        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            let progress = Progress(totalUnitCount: 100)
            Task {
                await MainActor.run {
                    self?.statusMessage = "正在拖出 \(fileName)..."
                }
                let dragDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SandBridgeDragCache", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: dragDir, withIntermediateDirectories: true)
                let dest = dragDir.appendingPathComponent(fileName)
                do {
                    try await DeviceCtlService.shared.copyFromDevice(
                        deviceId: deviceId,
                        bundleId: bundleId,
                        remotePath: remotePath,
                        destination: dest
                    )
                    progress.completedUnitCount = 100
                    await MainActor.run {
                        self?.statusMessage = "已拖出 \(fileName)"
                    }
                    completion(dest, false, nil)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "拖出失败: \(error.localizedDescription)"
                        self?.statusMessage = "拖出失败"
                    }
                    completion(nil, false, error)
                }
            }
            return progress
        }
        return provider
    }

    func uploadURLs(_ urls: [URL]) async {
        // 忽略从自身拖出缓存目录回落的文件，防止误触自我上传
        let validURLs = urls.filter { !$0.path.contains("SandBridgeDragCache") }
        guard let dev = selectedDevice, let app = selectedApp, !validURLs.isEmpty else { return }
        isLoading = true
        do {
            for url in validURLs {
                statusMessage = "正在上传 \(url.lastPathComponent)..."
                try await service.copyToDevice(deviceId: dev.id, bundleId: app.bundleId, localURL: url, remoteDir: currentPath)
            }
            statusMessage = "已上传 \(validURLs.count) 个文件"
            await refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func deleteEntry(_ entry: SandboxEntry) async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        isLoading = true
        statusMessage = "正在删除 \(entry.name)..."
        do {
            try await service.deleteFile(deviceId: dev.id, bundleId: app.bundleId, remotePath: entry.path)
            statusMessage = "已删除 \(entry.name)"
            await refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - 文本预览 & 音频试听（含裸 PCM）

    func previewTextFile(_ entry: SandboxEntry) async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        isLoading = true
        statusMessage = "正在读取 \(entry.name)..."
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview_\(UUID().uuidString)_\(entry.name)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await service.copyFromDevice(deviceId: dev.id, bundleId: app.bundleId, remotePath: entry.path, destination: tmp)
            let data = try Data(contentsOf: tmp)
            var text = String(data: data, encoding: .utf8) ?? "<非 UTF-8 二进制文件>"
            if entry.name.lowercased().hasSuffix(".json"),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let prettyStr = String(data: pretty, encoding: .utf8) {
                text = prettyStr
            }
            previewTitle = entry.name
            previewText = text
            statusMessage = "预览 \(entry.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func playAudioEntry(_ entry: SandboxEntry) async {
        guard let dev = selectedDevice, let app = selectedApp else { return }
        stopAudio()
        isLoading = true
        statusMessage = "正在加载音频 \(entry.name)..."
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("play_\(UUID().uuidString)_\(entry.name)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await service.copyFromDevice(deviceId: dev.id, bundleId: app.bundleId, remotePath: entry.path, destination: tmp)
            let rawData = try Data(contentsOf: tmp)
            playingEntry = entry
            if entry.name.lowercased().hasSuffix(".pcm") {
                cachedPcmData = rawData
                startPcmPlayback()
            } else {
                cachedPcmData = nil
                try startAudioDataPlayback(rawData)
            }
            statusMessage = "正在播放 \(entry.name)"
        } catch {
            errorMessage = "无法播放音频: \(error.localizedDescription)"
            playingEntry = nil
        }
        isLoading = false
    }

    func startPcmPlayback() {
        guard let pcm = cachedPcmData else { return }
        let wav = DeviceCtlService.wrapPcmAsWav(pcmData: pcm, sampleRate: pcmSampleRate, channels: pcmChannels)
        do {
            try startAudioDataPlayback(wav)
        } catch {
            errorMessage = "PCM 播放失败: \(error.localizedDescription)"
        }
    }

    private func startAudioDataPlayback(_ data: Data) throws {
        audioPlayer?.stop()
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        player.play()
        audioPlayer = player
        audioDuration = player.duration
        audioProgress = 0
        isPlaying = true

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.audioPlayer else { return }
                self.audioProgress = p.currentTime
                self.isPlaying = p.isPlaying
            }
        }
    }

    func togglePlayPause() {
        guard let p = audioPlayer else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func seekAudio(to seconds: Double) {
        audioPlayer?.currentTime = seconds
        audioProgress = seconds
    }

    func stopAudio() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        cachedPcmData = nil
        playingEntry = nil
        isPlaying = false
        audioProgress = 0
        audioDuration = 0
    }
}
