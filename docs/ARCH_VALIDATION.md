# Arch 实际回归与修复（2026-10-07）

本轮在 Arch、Neovim 0.12.5、Ghostty 1.3.1-arch2、GNOME Console / VTE 0.84.1、systemd 262 验证。保留主题、按键、导航、HDL 隔离与 20 个锁定插件；插件锁文件与原 main 逐字节相同。此记录描述实际检查范围，不是所有终端零 bug 的保证。

## 修复依据

- Console 相邻标签缺线：COLR 基底只包含下部末层，绘制边界缺少上沿与竖线。Console 衍生字体以原全部彩色图层组合基底，实际终端缺口消失。四字重各变更 144 个接缝基底；普通轮廓、所有字宽、色板、COLR 图层和字符映射不变。
- NORMAL 中 Esc 没有命令弹窗：NORMAL 已是普通模式，输入 Ex 命令用 `:`。未复现 Neovim 输入卡死；保留原 Esc 映射。
- Ghostty 概览启动失败：journal 报 USR2 handler 缺失，systemd 262 拒绝 notify-reload 启动。可选 Type=notify 用户覆盖保留 READY 和 D-Bus，应用内重载可用，systemctl reload 暂不可用。只在出现相同故障时安装，升级修复后应移走并重测。说明及回退见 [ARCH.md](ARCH.md)。

## 通过的检查

| 项目 | 范围 |
| --- | --- |
| 本机真实终端 | Ghostty 8 组 / Console 4 组；标签鼠标、侧栏双向拖动、保存后树/编辑焦点、模式切换、浮窗和极窄窗口恢复 |
| 模式与鼠标 | 各 12 轮，通过 Neovim 输入 API；点击标签不会进入装饰窗口，延迟刷新不抢树焦点 |
| GTK 实际控制键 | 两终端各 6 轮 i / Esc / 冒号 / Esc，XTest 经 GTK 与终端输入，确认命令弹窗出现 |
| Ghostty 桌面激活链路 | 10 次独立服务启动，另 10 次完整 D-Bus 冷启动；每次一个 Activate 即创建窗口，不先启动服务 |
| Headless | smoke 15、minimap 10、tab_corner 8、真实语法渲染 11、平台分支 41、自动适配分支 7 项 |
| 像素 | 缩略图与几何 16 项、Kitty 代码条带/独立选区 2 项；覆盖全部 1176 个装饰字形 |
| 字体 | 四字重接缝基底比较通过；COLR / CPAL / cmap、字宽和普通字形保持原样 |
| 格式与依赖 | 修改 Lua 格式检查及 Python 编译检查通过；插件锁文件未变 |

Ghostty Wayland 实测字符格 23×54；30 次选区更新仍只请求一次代码图像。像素尺寸随 DPI/终端字号改变，不应写死为 Windows 的 10×20 虚拟格。

[Console 中间活动标签截图](../assets/arch-console-tabs.png) 来自 Xvfb 中的实际终端窗口和临时 HDL 文件，没有合成网格；首次截图存在隔离 GTK 绘制残留，完整刷新窗口后逐张核对。GTK 按键测试最初继承桌面 Fcitx，空配置也收不到按键；测试进程隔离到简单输入法后通过。未改桌面输入法，未验证中文组合输入。

可机器读取的范围摘要见 [arch-2026-10-07.json](validation/arch-2026-10-07.json)。检查用例随配置公开；原始本机日志、个人设置、缓存、项目与会话不发布。

## 能力边界

GNOME Console 本机没有 Kitty / Sixel，不能显示真实小字体缩略图；Ghostty 提供完整缩略图。平台分支测试不等于 Windows/macOS 此轮现场验收。没有对用户 HDL 项目进行综合、仿真或完整 LSP 验收。实验性的 Neovim 图像装饰接口和终端实现升级后需重跑检查。
