# miniTools 自动发行

## 自动发行（2026-10-25 用户决定）

开发完成后立即从固定源码提交启动 `.github/workflows/beta.yml`，不等源码 CI 或人工体验确认。
同仓库、非 draft 的开发 PR 添加 `release` 标签后，后续 source 更新会自动请求新候选；
也可由仓库 writer 对本仓库分支的准确 head 派发：

```sh
gh workflow run beta.yml --ref master --field source_ref=<40位准确源码SHA>
```

- 受信任默认分支 workflow 调用固定 SHA 的 brew-ci 协调脚本，创建独立 `release/auto-<run-id>` 分支与候选 PR，不回写开发分支或本地工作树。以当前默认分支合入请求源码后分配新的 `YYYY.MM.DD.N`，候选 PR 指向准确 commit/tree。组织允许相关权限，只在这两个产品仓库启用 Actions 创建候选 PR。
- 包构建与单元/回归测试、CodeQL 快速语言扫描并行。Beta 只等包和必要分发验证，不等质量测试；Beta 可在安装体验前因 CI 已通过而自动提升。
- Beta、manifest、SHA 不可覆盖。重试已存在的 Beta 时下载原制品，不重新构建。失败保留候选与 CI 证据；修复后创建新版本，旧版本不覆盖。
- `release-state` 分支保留最新候选与版本预留。准备候选、移动 Beta feed、正式提升共用 publication concurrency；构建/测试不持有发布锁。发布前核对候选身份及开发 PR 最新 head，已取代候选不得写 feed 或正式版。
- 自动测试报告到准确候选 SHA，保留原有严格分支保护。CI 成功后以 squash 合入候选 PR，要求合入 tree 与已测试候选 tree 完全一致；有冲突或并发基线变化时停止，不绕过保护，不把不同源码当作同一候选。
- 正式版从 GitHub 下载 Beta 原制品，验证 manifest 和 SHA，然后发布相同字节；不重新构建、签名或公证。正式标签指向同 tree 的合入 commit，manifest 保留 source/candidate 身份。
- 不要求 Git 标签签名，不为此维护额外密钥；正式标签仍不可覆盖，指向受保护合入且 tree 与候选一致的 commit。应用签名、公证及更新签名不受此简化影响。
- 不再需要发布 subagent、`release-approved` 标签、人工复制候选 SHA 批准或单独 Promote 派发。失败任务可从同一 Actions run 重跑；新源码使用新请求。产品 Release 完成不等待 Tap，不升级设备，不发送飞书通知。

## 签名、公证与发布资产

`fast_beta` lane 复用只读 Fastlane Match 和固定版本 apple-ci，先构建 arm64 主应用及 helper、
使用 Developer ID 签名，再执行 Apple 公证、staple、Gatekeeper 检查；质量测试单独并行。窗口调整修复复用既有检查入口，以内存伪读写作回归；不安装目标应用或增加 GUI 验证任务，发行自动化通过不代表真实窗口交互已验收。定向窗口兼容版本沿用同一流程；测试覆盖异步请求互相覆盖、屏幕截断、最小尺寸贴边、动画状态恢复及取消，均用内存/虚拟时间。实际流畅度、贴边和临时AX动画属性的支持情况仍需用户反馈，诊断快照不作为交互验收。
跨屏比例设置复用现有候选检查，纯内存回归覆盖上下半屏/角落、负坐标屏幕、往返舍入、尺寸约束贴边、默认与持久化、诊断序列化；不增加 CI 任务或 GUI 测试。用户需在设置中主动开启并体验，自动化通过不代表真实跨屏已验收。
兼容应用名单的设置持久化、空名单/移除默认项、精确匹配、重复/无效标识、元信息解析与动作快照通过隔离回归验证；不启动应用或系统选择器，不增加 CI 任务。用户添加备忘录后的真实窗口效果仍需体验验收。
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

## 验证职责（2026-11-07）

