# 菜单栏最近下载工具

一个 macOS 菜单栏工具：快速查看最近下载的文件，并直接拖入 Codex、浏览器或其他应用，避免反复打开和排列访达窗口。

## 功能

- 菜单栏常驻，不占用 Dock。
- 展示 `~/Downloads` 中最近的 15 个文件（图标、名称、相对时间、大小）。
- 文件可跨应用拖放（Codex、Chrome、Safari 等）。
- 目录变化自动刷新。

## 开发

```bash
swift build          # 构建
swift test           # 运行测试
swift run RecentDownloads  # 本地运行（菜单栏出现图标）
```

## 打包为 .app

```bash
bash Scripts/build-app.sh
```

产物：`.build/app/最近下载.app`。首版为非沙盒本地运行版本，不签名、不公证、不上架。

## 打包为 .dmg（分享给其他 Mac 用户）

```bash
bash Scripts/build-dmg.sh
```

产物：`.build/最近下载.dmg`（内含应用和 /Applications 快捷方式）。

> **注意**：应用未签名、未公证。对方首次打开时需右键点击应用 →「打开」→ 确认，之后才能正常启动（Gatekeeper 提示"无法验证开发者"属预期行为）。

## 发布新版本（自动上传 Releases）

### 方式一：GitHub Actions（推荐，全自动）

仓库已配置 `.github/workflows/release.yml`。以后发布新版本只需：

```bash
git tag v1.1.0
git push origin v1.1.0
```

GitHub 云端自动：构建 Release → 运行测试 → 打包 DMG → 发布到 Releases（含自动生成更新说明）。

### 方式二：本地脚本

```bash
brew install gh && gh auth login   # 一次性
bash Scripts/release.sh v1.1.0     # 构建 DMG + 打 tag + 上传
```

### 手动打包

```bash
bash Scripts/build-dmg.sh
# 产物：.build/最近下载.dmg
```

## License

[MIT](LICENSE)
