# miniTools 工程上下文

本文件适用于整个仓库，供后续 AI 编程与代码评审使用。`README.md` 面向使用者，
`DISTRIBUTION.md` 记录发行操作；这里集中保存容易在迭代中被误改的产品约束、架构边界和验证要求。

## 项目定位

- miniTools 是 macOS 26+ 的菜单栏效率工具，核心场景是键盘优先的编码转换、Safari 窗口切换、窗口管理、鼠标侧键动作和手动合盖运行。
- 技术栈是 Swift 6.2、SwiftUI、AppKit、ApplicationServices、Carbon、CoreImage 与 Vision；项目由 Swift Package Manager 构建。
- 用户可见品牌写作 `miniTools`；Swift 模块、可执行文件和 Target 使用 `MiniTools`。
- Bundle ID 是 `com.omzcj.minitools`，应用为 `LSUIElement`，不显示 Dock 图标。
- 界面文案以简体中文为主。不要重新引入“剪贴板工具”“内容处理”等旧名称；当前功能名是“编码与转换”和“Safari 窗口”。
- 所有处理默认在本机完成。严格读取剪贴板第一个元素，成功后才按结果类型覆盖剪贴板。

## 不可随意破坏的产品约束

### 统一功能面板

- 全局快捷键只打开一个统一入口，默认是 `⌃⌥⇧⌘Space`；再次唤起时显示上次使用的面板。
- `Tab` 在“编码与转换”和“Safari 窗口”之间切换。顶部切换器与下方内容面板是两个分离的玻璃表面。
- 两个内容面板和顶部切换器等宽。面板切换、展开和调整高度不得出现跳动、残影或背景色受前台应用影响。
- 使用 macOS 26 原生 Liquid Glass API 和系统语义色。不要用自绘半透明背景模拟系统玻璃，也不要重新加入会造成布局跳动的隐式动画。
- 列表行不响应鼠标点击，避免悬停和轻微移动造成误操作；完整流程必须能只用键盘完成。
- `⌘,` 无论在哪个面板中都必须打开真实的设置窗口，不能生成空设置窗口。
- 面板关闭或切换后，迟到的异步任务不得更新界面或覆盖剪贴板。延续现有取消任务与 `sessionGeneration` 校验模式。

### 编码与转换

- 自动识别只负责推荐、排序和默认选中，绝不自动执行或覆盖剪贴板。
- 搜索框只接收 ASCII 英文字母、数字和分隔空格，并在编辑期间切换到英文输入源。
- 搜索后的可见结果必须重新分配 `⌘1`–`⌘9`，序号来自当前 `visibleActions`，不能沿用完整目录中的位置。
- 有推荐项时显示推荐分组；没有推荐项时，最前方最多显示 2 个最近使用动作。
- `↑/↓` 选择，`Enter` 执行，`⌘1`–`⌘9` 直达，`Tab` 切换面板。`Esc` 在有搜索内容时先清空，再次按下才关闭。
- 剪贴板摘要与输入预览属于内容面板，不与顶部切换器或标题栏合并。
- Vision、二维码和图片编码等较重工作在后台执行。图片压缩结果不小于原图时，不覆盖原剪贴板。

### Safari 窗口

- 通过 Accessibility AX API 读取和激活窗口，不使用 AppleScript，也不申请 Safari Automation 权限。
- 优先显示标签页组名称；没有标签页组时显示活动网页标题。按本地化标准标题排序，并用稳定标识作为相同标题的次排序条件。
- 窗口列表固定为单列，不提供搜索，不使用内部滚动区域；一次显示全部窗口，并根据数量调整面板高度。若受屏幕可用高度限制，优先保证稳定布局。
- 直达键固定为 `ASDFQWERZXCVTGBYHUIOPL`，按字母后立即打开对应窗口，不再要求回车确认；`N` 保留用于新建 Safari 窗口，不参与直达键分配。
- `↑/↓` 与 `J/K` 选择，`Enter` 打开高亮窗口，`N` 新建 Safari 窗口，`M` 打开全部未使用标签页组的窗口，`Tab` 切换面板，`Esc` 关闭。
- 不要给列表恢复鼠标点击，也不要改成多列。

### 窗口管理、鼠标侧键与定位动画

