import Foundation

struct IOSDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let osVersion: String
    let transport: String
    let tunnelState: String
    let isOnline: Bool
}

struct IOSAppInfo: Identifiable, Hashable {
    var id: String { bundleId }
    let name: String
    let bundleId: String
    let version: String
    let builtByDeveloper: Bool
}

struct SandboxEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDir: Bool
    let size: Int64
    let modified: String
}

enum DeviceCtlError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}

final class DeviceCtlService {
    static let shared = DeviceCtlService()
    private init() {}

    func listDevices() async throws -> [IOSDevice] {
        let json = try await runJSON(["list", "devices"])
        guard let result = json["result"] as? [String: Any],
              let list = result["devices"] as? [[String: Any]] else {
            return []
        }
        var out: [IOSDevice] = []
        for d in list {
            let conn = d["connectionProperties"] as? [String: Any] ?? [:]
            let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
            let props = d["deviceProperties"] as? [String: Any] ?? [:]
            guard (hw["reality"] as? String) == "physical" else { continue }
            let transport = conn["transportType"] as? String ?? "unknown"
            let tunnel = conn["tunnelState"] as? String ?? "unknown"
            let pairing = conn["pairingState"] as? String ?? "unknown"
            let online = (tunnel == "connected" || tunnel == "available" || transport == "wired" || transport == "localNetwork")
            guard online || pairing == "paired" else { continue }

            let udid = (hw["udid"] as? String) ?? (d["identifier"] as? String) ?? ""
            let name = (props["name"] as? String) ?? (hw["marketingName"] as? String) ?? "iPhone"
            let model = (hw["marketingName"] as? String) ?? (hw["productType"] as? String) ?? ""
            let osVer = (props["osVersionNumber"] as? String) ?? ""
            let tLabel: String
            if transport == "wired" {
                tLabel = "USB"
            } else if transport == "localNetwork" {
                tLabel = "Wi-Fi"
            } else if online {
                tLabel = "Wi-Fi"
            } else {
                tLabel = "离线"
            }
            out.append(IOSDevice(id: udid, name: name, model: model, osVersion: osVer, transport: tLabel, tunnelState: tunnel, isOnline: online))
        }
        out.sort {
            if $0.isOnline != $1.isOnline { return $0.isOnline }
            if $0.transport != $1.transport { return $0.transport == "USB" }
            return $0.name < $1.name
        }
        return out
    }

    func listApps(deviceId: String, devOnly: Bool) async throws -> [IOSAppInfo] {
        var args = ["device", "info", "apps", "--device", deviceId]
        if !devOnly {
            args.append("--include-all-apps")
        }
        let json = try await runJSON(args)
        guard let result = json["result"] as? [String: Any],
              let list = result["apps"] as? [[String: Any]] else {
            return []
        }
        var apps: [IOSAppInfo] = []
        for a in list {
            guard let bid = a["bundleIdentifier"] as? String, !bid.isEmpty else { continue }
            let isDev = (a["builtByDeveloper"] as? Bool) ?? false
            if devOnly && !isDev { continue }
            let name = (a["name"] as? String) ?? bid
            let ver = (a["version"] as? String) ?? ""
            apps.append(IOSAppInfo(name: name, bundleId: bid, version: ver, builtByDeveloper: isDev))
        }
        apps.sort {
            if $0.builtByDeveloper != $1.builtByDeveloper { return $0.builtByDeveloper }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return apps
    }

    func listFiles(deviceId: String, bundleId: String, subdir: String) async throws -> [SandboxEntry] {
        let cleanSub = subdir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var args = [
            "device", "info", "files",
            "--device", deviceId,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleId,
            "--no-recurse"
        ]
        if !cleanSub.isEmpty {
            args += ["--subdirectory", cleanSub]
        }
        let json = try await runJSON(args)
        guard let result = json["result"] as? [String: Any],
              let list = result["files"] as? [[String: Any]] else {
            return []
        }
        var dirs: [SandboxEntry] = []
        var files: [SandboxEntry] = []
        for f in list {
            let rawRel = (f["relativePath"] as? String) ?? (f["name"] as? String) ?? ""
            let rel = rawRel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rel.isEmpty || rel == cleanSub { continue }
            // devicectl 传入 --subdirectory 时，返回的 relativePath 是相对于该子目录的，需拼回完整沙盒路径
            let fullPath: String
            if cleanSub.isEmpty {
                fullPath = rel
            } else if rel.hasPrefix(cleanSub + "/") {
                fullPath = rel
            } else {
                fullPath = "\(cleanSub)/\(rel)"
            }
            let res = f["resources"] as? [String: Any] ?? [:]
            let meta = f["metadata"] as? [String: Any] ?? [:]
            let isDir = (res["isDirectory"] as? Bool) ?? false
            let size = (meta["size"] as? NSNumber)?.int64Value ?? 0
            let mod = (meta["lastModDate"] as? String) ?? ""
            let name = URL(fileURLWithPath: fullPath).lastPathComponent
            let entry = SandboxEntry(name: name, path: fullPath, isDir: isDir, size: size, modified: mod)
            if isDir { dirs.append(entry) } else { files.append(entry) }
        }
        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.modified > $1.modified }
        return dirs + files
    }

