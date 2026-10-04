# 语言支持与工程配置

语言工具由系统或 Mason 提供，仓库只包含 Neovim 配置。缺少工具时跳过相应服务；使用 `:DevTools` 查看实际可执行文件，使用 `:Mason` 安装或管理工具。

## 支持范围

| 语言 / 文件 | 语言服务与检查 | 格式化 | 工程要求 |
| --- | --- | --- | --- |
| C / C++ | clangd，后台索引、clang-tidy | clang-format | include 路径、宏和标准依赖编译数据库 |
| Python | basedpyright + Ruff | Ruff | 项目虚拟环境、依赖与检查规则 |
| Verilog / SystemVerilog | Verible | verible-verilog-format | 源码清单、lint 规则；完整工程检查需仿真器或综合工具 |
| Perl | PerlNavigator，可配合 Perl::Critic | perltidy | Perl 模块搜索路径与项目检查策略 |
| Tcl / SDC / XDC / UPF | tclsp（tclint） | tclfmt | EDA 命令需要对应工具规则或 tclint 插件 |
| Makefile / `.mk` | Tree-sitter、内置文件类型规则 | 不配置 | recipe 保留真实 Tab |
| Lua | lua-language-server | StyLua | 普通 Lua 项目配置优先；Neovim 配置识别 `vim` API |

`.v` / `.vh` 识别为 Verilog，`.sv` / `.svh` 识别为 SystemVerilog；`.sdc` / `.xdc` / `.upf` / `.itcl` 识别为 Tcl。文件类型规则在 [languages.lua](../lua/config/languages.lua)，缩进规则在 [autocmds.lua](../lua/core/autocmds.lua)。

LSP 快捷键按服务实际支持的能力注册。Verible 的语法、风格与符号检查不能替代完整 SystemVerilog 语义分析或 UVM 仿真；Tcl 服务主要用于检查和格式化，不承诺定义跳转、重命名或语义补全。没有相应服务能力时，仍可使用文本、路径与片段补全。

## 安装与检查

安装配置后，在 Neovim 中运行：

```vim
:MasonInstall clangd clang-format basedpyright ruff verible perlnavigator tclint lua-language-server stylua
:TSInstallWorkbench
```

`TSInstallWorkbench` 需要 C 编译器和 `tree-sitter-cli >= 0.26.1`，只在明确执行命令时下载解析器。配置启用 C、C++、Python、SystemVerilog、Perl、Tcl、Make、Lua、Vim、Vimdoc、Query、Bash、JSON、YAML、Markdown 和 Markdown Inline 解析器；Verilog 共用 SystemVerilog 解析器。

Perl 格式化和检查还需要 `perltidy` 与 `Perl::Critic`。可按平台用系统包管理器安装，例如 Fedora：

```sh
sudo dnf install perltidy perl-Perl-Critic
```

系统或用户工具目录中的可执行文件也可以使用，不要求全部通过 Mason 安装。安装新工具后运行 `:LspRefresh` 重新检查语言服务。

```vim
:DevTools
:checkhealth vim.lsp
:ConformInfo
:Mason
```

## 缩进与格式化

| 文件类型 | 默认缩进 |
| --- | --- |
| C / C++、Python、Perl、Verilog / SystemVerilog | 4 个空格 |
| Lua、Tcl | 2 个空格 |
| Makefile | 真实 Tab，显示宽度 8 |

Tab 默认执行缩进，片段展开后用 Tab / Shift+Tab 跳转占位符。补全选择用 Ctrl+n / Ctrl+p，回车接受已选候选。

仓库的 Verilog/SV、Perl 片段正文使用 4 空格缩进，Tcl 片段使用 2 空格；Make recipe 片段使用真实 Tab。

默认关闭保存时格式化：

- `<leader>cf` 或 `:Format`：手动格式化当前文件或选区。
- `<leader>uf`：切换当前会话的保存时格式化，只作用于 C/C++、Python、Lua。
- Verilog/SV、Perl、Tcl 始终由手动操作触发；Makefile 不启用通用格式化器。

