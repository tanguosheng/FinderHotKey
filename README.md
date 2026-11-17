# FinderHotKey

一个常驻菜单栏的 macOS 小工具，提供三个全局快捷键：

| 功能 | 默认快捷键 |
| --- | --- |
| 打开访达（主目录） | ⌘E |
| 最小化当前窗口（连续按可依次最小化） | ⌘esc |
| 显示桌面 / 恢复窗口 | ⌘D |

周点击菜单栏的 ⌘ 图标可以打开设置窗口：勾选或取消勾选来启用/停用功能，点击快捷键后直接按下新的组合键即可重新绑定。修改立即生效并自动保存。

## 工程结构

```
FinderHotKey/
├── Package.swift                     Swift Package 定义（可用 Xcode 打开）
├── Info.plist                        App 元数据（LSUIElement 等）
├── Sources/FinderHotKey/main.swift   全部源码
├── Resources/AppIcon.icns            应用图标
├── Scripts/build-app.sh              通用二进制构建脚本
├── dist/                             构建产物
└── README.md
```

## 构建

```bash
cd ~/Desktop/FinderHotKey
./Scripts/build-app.sh
```

脚本会分别编译 Intel（x86_64）和 Apple Silicon（arm64），用 `lipo` 合并，组装 `dist/FinderHotKey.app` 并做 ad-hoc 签名。要求已安装 Xcode 命令行工具。

生成安装包：

```bash
./Scripts/build-pkg.sh
```

输出 `dist/FinderHotKey-<版本>.pkg`。安装包的 postinstall 会写入当前用户的 LaunchAgent，并在升级时清理旧的辅助功能授权（因为 ad-hoc 签名的授权绑定到二进制指纹）。

也可以直接用 Swift Package 构建本机架构：

```bash
swift build -c release
```

## 运行

```bash
open dist/FinderHotKey.app
```

首次运行需要在「系统设置 › 隐私与安全性 › 辅助功能」中勾选 FinderHotKey。没有辅助功能权限时，打开访达仍可用，但最小化窗口和显示桌面不会工作。

## 安装与开机启动

- 将 `FinderHotKey.app` 拖入 `/Applications`。
- 新建 `~/Library/LaunchAgents/local.tgs.finderhotkey.plist` 指向该路径，或使用安装包自动配置。
- 应用自身不写任何日志；LaunchAgent 的 stdout/stderr 指向 `/dev/null`。

## 快捷键定制

设置窗口中的每一行包含：

- **启用**：取消勾选后该功能的全局快捷键会被注销。
- **快捷键**：点击后变为“按下快捷键…”，此时所有全局快捷键会临时注销，按下新的组合键即保存；按 Esc 取消。
- 组合键必须包含 ⌘、⌥ 或 ⌃ 中的至少一个。与其他功能重复时会提示冲突。
- 「恢复默认」恢复为 ⌘E / ⌘esc / ⌘D 并重新启用全部功能。

设置保存在 `~/Library/Preferences/local.tgs.finderhotkey.plist`。

## 菜单栏

- 左键点击 ⌘ 图标：打开设置。
- 右键点击：设置、打开访达、退出。
- 应用再次被打开（例如双击 App）时会弹出设置窗口。

## 说明

- 显示桌面使用系统自带的“显示桌面”快捷键（默认 fn+F11），会读取系统当前绑定，因此不会破坏台前调度。
- 本应用为 ad-hoc 签名，未经过公证。拷到其他 Mac 上若被 Gatekeeper 拦截，请在 Finder 中右键 App 选择“打开”，或在“系统设置 › 隐私与安全性”中点“仍要打开”。
- 重新构建后签名指纹会变化，辅助功能权限需要重新勾选。