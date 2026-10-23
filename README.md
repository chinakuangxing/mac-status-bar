# MacStatusBar 0.1.0 · 仅适用于 Mac
 
macOS 原生 206 × 23 点顶部浮条：磁盘可用空间、内存使用率，以及可选的本地额度数据。默认靠近摄像头左侧；没有摄像头安全区的屏幕按屏幕顶部定位。绿色、紫色、蓝色图标分别对应额度、磁盘、内存；警告项为橙色。每 15 秒读取，点击立即刷新，按住 Command 拖动调整位置。

这是一个轻量、开源的 Mac 桌面工具，按 MIT 许可证提供，作者为旷星。不是 Apple、OpenAI 或其他厂商的官方产品。它不是 Windows 软件、iPhone/iPad App，也不是微信小程序；微信只能用来转发安装包和教程，不能在微信里运行它。

最低系统要求为 macOS 13+。本发布包只在当前 Apple Silicon（ARM64）Mac 上完成编译、自测及命令行指标检查；未做 Intel 实机验收，也未覆盖全部 macOS 版本和屏幕布局。没有 Developer ID 签名或 Apple 公证，不承诺双击即可运行。

## 不熟悉代码，从这里开始

先看 [TUTORIAL.md](TUTORIAL.md)。不方便访问 GitHub，可以请分享者直接发送源码 ZIP 和 `离线使用教程.html`；教程不依赖网络。“离线分享”指无需 GitHub 即可获取文件和阅读教程，不代表从零安装全程断网：若缺少 Xcode 命令行工具，首次下载安装仍需联网。已验证的 ARM64 应用 ZIP 只适用于 Apple Silicon Mac。源码构建不能保证解决所有安全拦截；遇到拦截时请停止，向发包者或项目 Issues 求助，并按组织和 macOS 官方安全指引处理，不要关闭系统保护。

想让 AI 帮你操作，复制 [WHAT_TO_GIVE_YOUR_AI.md](WHAT_TO_GIVE_YOUR_AI.md) 的提示，并附上源码 ZIP。常见问题见 [FAQ.md](FAQ.md)。

## 编译与运行

需要 macOS 13 或更高版本，以及包含 Swift 编译器的 Xcode Command Line Tools。只使用系统 AppKit、Darwin 和 Foundation；无第三方运行时依赖。编译生成当前机器架构版本，不是通用二进制；其他芯片架构尚未验证。

在解压后的本目录执行：

```sh
zsh build.sh
open "build/Mac Status.app"
```

构建只在本目录生成 build，不复制到 Applications，不安装 LaunchAgent，不添加登录项，不自动启动图形界面，也不执行清理。系统可能为本地编译产物附加临时链接签名，但本包没有开发者身份签名、Developer ID 或 Apple 公证。请按组织和系统安全策略处理运行许可；这里不提供绕过 Gatekeeper 的步骤。

点击浮条，选择“退出 Mac 状态”即可退出。程序不注册自动重启。活动监视器入口仅打开系统工具；本程序不会自动结束其他程序。删除前先退出；源码与 build 可由使用者自行管理。

## 指标含义

- 磁盘：用户主目录所在卷的可用空间，十进制 GB；不额外计算可清理空间。主目录不一定在内置磁盘。
- 内存：匿名内存减可清除页，加 wired 和物理压缩占用，详情用 GiB；不是所有 Activity Monitor 指标的精确复刻。
- 警告：磁盘不足 20 GB、内存压力偏高或严重、本地额度已用至少 90%，或输入中带停机标记。它是观察提示，不是故障诊断。

## 可选本地额度 JSON

默认只读 `~/Library/Application Support/MacStatusBar/quota.json`，文件不存在时显示“—”，磁盘和内存仍工作。也可为直接启动的进程显式传入绝对路径：

```sh
MACSTATUS_QUOTA_PATH="/absolute/path/quota.json" "build/Mac Status.app/Contents/MacOS/MacStatus"
```

环境变量不会因上述设置而自动传递给 Finder 启动的进程。程序不创建或更新输入文件；需由使用者合法取得并提供。示例见 quota.example.json，所有数值均为固定演示值，时间会过期，不能代表真实账号。

`last_rate` 包含 `used_percent`（0–100）、`observed_at`（ISO 8601）、`resets_at`（Unix 秒）、`window_minutes`（正整数）及 `source: "local-json"`。可选 `quota_stop_latch` 非空对象只影响警告，不控制任何任务。超过 180 秒、未来超过 60 秒、重置时间已过、缺失或损坏的数据不显示有效百分比。

这不是通用官方额度 API。程序既不登录账号、不模拟官方客户端、不读取 token，也不验证输入的数据真实性或选择多窗口额度。不要把凭据、账号标识或真实状态提交到源码仓库。若数据用于额度决策，应独立核对官方界面；本工具不能强制停止计费或形成账单保护。

## 兼容与验收边界

浮条会覆盖顶部区域，长菜单可能重叠；全屏、自动隐藏菜单栏、外接屏、多显示器、无刘海屏和各类缩放比例未全面验收。位置重启后恢复默认，不保存拖动位置。储存空间设置 URL 可能随系统版本变化。

本发布包执行编译、19 项自测、命令行指标检查、ZIP 内容逐字节比对及白名单文件隐私模式扫描。没有对新包执行全机 UI、跨重启、Intel 实机、所有 macOS 版本、性能或辅助功能验收。旧版本的 UI 证据不自动适用于本发布包。安全说明见 SECURITY.md，源码与许可范围见 PROVENANCE.md，变更见 CHANGELOG.md。

