# 字体与终端外观

默认 `round_tabs = false` 是兼容模式，使用 Unicode 边框和标准 Nerd Font 符号。请在终端选择 **Nerd Font Mono**，例如 JetBrainsMono Nerd Font Mono；纯文字等宽字体可能缺少文件图标。

完整专用模式使用本目录的 **ForgeMono Geometry 6 NF**，是改名的 JetBrains Mono NL Nerd Font Mono 衍生字体，增加了标签连接、窗格外沿、焦点描边和底栏胶囊字形。四个 TTF 对应 Regular、Bold、Italic、Bold Italic，需要一起安装。原字体的文字与图标保留，新增字形依赖 Macchiato 的固定颜色。

## Windows Terminal + WSL

1. 在 **Windows** 上安装四个 `ForgeMonoGeometry6NF-*.ttf`，不是只复制到 WSL 字体目录。
2. 在实际使用的 Windows Terminal profile 中选择 `ForgeMono Geometry 6 NF`，配色选择你自己的 **Catppuccin Macchiato**。
3. 将该 profile 的字体行高设为 `1.42`，建议从 12 点字号开始。关闭终端内边距可让背景贴合窗口：`padding = "0"`。
4. 在配置目录的 `local.lua` 中设置 `round_tabs = true`、`line_height = 1.42`，并填写实际 profile 名称。
5. 保存编辑内容，完整关闭并重新打开 Windows Terminal，以更新字体缓存。

在 **Windows Terminal 的 JSON 设置**中，以下片段只展示需要合并到现有 profile 的字段；不要替换整个设置文件：

```json
{
  "name": "Fedora",
  "colorScheme": "Catppuccin Macchiato",
  "padding": "0",
  "font": {
    "face": "ForgeMono Geometry 6 NF",
    "size": 12,
    "cellHeight": "1.42",
    "builtinGlyphs": true,
    "colorGlyphs": true
  }
}
```

这里的 scheme 名称必须已存在于你的 Terminal 设置中，可从 [Catppuccin Windows Terminal](https://github.com/catppuccin/windows-terminal) 获取。Neovim 配置启动时只设置编辑器配色，不修改终端主题或 profile；修改终端行高只在主动调用命令时执行。

## 行高

Geometry 6 的字形银行支持 **1.42–1.65，步长 0.01**。实际终端行高和 Neovim 选择的银行必须一致，否则边框、标签连接或胶囊会错位。所有内容都在同一个终端网格中，因此文件树、正文、标签共用字符行高；Neovim 不能分别设置三者的像素高度。

```vim
:UiLineHeight       " 查询当前终端/几何高度
:UiLineHeight 1.48  " 调整到 1.48
```

WSL + Windows Terminal 中，这个命令通过 `scripts/terminal-ui.py` 修改指定 profile 的 **font.cellHeight**，保留 JSONC 注释和其他字段；写入前将终端设置备份到 `stdpath("state")/terminal-ui-backups`，几何高度保存到 `stdpath("state")/workbench-ui.json`。

profile 名称重名时，请在 `local.lua` 中填写 `terminal_ui.guid`；也可以显式指定脚本可读取的 `terminal_ui.settings` 路径。不要复制其他机器的 GUID。`terminal_ui.enabled = false` 可以禁用终端设置联动。

其他终端下，该命令只同步 Neovim 的几何高度并提示手动调整实际行高；普通字体模式仍可使用命令，但完整边框像素对齐主要在 Windows Terminal 验证。

`local.lua` 的 `line_height` 是**首次使用的默认值**。已有 `workbench-ui.json` 缓存时，缓存优先，以保留上次 `:UiLineHeight` 的选择。主动执行命令可以更新缓存；需要重置时，在关闭 Neovim 后移走该缓存文件，再设置新的默认值。

## Linux/macOS/原生 Windows 的其他终端

将 TTF 安装到所在系统的字体管理器，然后在终端选择该字体。Linux 可放到 `~/.local/share/fonts` 并运行 `fc-cache -f`；macOS 使用字体册；原生 Windows 使用字体安装功能。字体安装与终端 profile 设置由你主动完成。

专用字形使用 COLR 彩色层和组合字符，依赖终端的彩色字体与字符宽度实现。目前完整像素效果实测于 Windows Terminal；如果某终端缺字、出现接缝或颜色不一致，先设置 `round_tabs = false` 使用兼容模式。切换模式需要重启 Neovim。

## 修改颜色或字形

Geometry 6 字体中的几何颜色固定为 Macchiato：crust `#181926`、base `#24273a`、mantle `#1e2030`、普通边框 `#494d64`、焦点边框 `#8aadf4`。修改 Lua 高亮并不会改掉字体彩色层；大幅换主题时建议使用兼容模式。

本仓库包含可直接安装的最终字体，不包含历史字体构建流水线。`shape_bank.lua`、`pane_bank.lua`、`edge_bank.lua` 是与这些字体匹配的映射，日常修改宽度、按键、文字和标签间距无需编辑它们。新增几何字形或替换映射需要另行构建对应字体，不能单独改码点。

字体修改与第三方图标授权见 [THIRD_PARTY.md](../THIRD_PARTY.md)、[OFL.txt](OFL.txt) 和 [licenses/](licenses/)。