    func copyFromDevice(deviceId: String, bundleId: String, remotePath: String, destination: URL) async throws {
        let args = [
            "device", "copy", "from",
            "--device", deviceId,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleId,
            "--source", remotePath,
            "--destination", destination.path
        ]
        _ = try await runRaw(args)
    }

    func copyToDevice(deviceId: String, bundleId: String, localURL: URL, remoteDir: String) async throws {
        let cleanDir = remoteDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let dst = cleanDir.isEmpty ? localURL.lastPathComponent : "\(cleanDir)/\(localURL.lastPathComponent)"
        let args = [
            "device", "copy", "to",
            "--device", deviceId,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleId,
            "--source", localURL.path,
            "--destination", dst
        ]
        _ = try await runRaw(args)
    }

    func deleteFile(deviceId: String, bundleId: String, remotePath: String) async throws {
        let args = [
            "device", "remove",
            "--device", deviceId,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundleId,
            "--path", remotePath
        ]
        _ = try await runRaw(args)
    }

    static func wrapPcmAsWav(pcmData: Data, sampleRate: Int, channels: Int, bits: Int = 16) -> Data {
        var out = Data()
        func le<T: FixedWidthInteger>(_ v: T) {
            var val = v.littleEndian
            out.append(Data(bytes: &val, count: MemoryLayout<T>.size))
        }
        let byteRate = sampleRate * channels * (bits / 8)
        let blockAlign = channels * (bits / 8)
        out.append(Data("RIFF".utf8))
        le(UInt32(36 + pcmData.count))
        out.append(Data("WAVEfmt ".utf8))
        le(UInt32(16))
        le(UInt16(1))
        le(UInt16(channels))
        le(UInt32(sampleRate))
        le(UInt32(byteRate))
        le(UInt16(blockAlign))
        le(UInt16(bits))
        out.append(Data("data".utf8))
        le(UInt32(pcmData.count))
        out.append(pcmData)
        return out
    }

    // MARK: - Subprocess helpers

    private func runJSON(_ args: [String]) async throws -> [String: Any] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbridge_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await runRaw(args + ["--json-output", tmp.path])
        let data = try Data(contentsOf: tmp)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceCtlError.commandFailed("无法解析 devicectl 输出")
        }
        return obj
    }

    private func runRaw(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                proc.arguments = ["devicectl"] + args
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    if proc.terminationStatus != 0 {
                        let msg = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                        cont.resume(throwing: DeviceCtlError.commandFailed(msg.isEmpty ? "devicectl 执行失败 (\(proc.terminationStatus))" : msg))
                    } else {
                        cont.resume(returning: outStr)
                    }
                } catch {
                    cont.resume(throwing: DeviceCtlError.commandFailed("无法启动 xcrun devicectl：请确认已安装 Xcode 或 Command Line Tools"))
                }
            }
        }
    }
}
