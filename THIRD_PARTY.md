# 第三方来源与字体修改

Neovim 插件通过 `vim.pack` 从各自上游下载；源地址和锁定提交保存在 [nvim-pack-lock.json](nvim-pack-lock.json)。插件源码没有复制进本仓库，各插件使用自己的许可证。

## ForgeMono Geometry 6 NF

本仓库四个 TTF 是 **JetBrains Mono NL Nerd Font Mono** 的改名修改版，家族名为 **ForgeMono Geometry 6 NF**。

- 基础字体：[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono)，Copyright 2020 The JetBrains Mono Project Authors，SIL Open Font License 1.1；原始版权和许可证见 [fonts/OFL.txt](fonts/OFL.txt)。
- Nerd Font 补丁来源：[Nerd Fonts / JetBrains Mono](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/JetBrainsMono)。
- 本仓库修改：添加 1.42–1.65 行高银行、窗格圆角、普通/活动焦点描边、标签连接和底栏胶囊裁切；新增 COLR 颜色层和组合字形。基础文字、图标与字宽保留，字体名称已变更。
- 新增几何字形随该衍生字体按 SIL OFL 1.1 提供。第三方图标保留其独立授权和署名。

## 嵌入图标

来源与许可证依据 [Nerd Fonts 字形来源表](https://github.com/ryanoasis/nerd-fonts/blob/master/src/glyphs/README.md)；以下许可证文本一并保留在 [fonts/licenses/](fonts/licenses/)。`SOURCES.json` 记录本次获取的原始 URL 和 SHA-256，Nerd Fonts 的直接文件来自提交 `1002d659b5247d0dc0e5a635e89ab2735ecc2e5b`。该提交标记的是许可证采集来源，不代表基础字体的构建提交。

| 图标/项目与署名来源 | 许可证文本 |
| --- | --- |
| [Nerd Fonts / Ryan L. McIntyre 及贡献者](https://github.com/ryanoasis/nerd-fonts) | [MIT](fonts/licenses/nerd-fonts-LICENSE) |
| [Codicons / Microsoft Corporation](https://github.com/microsoft/vscode-codicons) | [CC BY 4.0](fonts/licenses/codicons-LICENSE.txt) |
| [Devicons / Devicon contributors](https://github.com/devicons/devicon) | [MIT](fonts/licenses/devicons-LICENSE) |
| [Extra glyphs / Hack、Source Foundry](https://github.com/source-foundry/Hack) | [Hack 授权与署名](fonts/licenses/hack-LICENSE.md) |
| [Font Awesome / Fonticons, Inc.](https://github.com/FortAwesome/Font-Awesome) | [Font Awesome 授权（图标 CC BY 4.0）](fonts/licenses/font-awesome-LICENSE.txt) |
| [Font Awesome Extension / Andre Luiz Gava](https://github.com/AndreLZGava/font-awesome-extension) | [MIT](fonts/licenses/font-awesome-extension-LICENSE) |
| [Font Logos / Lukas W. 及贡献者](https://github.com/lukas-w/font-logos) | [Unlicense / public domain](fonts/licenses/font-logos-LICENSE) |
| [Material Design Icons / Pictogrammers 及贡献者](https://github.com/Templarian/MaterialDesign-Font) | [上游声明](fonts/licenses/materialdesign-LICENSE)、[Apache 2.0 全文](fonts/licenses/Apache-2.0.txt) |
| [Octicons / GitHub, Inc.](https://github.com/primer/octicons) | [MIT](fonts/licenses/octicons-LICENSE) |
| [Seti / Jesse Weed](https://github.com/jesseweed/seti-ui) | [MIT](fonts/licenses/seti-ui-LICENSE) |
| [Pomicons / Gabriele Lana](https://github.com/gabrielelana/pomicons) | [OFL 1.1](fonts/licenses/pomicons-LICENSE) |
| [Powerline Extra / Ryan L. McIntyre](https://github.com/ryanoasis/powerline-extra-symbols) | [MIT](fonts/licenses/powerline-extra-LICENSE) |
| [Powerline Symbols / Powerline contributors](https://github.com/powerline/powerline) | [MIT](fonts/licenses/powerline-symbols-LICENSE.txt) |
| [Power Symbols IEC / Joe Loughry](https://github.com/jloughry/Unicode) | [MIT](fonts/licenses/power-symbols-IEC-LICENSE) |
| [Weather Icons / Erik Flowers](https://github.com/erikflowers/weather-icons) | [OFL 1.1](fonts/licenses/weather-icons-OFL.txt) |

Nerd Fonts 的基础图标在几何版本中予以保留；本项目主要新增自己的界面几何字形，并更改字体名称与相关表。图标的原始标志仍可能是各自权利人的商标。以上授权仅按各文件对应范围适用，不将插件、字体和图标统称为单一许可证。
