# 故障排查与平台边界

本配置在 Fedora WSL + Windows Terminal 上完成实际编辑和 UI 检查。Linux、macOS、原生 Windows 的路径和 shell 分支作了兼容处理；这不代表每个平台、字体和外部工具都已经完成实际工程验证。

## 首次启动失败或插件不存在

需要 Neovim 0.12 或更新版本，以及能从 Neovim 进程访问的 Git。首次启动通过原生 `vim.pack` 下载插件，请检查网络和 Git 输出。保留 `nvim-pack-lock.json`，不要用删除锁文件来处理网络故障。

配置目录以 `:echo stdpath('config')` 为准；数据和缓存分别查看 `stdpath('data')`、`stdpath('state')`。Windows 与 WSL 是两套独立的 Neovim 环境，安装在 Windows 的工具不一定能作为 Linux 程序在 WSL 内运行。

`local.lua` 必须返回 Lua table。复制 [local.example.lua](../local.example.lua) 后修改；不要提交包含个人路径的 `local.lua`。语法错误会提示并使用默认配置。

## 字形缺失、标签乱码或圆角不对齐

公共默认使用标准 Nerd Font UI。终端应选择 **Nerd Font Mono**；普通等宽字体可能缺少文件图标和 Powerline 符号。Neovim 无法可靠检测终端实际使用的字体。

只有安装 ForgeMono Geometry 6 NF 的四种样式，并匹配终端字符格高度后，才在 `local.lua` 设置 `round_tabs = true`。专用几何字形的像素效果主要在 Windows Terminal 中验证；其他终端建议先保持兼容模式。

`line_height` 仅设置几何字形的启动默认值，不改变终端行高。已有 `:UiLineHeight` 缓存优先，避免重启时覆盖刚设置的行高。自定义 `terminal_ui.state` 同时决定缓存的写入和读取路径。

Windows Terminal 会缓存字体集合。安装或更新字体后，保存文件，退出全部 Windows Terminal 窗口，再重新打开。其他终端请在各自设置中调整字体、行距或字符格高度；同一终端网格中的文件树、正文、标签和状态栏共享行高，不能分别设置像素高度。

## 缩略图空白或提示渲染器不可用

小字体图像需要 Sixel 终端及 Neovim 0.12，当前已验证 Windows Terminal 1.24。不支持图像的终端无法显示本实现的小字体；它没有自动退回方块轮廓。默认关闭，使用 `空格 u v` 开启。窗口过窄、欢迎页或工具缓冲区时会等待合适的正文窗格。

首次执行 `:MinimapSetup`，需要 Python 3.10+、venv 模块、pip 和网络；它把 Pillow 装入 `stdpath('data')/workbench-minimap-env`，不改系统环境。WSL 安装发生在 Linux 内，Windows 的 Python 包不能替代 Linux 包。命令只在主动执行时下载；已有自己的 Pillow 环境可在 `config.minimap.setup(opts)` 中指定 `python`。终端明确报告不支持 Sixel 时只提示一次，不创建空白窗格。

排查命令：

```vim
:lua print(vim.inspect(require('config.minimap_image').status()))
:lua print(vim.fn.stdpath('data') .. '/workbench-minimap-env')
:lua print(vim.inspect(vim.v.termresponse))
```

`supported=true` 表示当前 TTY 宣告支持 Sixel；`worker` 表示后台在运行，`pending` 表示仍在处理代码图像，`error` 给出渲染错误。Linux/macOS/WSL 的独立解释器位于上述目录的 `bin/python`，原生 Windows 位于 `Scripts/python.exe`。终端重绘、关闭浮窗后会恢复图像。正文和缩略图字号独立：修改 `lines_per_row` 为 `2` 可放大缩略字形，`char_width` 控制横向字符间距，不需要调整正文终端字体。

面板默认上限为 16 列，按编辑区域的 14% 自动收窄，最少 8 列；这些参数位于 `config.minimap` 的 `width`、`max_width_ratio` 和 `min_width`。继续收窄窗口后会暂时隐藏，为正文保留最低 48 列。增大宽度上限时，还需调整比例上限才能在常见屏幕宽度中看到变化。

光标/选区/视野走 8 ms 的独立交互通道，`pending=true` 不应阻止阴影更新。同一代码片段内持续拖选时，`status().code_requests` 应保持不变；换到新的代码片段或编辑文本时才会增长。`shadow_ms` 仅是 Lua 阴影处理耗时，不包含终端传输与物理屏幕延迟。若正文和缩略图同时卡顿，应先排查 Neovim 主线程上的语言工具或其他插件。可视模式帮助仅在按 Leader 后显示，避免进入选区就自动弹窗。

其他 Sixel 终端可按其虚拟像素格调整 `cell_width` / `cell_height`，默认 10×20 是 Windows Terminal 的协议映射，不是物理 DPI 尺寸。纯 GUI Neovim 或终端复用器对图像转发的支持未验证。

## `:UiLineHeight` 提示手动设置或找不到 profile

自动调整终端设置只在 **WSL + Windows Terminal** 中启用。它不在 Neovim 启动时调用 Windows interop，也不会在其他系统尝试修改终端设置。其他系统、非 Windows Terminal 或关闭集成时，无参数报告当前几何行高；带有效参数会立即同步几何字形并保存缓存，提示你手动设置终端行高。