常规开发与发行不再要求本地 `swift test`、构建或 macOS 平台校验。源码 PR CI 和准确发行候选
均在 GitHub Actions macOS runner 调用 `Scripts/ci-check.sh`，统一运行 Swift 单元测试、发行
回归测试、Info.plist 和 Shell 校验；测试失败保持候选证据并修复，不取消质量或分支保护门禁。
源码 PR 合入后可使用受信任 `master` workflow 按合入后的准确 branch head SHA 派发发行，
以实际 Actions run、候选身份和最终制品校验验证流程。签名、公证、架构、Gatekeeper 与更新
签名检查继续由发行 Actions 执行。本机仅审阅源码、检查 diff、发起和查询 Actions，不安装或启动应用。

## 本次变更

- 2026-11-10：键盘映射新增默认关闭的 Homerow 三键组（四修饰键+M/逗号/句号 → Control+同键）与 Ghostty 斜杠（四修饰键+/ → Control+/）；若启用 Caps Lock 前缀，同样可用 Caps 加对应键触发，miniTools 已注册四修饰键优先。隔离状态机测试验证精确匹配、重复按键、释放和冲突优先级；真实 Homerow/Ghostty 响应仍需用户体验。

- 2026-11-10：在“尺寸与位置”中，从占满或接近占满屏幕可用区域的窗口切到全宽半高时，对齐可用区域上半屏；其他尺寸变化仍按既有居中/角锚点规则。同尺寸无操作与兼容名单策略保持不变。新增几何与兼容路径最小高度隔离回归，由本次准确候选的 GitHub Actions 验证；真实窗口效果仍需用户体验。

- 2026-11-09：在“尺寸与位置”方案中，实际宽高已经匹配目标时仍无操作；需要改变尺寸且当前宽高均与屏幕可用区域相差不超过8pt时先选居中，而非把全屏的左上角当成优先锚点。其他角匹配顺序和8pt坐标容差保持原规则。现有候选测试覆盖全屏与接近全屏、贴边半屏、受限尺寸下的居中；真实AX交互仍由用户体验。

- 2026-11-08：最新默认尺寸键为反斜杠/I/J/K、四角为U/H/O/L，仅迁移当前上一版默认保留自定义。尺寸变化优先固定已贴边的窗口角（左上→左下→右上→右下，横纵各8pt），无匹配则居中；同尺寸不动。现有候选检查覆盖实际角偏差、优先顺序、无匹配居中、兼容受限尺寸及当前默认迁移；不新增CI任务或GUI测试，真实交互由用户体验。

- 2026-11-08：按用户截图更新尺寸与位置默认键（尺寸为反斜杠/H/L/O，四角为U/J/I/K），一次迁移旧默认并保留自定义。当前宽高已匹配目标时跳过写入和自动居中，诊断记录unchangedSize。现有候选检查新增默认/迁移/持久化及尺寸幂等几何测试；不增加CI或GUI任务，交互仍由用户体验。

- 2026-11-08：尺寸与位置方案改为Y/H/O/L四角对齐，取消H/L尺寸识别和循环，保持当前尺寸；经典布局不变。沿用现有候选检查，覆盖负坐标屏幕、任意/满宽满高/超屏尺寸、重复幂等、兼容显式角锚点、定位不写尺寸及旧自定义绑定保留；不增加CI job或GUI验证，真实窗口行为待体验。

- 2026-11-08：设置分类调整（通用的授权/版本、编码与工具的面板快捷键/JPEG质量）、跨屏分号/单引号默认值及一次迁移、默认兼容名单新增备忘录、U短按全宽全高/长按全宽半高、I保持原来。现有Actions覆盖迁移/自定义保留、显式名单保留、U/H/L几何与I保持原来；不启动系统授权或真实应用，权限展示与交互需用户体验。

- 此前曾移除“尺寸与位置”方案；2026-11-08 恢复为主动启用的可选方案，默认继续经典布局，长按默认 200ms 可调。复用当前 AX 兼容、跨屏与诊断实现，保留经典快捷键、鼠标绑定和统计。新增几何、配置、位置只写坐标与虚拟长按测试，纳入现有候选检查，不增加 CI job 或 GUI 验证；真实交互由用户体验。
- 自动化验证统一交由 GitHub CI / Actions，本次通过新版本发行验证该流程。前一提交在 Linux 上未执行的 Swift 测试由本次远端源码和候选检查覆盖；最终结果以对应 Actions run 为准，真实窗口交互仍未验证。
