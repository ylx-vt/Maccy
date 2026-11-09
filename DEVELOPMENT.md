# 个人版本开发说明

本仓库基于 [Maccy 官方稳定版 2.8.0](https://github.com/p0deje/Maccy/releases/tag/2.8.0) 开发。
上游基线提交为 `7c1644bfbed1dd0d703ecdbaf4a1b9a3a1d0b295`，保留原项目 MIT 许可证。

## 仓库与分支

- `origin`：个人仓库 `https://github.com/ylx-vt/Maccy.git`。
- `upstream`：官方仓库 `https://github.com/p0deje/Maccy.git`。
- 当前功能分支：`codex/compact-image-preview`。
- 现有远端分支保留；功能分支验收后再合并到个人主线，不强推覆盖旧历史。
- 后续迭代从个人仓库最新已验证的开发提交创建分支；同步官方版本时明确记录上游 tag、合并范围和验证结果。

```sh
git fetch origin
git fetch upstream --tags
git switch codex/compact-image-preview
git pull --ff-only
```

## 当前改动

图片在并排侧栏内适配显示，显示区域最多 400×480 点；图片尺寸不再决定窗口尺寸。
支持触控板双指捏合缩放和双指滚动查看局部，使用原始图像查看细节。
双击图片或点击“适配”恢复全图；切换图片重置缩放，同一图片的普通界面刷新保留缩放。

布局与图像视图位于 `Maccy/Views/PreviewItemView.swift` 和 `ZoomableImagePreview.swift`；
窗口约束位于 `Maccy/Observables/SlideoutController.swift`；定向测试位于 `MaccyTests/PreviewTests.swift`。

## 验证与演示

```sh
xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Debug \
  -derivedDataPath /tmp/maccy-preview-qa -destination 'platform=macOS' \
  -only-testing:MaccyTests/PreviewTests CODE_SIGNING_ALLOWED=NO test
python3 qa/prepare-preview-demo.py /tmp/maccy-preview-qa/Build/Products/Debug/Maccy.app
```

独立演示、验收边界和截图说明见 [qa/README.md](qa/README.md)。
构建产物、截图、日志及补丁仅保留在被 Git 忽略的 `qa/artifacts/`，不上传个人剪贴板数据。

正式替换日常使用的应用前，需完成真实触控板与实际使用路径验收，并为原应用和历史数据保留可恢复备份。

## 本地日常版本

个人日常版本使用 `LOCAL_FORK` 编译条件，由个人仓库维护更新，关闭官方 Sparkle 更新入口。
本地临时签名没有开发者 Team ID；移除未使用的更新库链接，可保留沙盒、强化运行时和库验证。

```sh
xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Release \
  -derivedDataPath /tmp/maccy-release -destination 'platform=macOS' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=LOCAL_FORK \
  OTHER_LDFLAGS=-Wl,-dead_strip_dylibs CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
```

安装前核验 `otool -L` 不含 Sparkle，沙盒开启且不带 `get-task-allow` 调试权限。
原应用、历史和偏好备份保留在本机私有目录，不提交到 Git。自启使用应用内“登录时启动”。
