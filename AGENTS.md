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

## 最低验证要求

任何源码修改至少运行不会启动应用或修改真实系统状态的自动化检查：

```bash
swift test
git diff --check
```

再按改动范围补充验证：

| 改动 | 额外验证 |
| --- | --- |
| UI、快捷键、AX、鼠标监听 | 补充可隔离的单元测试；不运行 `./Scripts/run-debug.sh` 或手动功能测试，交付时明确记录运行时未验证。 |
| Info.plist | `plutil -lint Support/Info.plist`。 |
| Shell 脚本 | `bash -n Scripts/*.sh`。 |
| 架构或依赖 | `swift build -c release --triple arm64-apple-macosx26.0 --scratch-path .build/ci-arm64`。 |
| 发行打包 | 校验 ZIP 的 SHA-256、`lipo -archs` 为 arm64，并检查 `codesign`、`stapler validate` 与 `spctl --assess`。不要启动发行包代替固定路径的稳定签名调试包。 |

开发与发行会话默认不做本机功能测试。交付时必须明确写出运行时未验证项，不能把编译或单元测试通过描述成“功能已验证”。

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

## 修改时的工作约定

- 开始前查看 `git status`，保留用户和其他会话留下的无关改动；不要通过 reset、checkout 等方式清除它们。
- 优先修正产生问题的状态模型、布局策略或服务边界，避免继续堆叠仅对单一截图生效的 UI 补丁。
- AppKit/SwiftUI 桥接处尤其注意主线程、窗口生命周期、隐式动画和异步回调越界。
- 添加新功能时同步检查设置入口、`AppCommand`、快捷键/鼠标可分配性、状态栏文案和测试，但不要为了“统一”制造没有实际复用价值的抽象。
- 用户可见行为、默认值、权限或发行方式发生变化时，同步更新 README、DISTRIBUTION 和本文件中对应部分。
