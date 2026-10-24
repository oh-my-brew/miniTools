# miniTools 自动发行

## 自动发行（2026-10-25 用户决定）

开发完成后立即从固定源码提交启动 `.github/workflows/beta.yml`，不等源码 CI 或人工体验确认。
同仓库、非 draft 的开发 PR 添加 `release` 标签后，后续 source 更新会自动请求新候选；
也可由仓库 writer 对已有同仓库、非 draft 开发 PR 的准确 head 派发：

```sh
gh workflow run beta.yml --ref master --field source_ref=<40位准确源码SHA>
```

- 受信任默认分支 workflow 调用固定 SHA 的 brew-ci 协调脚本，在独立 `release/auto-<run-id>` 分支准备版本候选，再以普通非强推快进追加到现有开发 PR 分支；不修改本地工作树。以当前默认分支合入请求源码后，分配新的 `YYYY.MM.DD.N`，开发 PR 指向准确候选 commit/tree。组织禁止 Actions 建 PR 的策略保持不变。
- 包构建与单元/回归测试、CodeQL 快速语言扫描并行。Beta 只等包和必要分发验证，不等质量测试；Beta 可在安装体验前因 CI 已通过而自动提升。
- Beta、manifest、SHA 不可覆盖。重试已存在的 Beta 时下载原制品，不重新构建。失败保留候选与 CI 证据；修复后创建新版本，旧版本不覆盖。
- `release-state` 分支保留最新候选与版本预留。准备候选、移动 Beta feed、正式提升共用 publication concurrency；构建/测试不持有发布锁。发布前核对候选身份及开发 PR 最新 head，已取代候选不得写 feed 或正式版。
- 自动测试报告到准确候选 SHA，保留原有严格分支保护。CI 成功后以 squash 合入候选 PR，要求合入 tree 与已测试候选 tree 完全一致；有冲突或并发基线变化时停止，不绕过保护，不把不同源码当作同一候选。
- 正式版从 GitHub 下载 Beta 原制品，验证 manifest 和 SHA，然后发布相同字节；不重新构建、签名或公证。正式标签指向同 tree 的合入 commit，manifest 保留 source/candidate 身份。
- Git 标签使用每仓库独立 SSH 签名密钥，私钥在 `RELEASE_SIGNING_KEY` Actions Secret，本机恢复入口为 login Keychain 的 service `github-fast-release-signing`、account `oh-my-brew/miniTools`。公钥固定在默认分支 `.github/release-signers`，以 `git verify-tag` 验证。与旧版依赖 GitHub 账号签名登记的验证方式不同，新的签名信任锚是仓库公钥；GitHub 账号未登记该公钥时 UI 可能显示 Unverified，但流水线必须通过固定公钥的密码学验证。
- 不再需要发布 subagent、`release-approved` 标签、人工复制候选 SHA 批准或单独 Promote 派发。失败任务可从同一 Actions run 重跑；新源码使用新请求。产品 Release 完成不等待 Tap，不升级设备，不发送飞书通知。

## 签名、公证与发布资产

`fast_beta` lane 复用只读 Fastlane Match 和固定版本 apple-ci，先构建 arm64 主应用及 helper、
使用 Developer ID 签名，再执行 Apple 公证、staple、Gatekeeper 检查；质量测试单独并行。
Swift/Ruby 依赖与兼容构建输出可缓存，Apple 凭据和签名身份不进入缓存或普通 Artifact。

每个不可变 Beta 包含 ZIP、SHA-256、release-manifest.json、签名 appcast-beta.xml 与稳定
appcast.xml。两个 feed 都在同一次签名构建后生成，正式提升只复制对应资产。
滚动 `beta` Release 只更新 feed；不可变候选不移动。完整验收保留 tag、run、tree、SHA、
Developer ID、公证、helper、arm64 和 Sparkle 签名证据，不启动本地应用。

## 更新渠道

