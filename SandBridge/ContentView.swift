import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isDropTargeted = false
    @State private var hoveredDeviceId: String?
    @State private var hoveredAppId: String?
    @State private var hoveredEntryId: String?
    @State private var selectedEntryId: String?

    private let audioExts: Set<String> = ["m4a", "wav", "mp3", "aac", "pcm", "caf"]
    private let textExts: Set<String> = ["json", "txt", "log", "xml", "plist", "csv", "md", "qrc"]

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
            } detail: {
                detailPane
            }

            if let entry = vm.playingEntry {
                Divider()
                audioPlayerBar(entry: entry)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider()
            statusBar
        }
        .animation(.easeInOut(duration: 0.16), value: vm.playingEntry?.id)
        .onAppear {
            vm.startAutoScan()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await vm.goUpOneLevel() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(vm.selectedApp == nil || vm.currentPath.isEmpty)
                .help("返回上一级目录")
            }

            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 2) {
                    quickPathTab("根目录", path: "")
                    quickPathTab("Documents", path: "Documents")
                    quickPathTab("Caches", path: "Library/Caches")
                    quickPathTab("tmp", path: "tmp")
                }
                .padding(3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(7)
                .disabled(vm.selectedApp == nil)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("过滤文件...", text: $vm.fileFilter)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .frame(width: 120)
                    if !vm.fileFilter.isEmpty {
                        Button {
                            vm.fileFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)

                Button {
                    Task { await vm.pickAndUploadFiles() }
                } label: {
                    Label("上传", systemImage: "square.and.arrow.up")
                }
                .disabled(vm.selectedApp == nil)
                .help("上传文件到当前手机目录")

                Button {
                    Task { await vm.refreshFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vm.selectedApp == nil)
                .help("刷新当前目录 (⌘R)")
            }
        }
        .sheet(isPresented: Binding(get: { vm.previewText != nil }, set: { if !$0 { vm.previewText = nil } })) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                    Text(vm.previewTitle ?? "文件预览")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { vm.previewText = nil }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
                ScrollView {
                    Text(vm.previewText ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .frame(width: 700, height: 520)
        }
        .alert("操作提示", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("确定", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func quickPathTab(_ title: String, path: String) -> some View {
        let isActive = vm.selectedApp != nil && vm.currentPath == path
        return Button {
            Task { await vm.openPath(path) }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                .foregroundColor(isActive ? .primary : .secondary)
                .cornerRadius(5)
                .shadow(color: isActive ? Color.black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 设备列表（支持 USB + Wi-Fi 持续自动发现）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("设备")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(vm.isAutoScanning ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(vm.isAutoScanning ? "USB / Wi-Fi 自动扫描" : "已暂停")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                    Spacer()

                    Button {
                        Task { await vm.refreshDevices(silent: false) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("立即扫描 USB / Wi-Fi 设备")
                }

                if vm.devices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在搜索 USB 或同局域网 Wi-Fi 设备...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(vm.devices) { dev in
                            deviceCard(dev)
                        }
                    }
                }
            }
            .padding(12)

            Divider()

            // App 搜索栏
            VStack(alignment: .leading, spacing: 8) {
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

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextField("搜索 App 或 Bundle ID...", text: $vm.appSearch)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !vm.appSearch.isEmpty {
                        Button {
                            vm.appSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // App 列表
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(vm.filteredApps) { app in
                        appRow(app)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func deviceCard(_ dev: IOSDevice) -> some View {
        let isSel = vm.selectedDevice?.id == dev.id
        let isHover = hoveredDeviceId == dev.id
        let badgeColor: Color = !dev.isOnline ? .secondary : (dev.transport == "USB" ? .green : .blue)

        return HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(badgeColor.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: dev.transport == "USB" ? "cable.connector" : (dev.isOnline ? "wifi" : "iphone.slash"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(badgeColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dev.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(dev.isOnline ? .primary : .secondary)
                Text("\(dev.model) · iOS \(dev.osVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(dev.transport)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.16))
                .foregroundColor(badgeColor)
                .cornerRadius(5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSel ? Color.accentColor.opacity(0.18) : (isHover ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSel ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .opacity(dev.isOnline ? 1.0 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDeviceId = hovering ? dev.id : (hoveredDeviceId == dev.id ? nil : hoveredDeviceId)
        }
        .onTapGesture {
            guard dev.isOnline else {
                vm.statusMessage = "\(dev.name) 当前离线，请解锁手机并保持同 Wi-Fi 或插上 USB"
                return
            }
            Task { await vm.selectDevice(dev) }
        }
    }

    private func appRow(_ app: IOSAppInfo) -> some View {
        let isSel = vm.selectedApp?.bundleId == app.bundleId
        let isHover = hoveredAppId == app.bundleId

        return HStack(spacing: 9) {
            appIconView(for: app)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.subheadline)
                        .fontWeight(isSel ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if app.builtByDeveloper {
                        Text("Dev")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.16))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSel ? Color.accentColor.opacity(0.20) : (isHover ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredAppId = hovering ? app.bundleId : (hoveredAppId == app.bundleId ? nil : hoveredAppId)
        }
        .onTapGesture {
            Task { await vm.selectApp(app) }
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(spacing: 0) {
            // 面包屑路径条
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        let parts = vm.currentPath.isEmpty ? [] : vm.currentPath.split(separator: "/").map(String.init)
                        breadcrumbButton(vm.selectedApp?.name ?? "未选择 App", isCurrent: parts.isEmpty) {
                            Task { await vm.openPath("") }
                        }
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, seg in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                            let target = parts[0...idx].joined(separator: "/")
                            breadcrumbButton(seg, isCurrent: idx == parts.count - 1) {
                                Task { await vm.openPath(target) }
                            }
                        }
                    }
                }

                Spacer()

                if vm.selectedApp != nil {
                    Text("\(vm.filteredEntries.count) 项")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.025))

            Divider()

            // 列头
            if vm.selectedApp != nil && vm.fileLoadError == nil && !vm.filteredEntries.isEmpty {
                HStack(spacing: 10) {
                    Text("名称")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("大小")
                        .frame(width: 80, alignment: .trailing)
                    Text("修改时间")
                        .frame(width: 125, alignment: .trailing)
                    Text("操作")
                        .frame(width: 145, alignment: .trailing)
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.02))
                Divider()
            }

            // 内容区 + 拖拽上传
            ZStack {
                if vm.selectedApp == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("选择左侧 iPhone 和 App 开始浏览沙盒")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("支持直接把文件拖入此窗口上传，或将沙盒文件直接拖出到桌面 / Finder")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErr = vm.fileLoadError {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.75))
                        Text("无法访问该 App 沙盒")
                            .font(.headline)
                        Text(loadErr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(vm.isLoading ? "加载中..." : "当前目录为空")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("可直接从 Finder 拖入文件上传到当前目录")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(vm.filteredEntries) { entry in
                                fileRow(entry)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                        )
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.accentColor)
                                Text("松开鼠标上传到 /\(vm.currentPath)")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        )
                        .padding(14)
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

    private func breadcrumbButton(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundColor(isCurrent ? .primary : .secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(vm.selectedApp == nil)
    }

    private func fileRow(_ entry: SandboxEntry) -> some View {
        let ext = URL(fileURLWithPath: entry.name).pathExtension.lowercased()
        let isAudio = !entry.isDir && audioExts.contains(ext)
        let isText = !entry.isDir && textExts.contains(ext)
        let isHover = hoveredEntryId == entry.id
        let isSel = selectedEntryId == entry.id

        return HStack(spacing: 10) {
            Image(systemName: entry.isDir ? "folder.fill" : (isAudio ? "waveform.circle.fill" : (isText ? "doc.text.fill" : "doc.fill")))
                .font(.system(size: 15))
                .foregroundColor(entry.isDir ? .accentColor : (isAudio ? .orange : (isText ? .teal : .secondary)))
                .frame(width: 20)

            Text(entry.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(entry.isDir ? "-" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(formatISO(entry.modified))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 125, alignment: .trailing)

            HStack(spacing: 4) {
                if isAudio {
                    rowActionIcon("play.fill", help: "试听音频", tint: .orange) {
                        Task { await vm.playAudioEntry(entry) }
                    }
                }
                if isText {
                    rowActionIcon("eye", help: "预览内容", tint: .teal) {
                        Task { await vm.previewTextFile(entry) }
                    }
                }
                if !entry.isDir {
                    rowActionIcon("square.and.arrow.down", help: "导出到 Mac", tint: .accentColor) {
                        Task { await vm.exportEntry(entry) }
                    }
                }
                rowActionIcon("trash", help: "删除", tint: .red) {
                    Task { await vm.deleteEntry(entry) }
                }
            }
            .opacity(isHover || isSel ? 1.0 : 0.25)
            .frame(width: 145, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSel ? Color.accentColor.opacity(0.18) : (isHover ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredEntryId = hovering ? entry.id : (hoveredEntryId == entry.id ? nil : hoveredEntryId)
        }
        .onTapGesture(count: 2) {
            openEntry(entry, isAudio: isAudio, isText: isText)
        }
        .onTapGesture(count: 1) {
            selectedEntryId = entry.id
        }
        .onDrag {
            vm.makeDragItemProvider(for: entry)
        }
        .contextMenu {
            if entry.isDir {
                Button("打开文件夹") { Task { await vm.openPath(entry.path) } }
            } else {
                if isAudio {
                    Button("试听音频") { Task { await vm.playAudioEntry(entry) } }
                }
                if isText {
                    Button("预览文本") { Task { await vm.previewTextFile(entry) } }
                }
                Button("用默认应用打开") { Task { await vm.openInFinder(entry) } }
                Button("导出到 Mac...") { Task { await vm.exportEntry(entry) } }
            }
            Divider()
            Button("复制沙盒路径") { vm.copyPathToPasteboard(entry.path) }
            Divider()
            Button("删除", role: .destructive) { Task { await vm.deleteEntry(entry) } }
        }
    }

    private func rowActionIcon(_ systemName: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(tint)
                .frame(width: 24, height: 22)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func openEntry(_ entry: SandboxEntry, isAudio: Bool, isText: Bool) {
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
            .keyboardShortcut(.space, modifiers: [])

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundColor(.orange)
                Text(entry.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(maxWidth: 210, alignment: .leading)

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
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭播放器")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if vm.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Text("USB & Wi-Fi 持续发现 · 支持文件双向拖拽")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 0.5)
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