格式化规则集中在 [formatting.lua](../lua/config/formatting.lua)。没有工具规则文件时，C/C++、Lua、Tcl 的格式化跟随缓冲区有效缩进；Verible 读取当前缩进宽度。已有 `.clang-format`、StyLua、tclint 等项目规则时，保留工具整套配置与默认值。项目 `.editorconfig` 和工具格式规则应保持一致。

## C / C++

clangd 需要真实编译参数，才能正确识别工程头文件、宏、交叉编译器和语言标准。CMake 工程可以生成编译数据库：

```sh
cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

如果数据库位于 `build`，可以在工程根目录添加 `.clangd`：

```yaml
CompileFlags:
  CompilationDatabase: build
```

传统 Make 工程可以安装 Bear 后捕获实际编译命令：

```sh
bear -- make
```

Make 若没有执行编译，Bear 不会捕获新的编译参数。交叉编译器的 query-driver、厂商头文件和目标参数应按工程配置。参考 [clangd 项目设置](https://clangd.llvm.org/installation)。

## Python

项目优先使用自己的虚拟环境和依赖清单。使用 `.venv` 时，可按需要在 `pyrightconfig.json` 中显式指定：

```json
{
  "venvPath": ".",
  "venv": ".venv",
  "typeCheckingMode": "standard"
}
```

basedpyright 负责类型检查、补全和导航；Ruff 负责 lint、修复和格式化。Ruff 规则、行宽和忽略项放在 `pyproject.toml`、`ruff.toml` 或 `.ruff.toml` 中。

参考 [basedpyright 配置](https://docs.basedpyright.com/latest/configuration/config-files/) 和 [Ruff 配置](https://docs.astral.sh/ruff/configuration/)。

## Verilog / SystemVerilog

在工程根目录添加 `verible.filelist`，写入源码列表，例如：

```text
rtl/counter.sv
rtl/counter_tb.sv
```

语言服务使用 `--rules_config_search`，可以向上查找 `.rules.verible_lint`。Verible 格式化使用缓冲区有效缩进宽度，默认 4 空格。

工程的 include 路径、宏、库、top 与 UVM 环境需要实际仿真器配置。可以通过 `:Build` 输入 Verilator、Icarus 或厂商工具的工程命令；仓库不会替工程选择仿真器或自动运行仿真。

自定义片段包括：

| 文件类型 | 前缀 |
| --- | --- |
| Verilog | `rtlmod`、`seq` |
| SystemVerilog | `rtlmod`、`ff`、`comb` |

参考 [Verible 语言服务](https://github.com/chipsalliance/verible/blob/master/verible/verilog/tools/ls/README.md)。

## Tcl、Perl 与 Make

Tcl 工程规则放在 `tclint.toml`、`.tclint` 或 `pyproject.toml` 的 `[tool.tclint]` 中。SDC/XDC/UPF 的命令取决于具体 EDA 工具，需要对应规则或插件。Tcl 格式化从目标文件目录查找配置，启动目录在工程外也可以使用项目规则。

Perl 工程需要安装自己的依赖、配置模块搜索路径与 Perl::Critic 策略。片段 `plmain` 插入带 strict/warnings 的脚本骨架，`sub` 插入函数骨架。

Make 的 `rule` / `phony` 片段使用真实 Tab。构建目标、环境变量与错误输出格式由工程决定；`:Build` 保留源缓冲区的 `errorformat`，结果进入 Quickfix，使用 `:BuildResults` 查看当前项目最近的构建输出。

参考 [tclint](https://github.com/nmoroze/tclint) 和 [PerlNavigator](https://github.com/bscan/PerlNavigator)。

## 大文件与进一步扩展

超过 1 MiB 或 20,000 行的文件跳过 LSP、Tree-sitter 和补全，折叠回退为普通模式。阈值可以在 [languages.lua](../lua/config/languages.lua)、[treesitter.lua](../lua/config/treesitter.lua) 和 [completion.lua](../lua/config/completion.lua) 中调整。

调试适配器、单元测试、RTL 仿真、波形查看与远程目标需要项目的真实程序和工具链。本配置提供终端与构建入口，调试和测试框架可按实际工程继续接入。
