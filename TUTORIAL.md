# MacStatusBar：第一次使用

## 1. 先判断你的电脑能不能用

本工具仅用于 macOS 13+，不支持 Windows、iOS/iPadOS 或微信小程序。点屏幕左上角苹果菜单 →“关于本机”，查看系统版本和芯片。写着 Apple M 系列的是 Apple Silicon（ARM64）；写着 Intel 的电脑不能使用本次 ARM64 应用 ZIP，可尝试自行从源码编译，但尚未经过 Intel 实机验收。

本次只在当前 ARM64 Mac 上实测。最低版本声明不代表每个 macOS 13 及以上版本均已测试。全屏、多屏、无刘海屏和各种缩放比例没有全面验收。

## 2. 选择一种拿到文件的方式

能访问 GitHub：在项目页面下载源码 ZIP，或使用发布页提供的 ZIP。下载页面上的源码归档与项目打包的源码 ZIP 目录名可能不同，以解压后找到 `build.sh` 和 `MacStatus.swift` 为准。

不能访问 GitHub：请分享者把 `MacStatusBar-v0.1.0-source.zip`、`离线使用教程.html` 发给你；需要预编译应用时，再附上 `MacStatusBar-v0.1.0-macos-arm64.zip`。这些文件可以直接通过微信等文件传输工具分享。收到后保存到 Mac 本地再解压；它们不是微信小程序。本项目不声明任何未经验证的镜像站。

“离线分享包”表示无需 GitHub 即可获取文件和阅读教程，不等于从零安装的全过程都能断网。如果 Mac 尚未安装 Xcode 命令行工具，首次下载安装仍需联网。已装好工具后，本项目的编译、自测和运行不需要网络请求。

只接收可信来源的文件。分享者可同时发送发布清单中的 SHA-256，接收者在终端执行 `shasum -a 256` 后输入一个空格，把 ZIP 拖进窗口，再按回车，比对显示的哈希；哈希一致仅证明字节一致，不证明作者身份或软件绝对安全。

## 3. 从源码编译（推荐能使用终端的读者）

需要 Xcode Command Line Tools，包含 Apple 的 Swift 编译器。在“终端”中检查：

```sh
xcode-select -p
xcrun swiftc --version
```

若提示未安装，可运行 Apple 提供的安装入口，再按系统窗口完成安装；这一步由你自行确认：

```sh
xcode-select --install
```

解压源码 ZIP，打开里面的 `MacStatusBar` 文件夹。终端输入 `cd` 和一个空格，把这个文件夹拖进终端，再按回车。确认当前目录含 `build.sh` 后执行：

```sh
zsh build.sh
```

成功时会看到 `PASS: 19 quota, display, disk and memory checks` 和 `Built locally only:`。应用在当前文件夹的 `build/Mac Status.app`。脚本只生成本目录内的 build，不安装到 Applications，不加登录项，不自动启动。

先做不打开界面的检查：

```sh
"build/Mac Status.app/Contents/MacOS/MacStatus" --self-test
"build/Mac Status.app/Contents/MacOS/MacStatus" --snapshot
```

`--snapshot` 输出当前本机指标，只供自己检查，不要未经检查公开。检查正常后启动：

```sh
open "build/Mac Status.app"
```

## 4. 使用预编译 ARM64 应用（可选）

解压 `MacStatusBar-v0.1.0-macos-arm64.zip`，里面的 `Mac Status.app` 仅适用于 Apple Silicon Mac。本包没有 Developer ID 签名或 Apple 公证，系统可能拦截；链接器产生的 ad-hoc 临时签名不是开发者身份认证。请遵守系统或组织安全政策；遇到拦截可以停止使用、核对来源，或在可信源码基础上自行构建。这里不提供移除隔离标记、关闭 Gatekeeper 或其他绕过步骤。

从源码构建也不保证解决所有系统安全拦截。遇到拦截应停止，记录已脱敏的提示，向发包者或项目 Issues 求助，不要反复尝试安全绕过命令。

本教程不要求全局安装。不要替换你已有的同类应用或登录项。源码构建与预编译包二选一运行即可。

## 5. 顶部三个数怎么看

浮条默认在摄像头左侧；没有对应安全区时按顶部位置计算。绿色代码图标：可选本地剩余额度；紫色硬盘：主目录所在卷的可用 GB；蓝色芯片：内存使用率。橙色警告表示某一阈值触发，不等于电脑已经出故障。

每 15 秒刷新，点击浮条立即刷新并打开详情。按住 Command（⌘）拖动可移动；菜单中“恢复到摄像头左侧”可回到默认位置。拖动位置不会跨重启保存。长菜单可能与浮条重叠。

详情中的内存使用量以 GiB 表示，算法不完全等同于活动监视器。判断是否吃紧，应结合内存压力和实际体验；缓存多不等于卡顿。磁盘空间不包含额外估算的“可清理空间”。

## 6. 额度显示“—”很正常

额度是可选项。没有输入文件时，磁盘和内存照常工作；它不会登录你的 AI 账号，也不会自动拉取官方额度。

只读默认路径为 `~/Library/Application Support/MacStatusBar/quota.json`。该文件需由你自己的合法数据来源提供；本工具不负责生成或更新。`quota.example.json` 仅说明格式，固定演示时间会过期，不能当成真实数据。

如需测试其他路径，在源码目录直接启动进程（先退出已运行实例）：

```sh
MACSTATUS_QUOTA_PATH="$PWD/quota.example.json" "build/Mac Status.app/Contents/MacOS/MacStatus" --snapshot
```

这个示例只验证路径读取，过期演示值应显示无效。不要把演示时间改成当前时间后当成真实额度。环境变量仅影响该进程，不会自动传给 Finder 启动的应用。数据超过 180 秒、未来超过 60 秒、重置时间已过或格式错误时不显示有效百分比。

数据结构字段及边界见 README。JSON 不需要密码、token 或账号标识，请勿提供这些内容。它不是官方额度 API，也不能强制停止任务、阻止扣费或替代官方账单。

## 7. 退出与清理

点击浮条 →“退出 Mac 状态”。程序没有登录启动或自动重启设置。退出后可以自行管理下载和 build 文件；不要误删自己原有的数据或其他程序。它不会替你清理磁盘、关闭程序或改动系统设置。

## 8. 向别人分享

最少分享源码 ZIP 与本 HTML 教程；需要时再附 ARM64 应用 ZIP。保留 LICENSE 和源文件，不要夹带你自己的 `quota.json`、快照、账号信息、截图、构建日志或私人路径。MIT 允许复制和修改，但不提供适用性或安全保证。

遇到问题可附系统版本、芯片类型、操作步骤和已脱敏的报错；不要发送凭据或完整个人目录。更多问题见 FAQ.md，交给 AI 的提示见 WHAT_TO_GIVE_YOUR_AI.md。
