# FinderHotKey

一个常驻后台的 macOS 小工具，提供三个全局快捷键：

| 功能 | 默认快捷键 |
| --- | --- |
| 打开访达（每次新建窗口，可自定义位置） | ⌘E |
| 最小化当前窗口（连续按可依次最小化） | ⌘esc |
| 显示桌面 / 恢复窗口 | ⌘D |

在“应用程序”中打开 FinderHotKey 会显示设置窗口，分为“快捷键”“触发提示”“菜单栏”三组。修改先暂存，点击“保存”才生效；直接关闭窗口会放弃修改。关闭设置窗口后应用继续在后台运行，没有 Dock 图标。快捷键触发时，屏幕中央会短暂显示该快捷键（深灰圆角卡片、白色大字），可在设置中开关、调整停留/淡出时间与颜色。

## 工程结构

```
FinderHotKey/
├── Package.swift                     Swift Package 定义
├── Info.plist                        App 元数据（LSUIElement 等）
├── Sources/FinderHotKey/main.swift   全部源码
├── Resources/AppIcon.icns            应用图标
├── Scripts/build-app.sh              构建通用二进制 App
├── Scripts/build-pkg.sh              生成安装包
├── Packaging/scripts/postinstall     安装包脚本
└── dist/                             构建产物
```

## 构建

```bash
./Scripts/build-app.sh   # 通用二进制，ad-hoc 签名 → dist/FinderHotKey.app
./Scripts/build-pkg.sh   # → dist/FinderHotKey-<版本>.pkg
```

需要 Xcode 命令行工具。安装包的 postinstall 会为当前登录用户写入 LaunchAgent，并在升级时清理旧的辅助功能授权（ad-hoc 签名与二进制指纹绑定）。

## 安装与权限

- 安装包固定安装到 `/Applications/FinderHotKey.app` 并设置开机启动；也可手动把 App 拖入 `/Applications` 后自行创建 `~/Library/LaunchAgents/local.tgs.finderhotkey.plist`。
- 首次运行需在「系统设置 › 隐私与安全性 › 辅助功能」勾选 FinderHotKey；没有该权限时“打开访达”仍可用，“最小化窗口”和“显示桌面”不工作。
- “打开访达”还需要“自动化 › 访达”权限；拒绝时会退化为打开或激活已有窗口。
- 应用为 ad-hoc 签名、未公证。在别的 Mac 上被 Gatekeeper 拦截时，右键 App 选择“打开”，或到「隐私与安全性」点“仍要打开”。
- 重新构建后签名指纹会变化，辅助功能和自动化权限需要重新勾选。

## 快捷键定制

- 每行包含功能、快捷键和“启用”勾选框；取消勾选并保存后停用该功能。
- 点击快捷键框后按下新组合键即可重新绑定：组合键需含 ⌘、⌥、⌃ 之一，F1–F20 可单独使用；Esc 取消，重复时提示冲突。
- 「打开位置」自定义“打开访达”的文件夹（默认主目录）；文件夹被移动或删除时自动回到主目录。
- 「触发提示」可开关，并调整停留/淡出时间（0–5000 毫秒，默认 600/200）及背景、文字颜色。
- 「恢复默认」重置快捷键和提示设置，仍需点击“保存”生效。
- 「在菜单栏显示图标」控制菜单栏图标；关闭后应用仍在后台运行，再次打开 App 可显示设置窗口。

设置保存在 `~/Library/Preferences/local.tgs.finderhotkey.plist`。菜单栏图标左键打开设置，右键提供设置、打开访达、退出。

## 说明

- “显示桌面”调用系统自带的“显示桌面”快捷键（默认 fn+F11），会读取当前绑定，因此兼容台前调度。
- “打开访达”通过自动化新建窗口，窗口位置完全交给访达，与系统默认一致。
- 不联网、不录屏、不监听键盘，不写日志；LaunchAgent 的输出指向 `/dev/null`。
