# 产品发行与应用内更新

## 候选 beta

开发代码进入 `master` 且源码 CI 通过后，后台 Beta Release subagent 使用独立 worktree：

1. 从远端默认分支中的准确开发 commit 创建单一候选 commit，只修改 `Support/Info.plist` 的 `CFBundleShortVersionString` 四段版本字段。
2. 以候选 commit 派发 `Beta Candidate` workflow，并把同一 commit 作为 `source_commit` 输入。
3. CI 运行测试，构建 arm64 主程序及 helper，完成 Developer ID 签名、Apple 公证、staple、Gatekeeper 和 SHA-256 校验。
4. 创建不可变的 `vYYYY.MM.DD.N-beta.RUN_NUMBER` prerelease，上传 ZIP、校验文件和签名 beta appcast。
5. 更新可移动的 `beta` prerelease 中的 `appcast-beta.xml`；它只指向不可变候选资产。
6. 回报候选标签、准确源码 commit 和 ZIP SHA-256，不自动提升正式版。

候选分支推送后，使用准确 commit 派发，不允许用会继续移动的分支名充当身份：

```bash
candidate_commit="$(git rev-parse HEAD)"
gh workflow run beta.yml \
  --ref "release/miniTools-YYYY.MM.DD.N" \
  -f "source_commit=$candidate_commit"
```

Workflow 的 preflight 会要求 checkout、事件 `GITHUB_SHA` 和 `source_commit` 三者完全相同；候选必须是非 merge 的单一版本 commit，其父提交已经位于远端默认分支，且相对父提交只能修改 `Support/Info.plist` 的 `CFBundleShortVersionString`。这些检查在任何签名、公证凭据进入 job 前完成。
候选 PR 在体验期间保持打开；beta 失败只修复候选流程或创建下一候选，不得创建正式标签。

共享发布流程和 Fastlane lanes 来自 `oh-my-infra/apple-ci`；workflow 固定完整
commit SHA，Fastfile 固定对应的 `v2026.09.12.1` 签名标签。应用发布结果位于
`oh-my-brew/miniTools`。

`Release` workflow 只保留 `publish=false` 的签名、公证诊断能力，不负责正式发布。

Release workflow 使用以下 GitHub Actions Secrets：

- `APPLE_ASC_KEY_ID`
- `APPLE_ASC_ISSUER_ID`
- `APPLE_ASC_PRIVATE_KEY_BASE64`
- `APPLE_MATCH_PASSWORD`
- `APPLE_MATCH_GIT_PRIVATE_KEY`
- `SPARKLE_ED_PRIVATE_KEY`

CI 通过只读 Fastlane Match 恢复 Developer ID 身份，不再保存项目级 P12。

候选 Release 包含：

- `miniTools-YYYY.MM.DD.N.zip`
- `miniTools-YYYY.MM.DD.N.zip.sha256`
- `appcast-beta.xml`

## 提升正式版本

用户明确批准某个 beta 后，后台 Promote subagent：

1. 锁定候选标签及用户批准时记录的 ZIP SHA-256，让原候选 commit 进入远端默认分支（保留该 commit，不使用会改写 commit 的 squash）。
2. 在原候选 commit 上创建并推送签名 annotated 标签 `vYYYY.MM.DD.N`；不得让标签指向重新构建的其他 commit。
3. 派发 `Promote Beta Candidate` workflow，输入候选标签和预期 SHA-256。
4. Workflow 明确抓取远端默认分支，验证它包含候选 commit、候选仍为 prerelease、正式标签签名有效且指向候选 commit，并重新检查 ZIP 摘要、Developer ID 签名、公证 ticket、Gatekeeper 和 arm64 架构。
5. 从候选 Release 下载原 ZIP，以稳定 Release URL 重新生成签名 `appcast.xml`，将同一 ZIP、同一校验文件和稳定 appcast 一次发布为正式 Release。

签名标签推送后，从默认分支派发提升流程：

```bash
gh workflow run promote.yml \
  --ref master \
  -f "candidate_tag=vYYYY.MM.DD.N-beta.RUN_NUMBER" \
  -f "expected_sha256=<用户批准候选的 64 位 SHA-256>"
```

`expected_sha256` 必须在用户批准时从候选校验文件记录，不能在提升时静默改用远端的新值。

标签必须使用 `vYYYY.MM.DD.N`，并与 Info.plist 中的可见版本完全一致；`N` 从
`1` 开始，同一天再次发布时依次递增。GitHub Release、应用内显示版本、发布文件和 Homebrew
Cask 均使用完整四段版本。标签必须是签名的 annotated tag；用户批准和正式提升允许跨天，
不要求 tagger 日期等于版本日期。正式提升不得重新构建或重新公证；
`CFBundleVersion` 保留 beta 构建时的 `YYYYMMDD.N.RUN_NUMBER`。这个值跨旧的稳定 Release
workflow 和新的 beta workflow 单调递增，避免两个 workflow 各自从 `1` 开始计数后，
Sparkle 把新 beta 误判为旧构建。

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
