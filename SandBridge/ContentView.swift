import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isDropTargeted = false

    private let audioExts: Set<String> = ["m4a", "wav", "mp3", "aac", "pcm", "caf"]
    private let textExts: Set<String> = ["json", "txt", "log", "xml", "plist", "csv", "md", "qrc"]

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
            } detail: {
                detailPane
            }

            if let entry = vm.playingEntry {
                Divider()
                audioPlayerBar(entry: entry)
            }

            Divider()
            statusBar
        }
        .task {
            await vm.refreshDevices()
        }
        .sheet(isPresented: Binding(get: { vm.previewText != nil }, set: { if !$0 { vm.previewText = nil } })) {
            VStack(spacing: 0) {
                HStack {
                    Text(vm.previewTitle ?? "文件预览")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { vm.previewText = nil }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(12)
                Divider()
                ScrollView {
                    Text(vm.previewText ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .frame(width: 680, height: 500)
        }
        .alert("操作提示", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("确定", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 设备列表
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("已连接 iPhone")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await vm.refreshDevices() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("刷新设备")
                }
                if vm.devices.isEmpty {
                    Text("未检测到真机")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(vm.devices) { dev in
                        HStack {
                            Image(systemName: dev.transport == "USB" ? "cable.connector" : "wifi")
                                .foregroundColor(dev.transport == "USB" ? .green : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dev.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                                Text("\(dev.model) · iOS \(dev.osVersion)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(dev.transport)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .padding(7)
                        .background(vm.selectedDevice?.id == dev.id ? Color.accentColor.opacity(0.22) : Color.clear)
                        .cornerRadius(7)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await vm.selectDevice(dev) }
                        }
                    }
                }
            }
            .padding(10)

            Divider()

            // App 列表
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("App 沙盒")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("仅开发版", isOn: $vm.devOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .onChange(of: vm.devOnly) { _ in
                            Task { await vm.refreshApps() }
                        }
                }
                TextField("搜索 App 或 Bundle ID...", text: $vm.appSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)

            List(vm.filteredApps) { app in
                HStack(spacing: 8) {
                    appIconView(for: app)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(app.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            if app.builtByDeveloper {
                                Text("Dev")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }
                        Text(app.bundleId)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(vm.selectedApp?.bundleId == app.bundleId ? Color.accentColor.opacity(0.22) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await vm.selectApp(app) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Group {
                    Button("根目录") { Task { await vm.openPath("") } }
                    Button("Documents") { Task { await vm.openPath("Documents") } }
                    Button("Caches") { Task { await vm.openPath("Library/Caches") } }
                    Button("tmp") { Task { await vm.openPath("tmp") } }
                }
                .disabled(vm.selectedApp == nil)

                Divider().frame(height: 18)

                // 面包屑
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        let parts = vm.currentPath.isEmpty ? [] : vm.currentPath.split(separator: "/").map(String.init)
                        Button(vm.selectedApp?.name ?? "/") {
                            Task { await vm.openPath("") }
                        }
                        .buttonStyle(.link)
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, seg in
                            Text("/").foregroundColor(.secondary)
                            let target = parts[0...idx].joined(separator: "/")
                            Button(seg) {
                                Task { await vm.openPath(target) }
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                }

                Spacer()

                TextField("过滤文件名...", text: $vm.fileFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Button {
                    Task { await vm.pickAndUploadFiles() }
                } label: {
                    Label("上传", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.selectedApp == nil)

                Button {
                    Task { await vm.refreshFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.selectedApp == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // File list with Drag & Drop
            ZStack {
                if vm.selectedApp == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 38))
                            .foregroundColor(.secondary)
                        Text("选择左侧 iPhone 和 App 开始浏览沙盒")
                            .foregroundColor(.secondary)
                        Text("支持直接把 Finder 文件拖拽到此窗口上传到手机")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErr = vm.fileLoadError {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text("无法访问该 App 沙盒")
                            .font(.headline)
                        Text(loadErr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Text(vm.isLoading ? "加载中..." : "当前目录为空")
                            .foregroundColor(.secondary)
                        Text("可直接拖拽 Mac 文件到这里上传")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.filteredEntries) { entry in
                        fileRow(entry)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentColor.opacity(0.12))
                        .overlay(
                            Text("松开鼠标上传到 /\(vm.currentPath)")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        )
                        .padding(10)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard vm.selectedApp != nil else { return false }
                var urls: [URL] = []
                let group = DispatchGroup()
                for p in providers {
                    group.enter()
                    p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        } else if let url = item as? URL {
                            urls.append(url)
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    Task { await vm.uploadURLs(urls) }
                }
                return true
            }
        }
    }

    private func fileRow(_ entry: SandboxEntry) -> some View {
        let ext = URL(fileURLWithPath: entry.name).pathExtension.lowercased()
        let isAudio = !entry.isDir && audioExts.contains(ext)
        let isText = !entry.isDir && textExts.contains(ext)

        return HStack(spacing: 10) {
            Image(systemName: entry.isDir ? "folder.fill" : (isAudio ? "waveform" : (isText ? "doc.text" : "doc")))
                .foregroundColor(entry.isDir ? .accentColor : (isAudio ? .orange : .secondary))
                .frame(width: 18)

            Text(entry.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(entry.isDir ? "-" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)

            Text(formatISO(entry.modified))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .trailing)

            HStack(spacing: 6) {
                if isAudio {
                    Button("试听") { Task { await vm.playAudioEntry(entry) } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if isText {
                    Button("预览") { Task { await vm.previewTextFile(entry) } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !entry.isDir {
                    Button("导出") { Task { await vm.exportEntry(entry) } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button(role: .destructive) {
                    Task { await vm.deleteEntry(entry) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
            }
            .frame(width: 155, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if entry.isDir {
                Task { await vm.openPath(entry.path) }
            } else if isAudio {
                Task { await vm.playAudioEntry(entry) }
            } else if isText {
                Task { await vm.previewTextFile(entry) }
            } else {
                Task { await vm.openInFinder(entry) }
            }
        }
    }

    // MARK: - Audio Player Bar

    private func audioPlayerBar(entry: SandboxEntry) -> some View {
        let isPcm = entry.name.lowercased().hasSuffix(".pcm")
        return HStack(spacing: 12) {
            Button {
                vm.togglePlayPause()
            } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderedProminent)

            Text(entry.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)

            if isPcm {
                Picker("", selection: $vm.pcmSampleRate) {
                    Text("48kHz").tag(48000)
                    Text("44.1kHz").tag(44100)
                    Text("16kHz").tag(16000)
                }
                .frame(width: 85)
                .onChange(of: vm.pcmSampleRate) { _ in vm.startPcmPlayback() }

                Picker("", selection: $vm.pcmChannels) {
                    Text("单声道").tag(1)
                    Text("双声道").tag(2)
                }
                .frame(width: 80)
                .onChange(of: vm.pcmChannels) { _ in vm.startPcmPlayback() }
            }

            Slider(
                value: Binding(get: { vm.audioProgress }, set: { vm.seekAudio(to: $0) }),
                in: 0...max(0.1, vm.audioDuration)
            )

            Text("\(formatSec(vm.audioProgress)) / \(formatSec(vm.audioDuration))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)

            Button {
                vm.stopAudio()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            if vm.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("基于原生 xcrun devicectl · 零侵入访问 USB/Wi-Fi 沙盒")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func appIconView(for app: IOSAppInfo) -> some View {
        Group {
            if let nsImg = vm.appIcons[app.bundleId] {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                let palette: [Color] = [.blue, .indigo, .purple, .teal, .orange, .pink, .mint]
                let hash = abs(app.bundleId.hashValue)
                let color = palette[hash % palette.count]
                let initial = String(app.name.prefix(1)).uppercased()
                ZStack {
                    color.opacity(0.85)
                    Text(initial.isEmpty ? "A" : initial)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func formatISO(_ iso: String) -> String {
        guard !iso.isEmpty else { return "-" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MM-dd HH:mm:ss"
        return out.string(from: d)
    }

    private func formatSec(_ s: Double) -> String {
        let total = max(0, Int(s))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
