# Arch 终端适配（2026-10-07）

本机适配经过 Neovim 0.12.5、Ghostty 1.3.1-arch2、GNOME Console / VTE 0.84.1 验证。保留 Macchiato、原有圆角设计、按键、文件树、导航和 20 个锁定插件。插件提交与 `nvim-pack-lock.json` 未变更。

## 两种终端

| 终端 | 字体 | 界面几何 | 缩略图 |
| --- | --- | --- | --- |
| Ghostty | ForgeMono Workbench Text NF | Kitty 透明图像绘制原字体轮廓，终端负责普通文字 | Kitty 图像；真实小字体、语法颜色、视口和三类选区阴影 |
| GNOME Console | ForgeMono Workbench Console NF | 原字体 COLR 彩色字形，字体行高为 1.42 em | 本机未提供 Kitty / Sixel；请求打开时提示并关闭空面板 |

Ghostty 对原字体 COLR 的渲染会报 `WrongAtlas`，所以这里保留原文字、图标及字体度量，另用稀疏透明图像绘制专用圆角和胶囊。中文标签保持原生宽字符，由图像层补上描边，避免宽字符与专用组合标记在 Ghostty 中出现替换字形。

Console 没有独立行距选项，因此其衍生字体将原来的 1.32 em 度量改为 1.42 em，并使基线保持居中。这个家族仅用于 1.42 银行；Console 中修改 `:UiLineHeight` 时需要另行构建对应字体。Ghostty 图像几何会根据实测像素格缩放。Console 的 144 个标签接缝字形（每字重）还修正了基底轮廓的包围盒：基底包含全部原 COLR 图层，避免 VTE 裁掉上沿和竖线。原彩色图层、色板、字符映射、字宽与普通字形不变。

## 已应用的本机设置

两个终端共用同一个 `local.lua`。可从 [共享圆角偏好模板](../local.geometry.example.lua) 复制：

```lua
return { round_tabs = true, line_height = 1.42 }
```

`core.settings` 默认 `geometry_images="auto"`，在 Linux Ghostty 中自动选择图像装饰，其余环境使用原字体装饰。无需按终端切换配置文件。WSL / Windows Terminal 联动会检查实际运行环境，Arch 不会触发 Windows 设置写入；原有 WSL 功能保留。可在诊断时用布尔值显式覆盖 `geometry_images`。普通文字、焦点、窗口布局和鼠标操作仍由原配置负责。

Neovim 的偏好可以统一；终端的字体和行距仍需由终端设置，因为 Neovim 无法替终端选择 Fontconfig 字体或增加终端未实现的图像协议。

Ghostty 当前使用以下设置；可将 [终端配置片段](../terminal/ghostty-fonts.conf) 合并到自己的配置：

```ini
theme = Catppuccin Macchiato
font-family = ForgeMono Workbench Text NF
font-size = 13
adjust-cell-height = 8%
```

8% 对应原字体的 1.32 em 到约 1.42 em，实际按终端像素取整。并不是把行距增加 42%。Console 当前为 `ForgeMono Workbench Console NF 14`，保留原 `font-scale=0.9`。

完整关闭并重新打开终端后生效；原有 Neovim 进程也需要重新启动。打开代码文件后按 `<Space>uv` 或运行 `:MinimapToggle`，缩略图默认保持关闭。`:MinimapStatus` 可查看协议、绘制状态和错误。Console 完整图像缩略图需要终端支持相应图像协议；此次没有用方块或盲文替代真实字体。

## 依赖与重装

运行时需要系统 Python 的 Pillow 和 pycairo，以及 Fontconfig。Arch 对应包为 `python-pillow`、`python-cairo`、`fontconfig`。本机已有这些依赖。缩略图保留 Windows Terminal 的 Sixel 后端；Ghostty 使用 Kitty，不再将 Windows 的 10×20 虚拟格套到 Linux。

可安装的四字重字体已包含在 `fonts/arch-text`、`fonts/arch-console`。安装到用户字体目录并刷新缓存：

```sh
mkdir -p ~/.local/share/fonts/ForgeMonoWorkbenchTextNF ~/.local/share/fonts/ForgeMonoWorkbenchConsoleNF
cp ~/.config/nvim/fonts/arch-text/*.ttf ~/.local/share/fonts/ForgeMonoWorkbenchTextNF/
cp ~/.config/nvim/fonts/arch-console/*.ttf ~/.local/share/fonts/ForgeMonoWorkbenchConsoleNF/
fc-cache -f
gsettings set org.gnome.Console custom-font 'ForgeMono Workbench Console NF 14'
```