检查 `local.lua` 中 `terminal_ui`：

- `enabled = false` 会关闭 Windows Terminal 后台操作，保留本地几何行高与缓存同步。
- `profile` 必须匹配你的 Windows Terminal profile 名称。
- 重名 profile 需要填写自己的 `guid`，配置没有内置任何用户的 GUID。
- Preview、非打包版 Terminal 或自定义设置位置可指定 `settings`，使用 WSL 能访问的路径，例如 `/mnt/c/.../settings.json`。显式路径也可用于 WSL 中未继承 `WT_SESSION` 的场景。
- `python` 是单个 Python 可执行文件路径，不要把参数写在该字段中。

默认自动探测依赖 WSL 中的 `powershell.exe` 和 `wslpath`；关闭 interop 时，应恢复 interop 或改为手动调整。设置操作会备份目标文件，并同步 Neovim 缓存。查询不会修改 Windows Terminal 设置，但会更新本地缓存。

`scripts/terminal-ui.py` 是 POSIX/WSL 后台：自动探测需要 WSL；Linux/macOS 可用 `--settings` 对明确指定的文件进行隔离验证，原生 Windows 只支持查看 `--help`，实际操作会说明应手动调整。不要把该辅助脚本当作所有终端通用的控制接口。

## 补全、诊断、格式化或高亮没有出现

先使用 `:DevTools`、`:ConformInfo`、`:checkhealth vim.lsp` 检查具体工具。缺少语言服务时会安静跳过，不影响基础编辑。安装工具后执行 `:LspRefresh`，或重新打开文件。

Mason 的工具可用性随平台而异。Perl、Tcl、HDL 及厂商工具可能需要系统包管理器或官方发行包，不能保证一条 Mason 命令在所有系统安装全部工具。PATH 在原生 Windows 使用 `;`，在 Linux/macOS/WSL 使用 `:`；不要复制其他系统的完整 PATH。

Tree-sitter 解析器不随配置仓库发布。当前插件需要 tree-sitter CLI ≥ 0.26.1、C 编译器、tar、curl；按插件要求使用系统包管理器或官方 CLI 发行方式，不用 npm 安装 CLI。准备好工具后运行 `:TSInstallWorkbench`。更新插件后，按需要执行 `:TSUpdate` 同步解析器。

大文件默认跳过 LSP、Tree-sitter 和补全。C/C++ 的宏与头文件需要正确编译数据库；Python 需要项目虚拟环境；Verible 不替代完整仿真/综合；Tcl EDA 命令需要项目规则。详见 [LANGUAGES.md](LANGUAGES.md)。

## 手动缩进与格式化后的缩进不同

没有格式化配置时，C/C++、Lua、Tcl 按缓冲区有效缩进进行格式化。存在 `.clang-format`、StyLua 配置、tclint 配置时，尊重工具整套项目规则，包含未指定字段的工具默认值。请同步项目 `.editorconfig` 和格式化配置，不要假定只设置行宽的配置会继承编辑器缩进。

StyLua 的父目录及 XDG/Home 全局配置也可能生效；参见 [StyLua 配置查找规则](https://github.com/JohnnyMorganz/StyLua#finding-the-configuration)。Tcl 从目标文件目录向上查找规则，不依赖启动目录。Makefile 不配置通用格式化器，保留配方需要的真实 Tab。

## 终端或 `:Build` 启动失败

检查 `:set shell? shellcmdflag?`。终端启动遵守 `shell` 的可执行文件和固定参数；构建还使用 `shellcmdflag`，默认 Unix 为 `-c`，Windows cmd.exe 为 `/s /c`。修改 shell 时同时检查 Neovim 的相关 shell 选项。

例如希望使用 PowerShell，可以在个人 `local.lua` 的 `return` 前设置：

```lua
vim.opt.shell = "pwsh"
vim.opt.shellcmdflag = "-NoLogo -NoProfile -Command"
```

带空格的 shell 路径按 `:help shell-unquoting` 使用双引号；PATH、cwd 和工具权限应在实际运行 Neovim 的系统中有效。构建命令属于你的工程，本配置不会替你安装厂商工具或猜测环境变量。

终端以创建时的项目为归属，终端内部手动 `cd` 不改变项目缓存。后台构建完成不会抢其他项目的错误列表，使用 `:BuildResults` 显式查看当前项目最近的输出。

## 文件树无法切换或窗口太拥挤

先按 Esc，再按 `空格 e` 在文件树和编辑区间切换。`Ctrl+h/l` 按空间相邻窗口移动；“树 | 文件一 | 文件二”的布局从文件二返回树需要两次 `Ctrl+h`。

少于 24 列或 8 行时会进入紧凑模式，收起部分装饰。终端保留的快捷键可能拦截 `Ctrl+h/l` 或 `Ctrl+方向键`；检查终端按键绑定后，可使用 `空格 e` 或原生 `Ctrl+w` 导航。

系统剪贴板可用 `"+y` / `"+p`。WSL 检测到 win32yank.exe 后会自动集成；其他系统使用各自的 Neovim clipboard provider，并可按需要在个人配置设置 `vim.opt.clipboard = "unnamedplus"`。Linux Wayland/X11 可能需要安装 wl-clipboard/xclip。