应用状态菜单提供“检查更新…”，通过 Sparkle 读取 GitHub Latest Release 的签名
`appcast.xml`；“检查 Beta 更新…”读取 `beta` prerelease 的独立 `appcast-beta.xml`。
两个入口都只执行手动检查，不持久切换通道，不启用后台定时检查或静默更新。beta appcast
指向不可变候选 Release，稳定 appcast 指向正式 Release；更新包和 feed 都必须通过嵌入
应用的 EdDSA 公钥验证。

GitHub `Latest` 和 Homebrew 只观察正式 Release。所有候选和滚动 `beta` Release 必须保持
`prerelease=true`；不得把 beta 标为 Latest，也不得让 Homebrew Tap 处理 beta 标签。

## Homebrew Tap

`oh-my-brew/homebrew-tap` 中的 `minitools` Cask 固定下载对应版本的 GitHub Release。
Tap 的定时 Autobump 工作流发现新版本后，会自动创建更新 Cask 版本和 SHA-256 的 PR。
产品 Release 不触发该工作流，也不等待 Tap PR 或三机安装；这些由独立的 Homebrew
维护流程处理。

用户可执行：

```bash
brew install --cask oh-my-brew/tap/minitools
```

合盖运行的 LaunchDaemon 通过 `SMAppService` 从应用包内注册。Cask 必须把应用安装到
`/Applications`，不能把 helper 单独复制到系统目录；升级时保持 Bundle ID、Team ID、helper
label 和签名身份不变，才能复用已有后台项目批准。

## Gatekeeper

Release 使用 Developer ID 签名并经过 Apple 公证，Gatekeeper 应直接接受。首次从旧的
ad-hoc 版本迁移到 Developer ID 版本时，系统可能将其视为一次签名身份变更；辅助功能和
输入监控权限可能需要重新授权一次。后续版本必须维持 Bundle ID `com.omzcj.minitools`、
Team ID `566UG6DQ7E` 和 Developer ID 签名，避免再次破坏 TCC 权限身份。Safari 窗口切换
和窗口管理需要辅助功能权限；使用鼠标 Button 4/5 绑定时还需要输入监控权限。Carbon
全局快捷键本身不依赖辅助功能权限。

## 公开发行前检查

项目包含第三方图稿和商标相关素材。面向个人设备或私有分发的风险较小；提交 Homebrew
官方 Cask 或公开推广前，应替换为原创素材并复核 `THIRD_PARTY_NOTICES.md` 中的许可状态。

## 响应性能诊断

统一面板与剪贴板管线通过系统 Instruments 的 `com.omzcj.minitools` / `Responsiveness`
signpost 记录固定阶段名、耗时和节点数量，不记录标题、URL、路径或剪贴板内容。
`PanelHotkeyMainQueue`、`SafariEnumerateWindows`、`SafariWebAreaLookup`、`SafariWindowScan`、
`PanelOrderedFront`、`PanelDrawSubmitted`、`PanelRevealComplete` 可用于区分主线程排队、AX 扫描及呈现阶段；
绘制提交不等于屏幕首帧呈现，实际首帧/掉帧需另用 Instruments 采样。
自动化以假 AX 客户端和私有剪贴板验证取消、缓存身份、映射冻结、后台处理及停止后的结果丢弃，
不启动应用。HTML-only 剪贴板的系统导入仍遵守主线程约束；不能把自动测试或签名公证通过描述为
实际响应时间已经改善，交付时需保留运行时未验证说明。

Safari 最小化恢复的自动测试注入 AX 状态、返回码、时钟与等待，覆盖延迟恢复、超时后实际成功、有限重试、永久失败、批量继续和面板关闭取消；不操作真实 Safari。Dock 动画、真实焦点切换和应用内更新仍需用户体验，不能由测试或公证结果代替。

Swift 常规 CI 保留单元测试所需编译；发行配置的 arm64 构建由快速出包 job 负责，避免
在 CI 和发行路径重复构建同一 Release。主应用/Helper 的真实权限与交互仍由用户体验，
自动发布不宣称这些运行时行为已人工验收。