- 窗口移动和缩放基于当前屏幕 `visibleFrame`，并正确处理 AppKit 与 AX 坐标系转换。
- 窗口循环状态判断优先参考 WindowServer 的前台可见窗口 frame，AX frame 仅作为回退，兼容应用最小尺寸约束或 AX 返回请求值而非实际值的情况。
- 窗口布局命令及默认快捷键以 `WindowControlCatalog` 为唯一来源；循环尺寸的候选顺序属于交互行为，调整时必须同步测试。所有循环命令统一“先半宽/二分之一、再三分之一”的顺序，且当窗口位于其他区域时该快捷键必须从第一个候选开始，不能沿用上一个区域的循环进度。
- “使用 macOS 原生窗口布局”默认关闭；开启后通过目标应用的 AX 菜单项直接调用 macOS 布局和跨屏动作，不模拟系统快捷键。找不到、不可用或不匹配的系统动作必须回退到现有几何实现；只有确实调用到 macOS 原生能力时才在屏幕右上角提示“macOS 原生 · 目标尺寸”。
- 系统布局动作优先使用稳定的 AX 标识；跨屏菜单标题是动态且本地化的，应按目标显示器名称和 AppKit 本地化模板匹配。“将窗口移回 Mac”仅用于目标为内建显示器时。不得假定所有应用暴露相同菜单。
- `WindowAccessibilityHealth` 用 WindowServer 可见窗口与 AX 窗口角色交叉检查状态。检测到目标应用的 AX 状态过期时，应提示重启目标应用，不能静默按错误坐标继续。
- 即使只有一块屏幕，“鼠标移至下一屏”也要继续执行后续定位动画。
- 定位动画允许一个都不选；选中多个时轮流使用。设置页通过画廊一次展示全部效果，不再提供逐个播放的预览按钮。
- 鼠标侧键只支持物理 Button 4、Button 5，以及单击、双击、向上/下/左/右拖动；不支持长按。
- 侧键动作默认全部未分配。只拦截已分配的按键/手势，未分配事件尽量保留系统或应用原行为。
- 拖动阈值是相对当前屏幕宽高的比例，不是固定 pt。当前允许范围和默认值以 `MouseGestureConfiguration` 为准。
- 拖动反馈显示路径动画，不显示文字 Toast。

### 合盖运行

- 状态栏通过单个带勾选状态的“合盖运行”菜单项直接切换状态，不提供时长选项。
- 合盖运行仅允许用户手动开启或关闭，不检测 Codex、Claude 或其他进程状态，也不增加自动触发规则。
- helper 只允许开启、关闭和查询合盖运行状态，不得接受任意命令、路径或 `pmset` 参数；不跟踪 `disablesleep` 的设置者。
- 合盖功能开关与 `SleepDisabled` 实际值是两个独立状态；功能开关需要持久化。主应用无论开关状态都每分钟读取并展示实际值，状态栏锤子旁的小点只表示实际值为 1。
- 功能开关打开时，电量低于 20% 必须确保 `SleepDisabled` 为 0，高于 25% 必须确保其为 1，20%–25% 之间不修改；不判断或尊重其他程序的修改。手动关闭开关时立即设置一次 0，此后只读取、不主动修改。
- 不因温度、主应用连接异常、helper 异常、开盖、关机或重启主动恢复系统睡眠，也不保留时长关闭逻辑。
- helper 由 Mach service 按需启动，最后一个主应用 XPC 连接断开后只退出进程，不修改 `SleepDisabled`，避免应用升级后旧 helper 继续驻留。
- 非“应用程序”目录中的开发构建不得访问 `SMAppService` 状态或注册正式 helper，避免破坏 Background Task Management 记录。

### DS_Store 管理与登录启动

- DS_Store 管理是设置中的可选功能，默认关闭；开启后固定监听 `/`，立即清理也从 `/` 开始。
- FSEvents 事件需要按目标路径去重；删除成功后才累计本次删除数量，错误提示需要限频并保留最近一次错误。
- 递归清理和实时监控共用路径策略，必须排除 `.Trash`、`.Trashes`、系统目录、挂载卷、应用包和无权限目录，不得跟随符号链接进入其他路径。
- “登录时启动 miniTools”使用 `SMAppService.mainApp`，属于整个主应用的设置；非“应用程序”目录中的开发构建不得注册或查询正式登录项。
- 该功能在主应用内运行，不新增特权 helper，也不得停止、卸载或接管其他 DS_Store 服务。

### 使用统计

- 使用统计只保存在本机，独立于 `AppSettings`；只在动作确认成功后累计。
- 仅统计编码与转换、窗口管理、鼠标跨屏三类。窗口管理的循环命令按具体目标尺寸分别计数（例如 `upperLeft.1` → “左上区域 · 三分之一宽”）。Safari 窗口、DS_Store 管理、合盖运行、失败动作和自动事件不得计数。
- 只保存稳定动作 ID、展示名称、累计次数、按日次数和最近使用时间；不得记录剪贴板内容、窗口标题、文件路径或其他用户内容。

