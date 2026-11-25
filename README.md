# SandBridge

轻量、零依赖的原生 macOS iOS 真机沙盒管理工具，基于 Apple 原生 `xcrun devicectl`。

**无需在 iOS App 里写任何代码**，插上 USB 或同局域网 Wi-Fi 即可稳定浏览任意开发版 App 的沙盒目录、单文件导出、拖拽上传、在线试听音频（支持 `.m4a` / `.wav` / 裸 `.pcm`）及预览 JSON/日志。

## 核心特性

- **零侵入访问真机沙盒**：直接基于 Xcode 原生 `xcrun devicectl`，支持 USB 与已配对 Wi-Fi，告别 Finder 断连和整包下载容器；
- **全目录管理**：快捷切根目录 / `Documents` / `Library/Caches` / `tmp`、面包屑导航、文件名搜索、单文件导出、拖拽上传、删除；
- **原生音频试听（含裸 `.pcm`）**：双击 `.m4a` / `.wav` / `.pcm` 直接播放，裸 `.pcm` 自动加 WAV 头并支持实时切换采样率（`48k / 44.1k / 16k`）和声道数（单/双声道）；
- **文本在线预览**：双击 `.json` / `.log` / `.txt` / `.qrc` 自动格式化预览；
- **自动拉取 App 图标**：支持 App Store 图标异步拉取与本地缓存，并自动兼容 `Dev` / `Debug` 后缀开发版。

## 系统要求

- macOS 13.0+
- 已安装 Xcode 15+（包含 `xcrun devicectl`）
- iOS 17+ 真机（已开启开发者模式并与本机配对）

## 安装与使用

1. 前往 GitHub **Releases** 下载最新的 `SandBridge-x.y.z.dmg`，拖入「应用程序」；
2. 首次打开若 macOS 提示“无法验证开发者”（未公证的 Ad-Hoc 签名版本），请右键点击 App 选择「打开」，或在终端执行一次：
   ```bash
   xattr -cr /Applications/SandBridge.app
   ```

## 本地构建与发布

```bash
# 本地编译 Release App + 打包 DMG / ZIP
chmod +x scripts/package_dmg.sh
./scripts/package_dmg.sh

# 推送 Tag 自动触发 GitHub Actions 编译并发布 GitHub Release
git tag v1.0.0
git push origin v1.0.0
```
