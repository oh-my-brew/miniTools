# miniTools 工程上下文

本文件适用于整个仓库，供后续 AI 编程与代码评审使用。`README.md` 面向使用者，
`DISTRIBUTION.md` 记录发行操作，[docs/engineering.md](docs/engineering.md) 保存产品约束、架构和权限；本文件保存助手操作与验证要求。

## 项目定位

- miniTools 是 macOS 26+ 的菜单栏效率工具，核心场景是键盘优先的剪贴板历史、编码转换、Safari 窗口切换、窗口管理、鼠标侧键动作和手动合盖运行。
- 技术栈是 Swift 6.2、SwiftUI、AppKit、ApplicationServices、Carbon、CoreImage 与 Vision；项目由 Swift Package Manager 构建。
- 用户可见品牌写作 `miniTools`；Swift 模块、可执行文件和 Target 使用 `MiniTools`。
- Bundle ID 是 `com.omzcj.minitools`，应用为 `LSUIElement`，不显示 Dock 图标。
- 界面文案以简体中文为主。不要重新引入“剪贴板工具”“内容处理”等旧名称；当前功能名是“编码与转换”和“Safari 窗口”。
- 所有处理默认在本机完成。严格读取剪贴板第一个元素，成功后才按结果类型覆盖剪贴板。

## 开工入口

先检查Git状态并保留用户及其他会话修改；不reset、clean、stash、强推或擅自切分支。
修改功能前读取 [docs/engineering.md](docs/engineering.md) 中对应的产品约束、架构和权限章节。
保持本机数据、既有用户配置迁移、稳定应用身份、异步取消和主线程边界，不以真实剪贴板、Safari或系统设置进行常规测试。

## 本地构建与签名

`Scripts/run-debug.sh` 仅供用户明确要求的本地功能调试使用；常规开发会话不得运行它，也不得启动本地构建验证真实功能：

```bash
./Scripts/run-debug.sh
```

该脚本使用稳定的 Apple Development 身份组装固定路径 `dist/miniTools.app`，再替换并启动应用。获得明确本地调试要求时，必须保持固定 Bundle ID、固定路径和稳定签名，才能让 TCC 权限在重复构建后继续有效。

不要使用 `swift run MiniTools` 验证权限相关功能；不要把 ad-hoc 构建覆盖到 `dist/miniTools.app`。发行包必须留在 `dist/release/miniTools.app`，否则下一次本地调试可能持续报告辅助功能状态异常。

`Scripts/build-app.sh` 不允许退回 ad-hoc。若本机存在多个 Apple Development 证书，应显式传入稳定身份：

```bash
CODE_SIGN_IDENTITY="Apple Development: Name (TEAMID)" ./Scripts/build-app.sh
```

`Scripts/package-release.sh` 只接受 Developer ID Application 身份，并生成启用 Hardened Runtime 和安全时间戳的通用发行包；`Scripts/notarize-release.sh` 负责上传 Apple 公证、staple ticket、验证 Gatekeeper 并重新生成最终 ZIP 和 SHA-256。不要把本地 Apple Development 签名用于公开发行，也不要让发行流程回退到 ad-hoc。

项目仅支持 Apple Silicon，主应用和合盖运行 helper 只生成 arm64 二进制，不再构建 x86_64。先签署 helper，再签署外层应用。正式 helper 仅由 `/Applications/miniTools.app` 管理；`dist/miniTools.app` 不得注册或查询正式后台服务。

## 自动化验证（GitHub Actions）

常规开发和发行会话不在本地执行 `swift test`、`swift build` 或 macOS 平台校验；不要求开发机安装 Swift/Xcode，也不借助其他设备绕行测试。自动化检查统一在 GitHub CI / Actions 的 macOS runner 上执行，不能因为本机缺少工具链跳过远端质量门禁。

- `.github/workflows/ci.yml` 在源码 PR、主分支推送及手动派发时运行 `Scripts/ci-check.sh`。
- `.github/workflows/beta.yml` 对准确候选 SHA 运行同一检查入口，与签名打包并行；测试或安全检查失败不得提升正式版。
- `Scripts/ci-check.sh` 统一执行工具链报告、`git diff --check`、Info.plist 校验、Shell 语法检查、发行回归测试和 `swift test`。架构或依赖变化时，在 Actions 补充 arm64 release 构建验证。
- UI、快捷键、AX、鼠标监听变更需补充可隔离单元测试；测试不得启动应用、操作真实剪贴板、Safari、系统设置或发送真实输入。窗口调整通过内存矩形和伪读写验证，不安装第三方应用、不增加 GUI 自动化、CI job 或矩阵；真实流畅度与到位情况由用户体验反馈。
- 本地仅做源码审阅、Git 状态和 `git diff --check` 等无需 macOS 的轻量检查；提交不以本地 Swift 测试为前置条件。交付须记录实际源码/候选 SHA、Actions run 和结果，不能用其他提交的成功结果代替。
- 发行 Actions 保留 ZIP SHA-256、主应用/helper 的 arm64、Developer ID 签名、Apple 公证、stapling、Gatekeeper 和 Sparkle 签名验证；不启动发行包代替固定路径的稳定签名调试包。

开发与发行会话默认不做本机功能测试。交付时明确区分远端自动化结果与运行时未验证项，不能把编译或单元测试通过描述成“功能已验证”。本地功能调试仅按用户明确要求执行，仍须遵守上文稳定路径和签名约束。

## 发行边界

- 发行入口、候选身份与失败恢复统一见 [DISTRIBUTION.md](DISTRIBUTION.md)，从准确源码请求Actions独立候选。
- Beta构建与质量检查并行；必需检查通过后自动提升同一ZIP，不等人工批准、不依赖发布代理。
- 保留Developer ID、Team ID、helper身份、Apple公证、stapling、Sparkle签名与必要CI；取消额外Git标签签名门禁不改变应用签名要求。
- 过期候选不得写feed或正式版；不重建或覆盖已发布制品。产品Release不等待Tap、不升级设备、不发送飞书通知。
- 文档修改不自动发行。普通开发不启动应用；自动化通过不代表真实权限、交互和性能已验收。

## 资源与许可

- 原创代码使用 MIT License。
- Smartisan 风格锤子图标和写轮眼动画资源不自动包含在 MIT 授权中，来源与状态见 `THIRD_PARTY_NOTICES.md`。
- 在确认再分发权利或替换为原创资源前，不要把当前图稿描述为适合无条件公开发行。

## 窗口管理

- 仅保留经典布局；“尺寸与位置”方案、专属快捷键和长按设置已移除。旧配置不再参与注册或动作分派，不迁移覆盖经典布局快捷键、鼠标绑定或历史统计。

## 修改时的工作约定

- 开始前查看 `git status`，保留用户和其他会话留下的无关改动；不要通过 reset、checkout 等方式清除它们。
- 优先修正产生问题的状态模型、布局策略或服务边界，避免继续堆叠仅对单一截图生效的 UI 补丁。
- AppKit/SwiftUI 桥接处尤其注意主线程、窗口生命周期、隐式动画和异步回调越界。
- 添加新功能时同步检查设置入口、`AppCommand`、快捷键/鼠标可分配性、状态栏文案和测试，但不要为了“统一”制造没有实际复用价值的抽象。
- 用户可见行为、默认值、权限或发行方式发生变化时，同步更新 README、DISTRIBUTION 和本文件中对应部分。