## 代码结构与职责

| 路径 | 职责与修改边界 |
| --- | --- |
| `Sources/MiniTools/App` | 应用生命周期、状态栏、设置窗口、功能面板编排和统一命令分发。不要把具体转换或 AX 实现塞入控制器。 |
| `Features/FeaturePanel` | 两个面板共享的命令、切换器、尺寸策略和原生玻璃视觉规范。面板等宽、分离表面及无跳动布局在这里统一治理。 |
| `Features/EncodingConversion` | 动作目录、剪贴板模型、文本/图片转换服务、搜索与编码面板状态。新增动作时优先扩展 Catalog 和 `ToolAction`，不要在 View 中写转换逻辑。 |
| `Features/SafariWindows` | Safari AX 窗口读取、标题推导、排序、布局、选择和激活。保持 Service、ViewModel、View 分层。 |
| `Features/WindowManagement` | 窗口几何、布局命令、AX 健康检查、跨屏鼠标移动和定位动画。 |
| `Features/MouseBindings` | 侧键事件监听、手势识别、动作配置和拖动路径反馈。 |
| `Features/ClosedLidRunning` | 合盖运行、电量暂停与恢复、后台服务状态和 XPC 客户端。 |
| `Features/DSStoreManagement` | 根目录 FSEvents 监控、DS_Store 清理策略、计数和登录启动状态。 |
| `Sources/MiniToolsPowerSupport` | 主应用与 root helper 共用的最小 XPC 协议、签名要求和 `pmset` 解析。 |
| `Sources/MiniToolsPowerHelper` | 受 `SMAppService` 管理的 root LaunchDaemon，只负责设置和查询合盖运行开关。 |
| `Shared` | Accessibility、统一 `AppCommand`、全局快捷键、设置持久化、本机使用统计和通用 UI。跨功能抽象应有两个以上实际调用方再放入这里。 |
| `Tests/MiniToolsTests` | 按功能目录放置单元测试。新增行为应优先在所属功能下补测试，而不是建立大型跨模块测试文件。 |
| `Scripts` | 可复现的本地构建、稳定签名调试、通用包构建与发行打包。签名和输出目录的隔离属于关键行为。 |
| `Support` | Info.plist、图标、状态栏资源及应用包支持文件。 |

以下类型是跨界面的事实来源，修改时不要在其他位置复制常量：

- `AppSettings`：UserDefaults 设置、默认值和旧版本迁移。
- `AppCommand`：快捷键与鼠标绑定可调用的统一动作模型。
- `WindowControlCatalog`：窗口动作描述、顺序和默认快捷键。
- `TextActionCatalog` / `ImageActionCatalog`：编码与转换动作目录。
- `FeaturePanelMetrics` / `FeaturePanelLayoutPolicy`：统一面板尺寸和布局。
- `FeaturePanelCommand`：面板级键盘命令。

重命名设置键、动作 ID 或默认快捷键时，必须检查并保留 `AppSettings` 中已有用户配置的迁移路径。

## 权限模型

| 功能 | 权限 |
| --- | --- |
| 剪贴板转换、二维码生成、OCR | 不需要辅助功能权限；OCR 使用系统 Vision。 |
| Safari 窗口读取与前置 | 辅助功能（Accessibility）。不使用 AppleScript 自动化权限。 |
| 活动窗口移动、缩放和跨屏 | 辅助功能（Accessibility）。 |
| Button 4/5 监听与拦截 | 辅助功能 + 输入监控（Input Monitoring）。 |
| 合盖运行 | 首次使用需管理员批准后台 LaunchDaemon；不依赖辅助功能或输入监控。 |
| DS_Store 管理 | 不需要辅助功能权限；受普通文件权限约束，无法读取的目录会跳过。登录启动由系统登录项管理。 |

权限异常先检查应用路径、Bundle ID、代码签名的 Designated Requirement 和目标应用 AX 状态，不要直接建议用户反复重置整个 TCC 数据库。

## 本地构建与签名

依赖辅助功能或输入监控的本地调试，必须使用：

```bash
./Scripts/run-debug.sh
```

该脚本使用稳定的 Apple Development 身份组装固定路径 `dist/miniTools.app`，再替换并启动应用。保持固定 Bundle ID、固定路径和稳定签名，才能让 TCC 权限在重复构建后继续有效。

