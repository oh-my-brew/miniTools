# 发行与 Homebrew Cask

## 发布流程

推送格式为 `vYYYY.MM.DD.N` 的标签后，`.github/workflows/release.yml` 会自动：

1. 校验标签日期与 `Support/Info.plist` 一致并运行测试。
2. 构建 arm64 主程序及合盖运行 helper（仅支持 Apple Silicon，不构建 x86_64）。
3. 使用 Developer ID Application、Hardened Runtime 和安全时间戳先签署 helper，再签署应用。
4. 上传 Apple 公证服务，等待通过并将 ticket staple 到应用。
5. 校验签名、Gatekeeper 和公证 ticket，再生成最终 ZIP、SHA-256 和 GitHub Release。

共享发布流程和 Fastlane lanes 来自 `oh-my-infra/apple-ci`；workflow 固定完整
commit SHA，Fastfile 固定对应的 `v2026.09.12.1` 签名标签。应用发布结果位于
`oh-my-brew/miniTools`。

手动运行 Release workflow 时 `publish=false`，仍会构建、签名并提交 Apple
公证，但不会创建或更新 GitHub Release。迁移验证不需要修改产品版本或创建产品标签。

Release workflow 使用以下 GitHub Actions Secrets：

- `APPLE_ASC_KEY_ID`
- `APPLE_ASC_ISSUER_ID`
- `APPLE_ASC_PRIVATE_KEY_BASE64`
- `APPLE_MATCH_PASSWORD`
- `APPLE_MATCH_GIT_PRIVATE_KEY`

CI 通过只读 Fastlane Match 恢复 Developer ID 身份，不再保存项目级 P12。

Release 包含：

- `miniTools-YYYY.MM.DD.N.zip`
- `miniTools-YYYY.MM.DD.N.zip.sha256`

## 发布版本

先把 `Support/Info.plist` 中的 `CFBundleShortVersionString` 更新为发布日期，提交并确认
CI 通过，再创建包含当日发布序号的标签：

```bash
git tag -s v2026.08.29.1 -m "miniTools 2026.08.29.1"
git push origin v2026.08.29.1
```

标签必须使用 `vYYYY.MM.DD.N`：日期部分与 Info.plist 中的三段可见版本一致，`N` 从
`1` 开始，同一天再次发布时依次改为 `2`、`3`。GitHub Release、发布文件和 Homebrew
Cask 使用完整四段版本；应用内显示三段日期版本。标签必须是签名的 annotated tag，
其上海时区 tagger 日期也必须与版本日期一致。`CFBundleVersion` 在 GitHub Actions 中
使用当次 `GITHUB_RUN_NUMBER`，无需每次手动修改。

## Homebrew Tap

`oh-my-brew/homebrew-tap` 中的 `minitools` Cask 固定下载对应版本的 GitHub Release。
Tap 的定时 Autobump 工作流发现新版本后，会自动创建更新 Cask 版本和 SHA-256 的 PR。

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
