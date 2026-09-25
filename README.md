# miniTools

[![CI](https://github.com/oh-my-brew/miniTools/actions/workflows/ci.yml/badge.svg)](https://github.com/oh-my-brew/miniTools/actions/workflows/ci.yml)

一个面向个人高频场景的轻量级 macOS 编码与转换工具。复制文本或图片后，通过全局快捷键打开操作面板，选择动作并回车，结果会直接写回剪贴板。

## 当前能力

- 文本识别与转换：URL、Base64、JSON Escape / Unescape、Unix 时间戳
- 文本工具：MD5、SHA256、SHA512、JSON Sort、Sort → Uniq、Sort → Count、当前时间戳
- 文本转图片：二维码 PNG
- 图片转文本：二维码识别、中文/英文 OCR
- 图片处理：PNG / JPEG 转换、可配置质量的 JPEG 压缩
- 交互：输入框实时筛选功能、方向键选择、回车执行、Command-1–9 直达、Tab 切换面板、Esc 清空筛选或关闭
- Safari 窗口切换：与编码转换共用一个全局快捷键，优先显示标签页组名称，按标题排序；使用单列并根据窗口数量自动调整面板高度
- 窗口控制：在当前显示器可用区域内调整活动窗口，并支持跨屏移动窗口和鼠标
- 合盖运行：手动保持 MacBook 合盖后继续运行；电量低于 20% 时暂停，高于 25% 时自动恢复
- DS_Store 管理：按需清理和监控磁盘中的 `.DS_Store`，可选择登录时启动 miniTools
- 使用统计：仅在本机统计成功完成的编码与转换、窗口管理和鼠标跨屏操作
- 性能与安全：图片识别和编码在后台执行；压缩结果没有变小时不会覆盖原剪贴板

自动识别只会把可靠候选项放到顶部并默认选中，仍需用户确认，不会自动覆盖原剪贴板。

## 运行与打包

要求 macOS 26 或更高版本、Apple Silicon (M 系列) Mac，以及 Xcode Command Line Tools。

本地调试请使用固定路径、稳定签名的应用包：

```bash
./Scripts/run-debug.sh
```

该命令会构建 Debug 版本、使用本机有效的 Apple Development 证书签名，替换固定位置的
`dist/miniTools.app`，退出旧进程后重新打开。不要使用 `swift run MiniTools` 调试依赖辅助功能
权限的功能；直接运行 SwiftPM 可执行文件没有稳定的应用签名，重建后可能需要重新授权。

生成可直接打开的 `.app`：

```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
open dist/miniTools.app
```

构建脚本不会再回退到 ad-hoc 签名。它会优先自动选择本机唯一的具名 Apple Development
证书；如果存在多个候选证书，使用下面的方式明确指定一个固定证书：

```bash
CODE_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./Scripts/build-app.sh
```

首次改用稳定签名时，需要在“系统设置 → 隐私与安全性 → 辅助功能”中删除旧的 miniTools
记录，再对 `dist/miniTools.app` 授权一次。后续只要 Apple Development 证书、应用路径和
Bundle ID 不变，本地调试重建就可以复用同一份授权。Homebrew 安装的 Developer ID 发行版
是另一份应用身份，首次迁移时可能需要单独授权一次。

默认面板唤起快捷键是 `⌃⌥⇧⌘Space`。面板会打开最后一次使用的功能，按 `Tab` 在 Safari 窗口与编码转换之间切换。Safari 面板使用 `ASDFQWERZXCVTGBYHUIOPL` 直接打开对应窗口、方向键或 `J/K` 上下选择、`Enter` 打开当前高亮窗口、`N` 新建 Safari 窗口、`M` 打开全部未使用标签页组的窗口、`Esc` 关闭。两个面板都不响应列表行鼠标点击，避免误触；应用启动后常驻菜单栏。

窗口控制默认使用 `⇧⌃⌥⌘`：`U/I/J/K` 对应四个角，重复触发在半宽和三分之一宽之间切换；`H/L` 对应左/右侧，重复触发同样先二分之一宽、再三分之一宽；`Y` 在上/下半屏之间切换；`O` 在右/左三分之一之间切换；`\` 铺满当前屏幕可用区域。切换到另一个区域时会重新从半宽开始，不沿用上一个区域的循环进度。设置中可以开启“使用 macOS 原生窗口布局”：系统菜单支持当前目标时直接调用 macOS 的布局或跨屏能力，否则自动回退到 miniTools 原有几何实现；只有确实调用到 macOS 原生能力时，右上角才提示“macOS 原生 · 目标尺寸”。该选项默认关闭。Safari 窗口切换和窗口控制共用辅助功能权限，首次使用需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 miniTools，不再需要 Safari 自动化权限。

同一组修饰键还支持：`P` 将活动窗口移动到下一块屏幕并保留相对位置，`;` 将鼠标移动到下一块屏幕中心并显示短暂定位动画，`Enter` 将活动窗口居中到当前屏幕。统一功能面板以及全部窗口/鼠标快捷键都可以在“设置”中单独录制。

状态栏菜单通过单个带勾选状态的“合盖运行”项目直接切换功能。
第一次开启需要在“系统设置 → 通用 → 登录项与扩展”中批准 miniTools 后台服务；之后不再重复请求管理员批准。
合盖功能开关会持久化。主应用每分钟读取 `SleepDisabled` 实际值：开关打开时，电量低于 20% 会确保实际值为 0，高于 25% 会确保实际值为 1；20%–25% 之间不修改。手动关闭会立即把实际值设为 0，此后只读取状态、不再自动修改。状态栏锤子旁的小点和设置页始终展示实际值。该功能会增加耗电与发热，
不应在收纳包内长时间使用。

后台 helper 按 XPC 请求启动，并在主应用断开后退出进程；退出不会修改 `SleepDisabled`。这样应用升级后不会继续运行旧版本 helper。

DS_Store 管理默认关闭。开启后使用 FSEvents 监听磁盘根目录，也可以立即从 `/` 开始递归
清理 `.DS_Store`。清理和监控都会跳过废纸篓、系统目录、挂载卷、应用包、符号链接和无法读取的目录。设置页显示本次运行成功删除的
数量和最近一次错误。若需登录后持续监控，可单独开启“登录时启动 miniTools”。该功能在
主应用内运行，不会停止、卸载或接管其他 DS_Store 服务。

设置中的定位动画以画廊一次展示全部效果，可直接启用多个效果、全部启用或全部关闭。
“使用统计”只在本机保存成功操作的动作标识、次数和时间；窗口管理会细化到具体目标尺寸（例如“左上区域 · 半宽”）。不统计 Safari 窗口、DS_Store
管理或合盖运行，也不记录剪贴板内容、窗口标题和文件信息。

## 测试

```bash
swift test
```

## 发行与 Homebrew

推送 `vYYYY.MM.DD.N` 标签后，GitHub Actions 会构建 arm64 应用，使用
Developer ID 签名并提交 Apple 公证，再生成 GitHub Release 和 SHA-256。Homebrew Tap
会定期检查 Release，通过 Autobump PR 更新 Cask。签名配置和发版步骤见
[DISTRIBUTION.md](DISTRIBUTION.md)。

## 代码结构

面向贡献者和后续 AI 编程的产品不变量、架构边界、签名隔离及最低验证要求见
[AGENTS.md](AGENTS.md)。修改交互、权限、构建或发行流程前请先阅读该文件。

- `App`：应用生命周期、状态栏菜单和功能编排
- `Features/FeaturePanel`：统一面板状态、键盘命令、布局策略和视觉规范
- `Features/EncodingConversion`：文本、图片、二维码、OCR 与编码转换面板
- `Features/SafariWindows`：Safari 窗口读取、排序、布局和切换面板
- `Features/WindowManagement`：窗口几何、辅助功能窗口控制和鼠标跨屏
- `Features/ClosedLidRunning`：合盖运行、电量暂停/恢复和特权 helper 客户端
- `Features/DSStoreManagement`：FSEvents 监控、清理策略、计数和登录启动状态
- `Shared`：辅助功能访问、全局快捷键、设置存储、本机使用统计和通用 UI

项目原创代码采用 [MIT License](LICENSE)。第三方图稿不包含在该许可授权范围内，来源与
许可状态见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。公开发行前仍需确认图标与
全部动画图稿的再分发权利。

MVP 严格读取剪贴板的第一个元素。图片识别使用 Vision，首次处理大图时可能需要短暂等待；识别期间仍可直接选择格式转换或压缩操作。