不要使用 `swift run MiniTools` 验证权限相关功能；不要把 ad-hoc 构建覆盖到 `dist/miniTools.app`。发行包必须留在 `dist/release/miniTools.app`，否则下一次本地调试可能持续报告辅助功能状态异常。

`Scripts/build-app.sh` 不允许退回 ad-hoc。若本机存在多个 Apple Development 证书，应显式传入稳定身份：

```bash
CODE_SIGN_IDENTITY="Apple Development: Name (TEAMID)" ./Scripts/build-app.sh
```

`Scripts/package-release.sh` 只接受 Developer ID Application 身份，并生成启用 Hardened Runtime 和安全时间戳的通用发行包；`Scripts/notarize-release.sh` 负责上传 Apple 公证、staple ticket、验证 Gatekeeper 并重新生成最终 ZIP 和 SHA-256。不要把本地 Apple Development 签名用于公开发行，也不要让发行流程回退到 ad-hoc。

项目仅支持 Apple Silicon，主应用和合盖运行 helper 只生成 arm64 二进制，不再构建 x86_64。先签署 helper，再签署外层应用。正式 helper 仅由 `/Applications/miniTools.app` 管理；`dist/miniTools.app` 不得注册或查询正式后台服务。

## 最低验证要求

任何源码修改至少运行：

```bash
swift test
git diff --check
```

再按改动范围补充验证：

| 改动 | 额外验证 |
| --- | --- |
| UI、快捷键、AX、鼠标监听 | `./Scripts/run-debug.sh`，手动覆盖相关键盘路径和权限状态。 |
| Info.plist | `plutil -lint Support/Info.plist`。 |
| Shell 脚本 | `bash -n Scripts/*.sh`。 |
| 架构或依赖 | `swift build -c release --triple arm64-apple-macosx26.0 --scratch-path .build/ci-arm64`。 |
| 发行打包 | 校验 ZIP 的 SHA-256、`lipo -archs` 为 arm64，并检查 `codesign`、`stapler validate` 与 `spctl --assess`。不要启动发行包代替固定路径的稳定签名调试包。 |

若环境不允许完成某项运行时验证，交付时必须明确写出未验证项，不能把“编译通过”描述成“功能已验证”。

## 版本、GitHub Release 与 Homebrew

- `Support/Info.plist` 的展示版本使用 `YYYY.MM.DD`。
- Git 标签使用 `vYYYY.MM.DD.N`；GitHub Release 产物和 Homebrew Cask 使用不带 `v` 的 `YYYY.MM.DD.N`，同一天从 `1` 开始递增。
- `.github/workflows/ci.yml` 负责 push、PR 和手动 CI；`.github/workflows/release.yml` 只由 `v*` 标签触发，并校验标签日期与 Info.plist 一致。
- 正常顺序是：更新展示版本并提交 → 推送 → 等待 CI 成功 → 创建带注释标签并推送 → 等待 Release 完成 → 触发 Tap Autobump。
- Homebrew Tap 位于同级仓库 `../homebrew-tap`，Cask 是 `Casks/minitools.rb`。
- Tap 的 Autobump 只创建升级 PR，不会自动合并。BrewTestBot 通过后，合并仍是单独的外部写操作。
- 不要假定应用 Release workflow 会直接修改 Homebrew Tap；当前两条流水线相互独立。
- 创建标签/Release、触发 Autobump、合并 Tap PR 等会改变远端状态的操作，必须来自用户明确授权。

完整发行命令、Gatekeeper 限制和公开发行检查见 `DISTRIBUTION.md`。

## 资源与许可

- 原创代码使用 MIT License。
- Smartisan 风格锤子图标和写轮眼动画资源不自动包含在 MIT 授权中，来源与状态见 `THIRD_PARTY_NOTICES.md`。
- 在确认再分发权利或替换为原创资源前，不要把当前图稿描述为适合无条件公开发行。

## 修改时的工作约定

- 开始前查看 `git status`，保留用户和其他会话留下的无关改动；不要通过 reset、checkout 等方式清除它们。
- 优先修正产生问题的状态模型、布局策略或服务边界，避免继续堆叠仅对单一截图生效的 UI 补丁。
- AppKit/SwiftUI 桥接处尤其注意主线程、窗口生命周期、隐式动画和异步回调越界。
- 添加新功能时同步检查设置入口、`AppCommand`、快捷键/鼠标可分配性、状态栏文案和测试，但不要为了“统一”制造没有实际复用价值的抽象。
- 用户可见行为、默认值、权限或发行方式发生变化时，同步更新 README、DISTRIBUTION 和本文件中对应部分。