重新生成字体和 `fonts/geometry-paths.json` 时才需要 fontTools：

```sh
python3 scripts/build-arch-fonts.py
```

构建脚本读取随配置附带的原始四款 TTF；不会自行安装字体或修改终端设置。字体和轮廓的授权继承 [OFL](../fonts/OFL.txt) 与 [第三方署名](../THIRD_PARTY.md)。衍生字体已改名。

## Ghostty 从 GNOME 概览启动

本机 Ghostty 1.3.1-arch2 的 packaged user service 使用 `Type=notify-reload`、`ReloadSignal=SIGUSR2`。实际 journal 显示启动时缺少 USR2 handler，systemd 262 拒绝启动并返回 `protocol`。这是应用启动服务的问题，发生在 Neovim 启动之前。

本机已添加用户级覆盖文件 `~/.config/systemd/user/app-com.mitchellh.ghostty.service.d/10-startup-compat.conf`。仓库提供 [覆盖示例](../terminal/systemd/user/app-com.mitchellh.ghostty.service.d/10-startup-compat.conf)，只在 journal 出现相同 USR2 handler 启动拒绝时安装，不是所有 Ghostty 版本的必需设置：

```ini
[Service]
Type=notify
```

本机已执行 `systemctl --user daemon-reload`，保留 READY 通知和 D-Bus 启动，没有更改系统文件。其他机器安装覆盖后也需执行 daemon-reload。下次冷启动使用此覆盖。该兼容措施使 `systemctl --user reload app-com.mitchellh.ghostty.service` 暂不可用；使用 Ghostty 的 Reload Configuration 动作重载配置。Ghostty 更新解决信号注册问题后，可以移走此文件、daemon-reload 并重测冷启动。无需停止正在使用的终端。

依据：[Ghostty D-Bus / systemd 启动流程](https://ghostty.org/docs/linux/systemd)、[systemd v262 的 reload handler 检查](https://github.com/systemd/systemd/blob/v262/src/core/service.c#L5535)。

## 模式与输入

左下角 `NORMAL` 就是普通模式。`Esc` 退出 INSERT / VISUAL 或取消命令；NORMAL 中的 `Esc` 清除搜索高亮。输入 Ex 命令请按 `:`，显示命令弹窗。嵌入终端中的双击 Esc 使用原有退出终端输入模式映射。

## 验证与后续维护

`tests/arch_ui.lua` 需在真实终端运行，创建临时文件，检查标签、焦点、双向拖动、实际像素尺寸、选区复用、浮窗遮挡及窄窗口恢复。测试还包含 12 轮标签鼠标切换和 INSERT / NORMAL / 命令行往返，检查延迟刷新不抢走树焦点。其他测试见 `tests/tab_corner.lua`、`tests/test_geometry_pixels.py`、`tests/test_minimap_kitty.py`、`tests/terminal_settings.lua`。`tests/gui_keys.py` 在 Xvfb 中经 GTK 和终端发送真实 XTest 按键；测试进程使用简单输入法，避免连接桌面 Fcitx / IBus，不修改桌面输入法设置。

装饰层使用 Neovim 0.12 的实验性 `nvim__inspect_cell` 接口。升级 Neovim 后应重跑终端测试。普通浮窗会裁掉其覆盖的几何，重绘合并并丢弃过时的工作结果；退出和挂起时只删除自身拥有的图像。

此次保存的图形截图来自 Xvfb 中的实际 Ghostty / Console 窗口，验证字体、接缝和文字显示。另在本机 Wayland 的真实终端做了交互回归；Ghostty 实测字符格为 23×54 像素，Xvfb 截图为 10×24，不能混作同一显示环境。

协议参考：[Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)、[Ghostty 行距](https://ghostty.org/docs/config/reference#adjust-cell-height)、[Ghostty Sixel 说明](https://github.com/ghostty-org/ghostty/discussions/2496)。

此次实际测试结果见 [Arch 回归记录](ARCH_VALIDATION.md)，Console 截图见 [assets/arch-console-tabs.png](../assets/arch-console-tabs.png)。
