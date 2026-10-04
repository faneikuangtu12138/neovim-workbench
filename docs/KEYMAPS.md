# 快捷键与工作流

Leader 是空格。除保存、补全和终端专用按键外，以下操作在普通模式中使用；编辑时先按 Esc。

## 文件树、窗口与缓冲区

| 按键 | 操作 |
| --- | --- |
| `<leader>e` | 在文件树与最近的编辑窗口之间切换 |
| `<leader>E` | 在文件树中定位当前文件 |
| `<leader>ue` | 显示 / 隐藏文件树 |
| Ctrl+h / j / k / l | 移到相邻左 / 下 / 上 / 右窗口，跳过装饰窗口 |
| Ctrl+w h / j / k / l | 同上 |
| `<leader>\|` / `<leader>-` | 右侧 / 下方分屏 |
| Ctrl+方向键 | 调整当前分屏尺寸 |
| Shift+h / Shift+l | 上一个 / 下一个文件缓冲区 |
| `[b` / `]b` | 上一个 / 下一个文件缓冲区 |
| `<leader>bd` | 关闭文件缓冲区，保留窗口布局；未保存内容仍受保护 |
| `<leader>bp` | 挑选文件缓冲区 |
| `<leader>bn` | 新建空白缓冲区 |
| `<leader>w` / Ctrl+s | 保存文件；Ctrl+s 也可在插入模式、可视模式使用 |
| `<leader>q` | 退出当前窗口 |
| Esc | 清除搜索高亮 |

顶部文件标签表示缓冲区，与 Neovim 的 Tab page 不同。普通 `:tabnew` 可以另建一组窗口布局；终端按 Neovim Tab page 与项目共同缓存。

Ctrl+h/l 按相邻窗口移动。例如“文件树 | 文件 A | 文件 B”布局中，从 B 返回文件树需要两次 Ctrl+h；`<leader>e` 直接切到文件树。

| 文件树内按键 | 操作 |
| --- | --- |
| 回车 / `l` | 打开文件、展开目录 |
| `h` | 收起目录 |
| Tab | 返回最近的编辑窗口 |
| `a` / `A` | 新建文件 / 新建目录 |
| `r` / `d` | 重命名 / 删除，删除遵循 Neo-tree 确认流程 |
| `P` | 浮窗预览 |

文件树与编辑区之间的 `⋮` 和分隔区可以左右拖动。顶部 Files / Bufs / Git 按钮切换来源，并使用当前项目目录。

创建文件：`<leader>e` → 选中目录 → `a` → 输入文件名 → 回车 → 选中新文件 → 回车 → `i` 编辑 → Esc → `<leader>w` 保存。

## 查找与搜索

| 按键 | 操作 |
| --- | --- |
| `<leader>ff` / `<leader>fg` | 查找项目文件 / 搜索项目文本 |
| `<leader>fb` / `<leader>fr` | 查找缓冲区 / 最近文件 |
| `<leader>fc` | 查找 Neovim 配置文件 |
| `<leader>fF` | 在当前 cwd 查找文件，替代自动项目目录 |
| `<leader>fh` | 搜索帮助标签 |
| `<leader>sw` | 搜索光标下单词 |
| `<leader>ss` | 搜索文档符号 |
| `<leader>sk` | 搜索快捷键 |
| `<leader>sr` | 恢复上一个 Telescope 搜索 |
| Telescope 插入模式 Ctrl+j / Ctrl+k | 下一个 / 上一个候选 |

文件树、搜索和构建识别 `.git`、Make/CMake、Python、Verible、Tcl、Lua 与编译数据库等项目标记。独立文件使用最近的现存父目录；跨目录文件树定位不修改 Neovim 全局 cwd。

## 代码、补全与诊断

服务支持对应能力时，LSP 按键在当前缓冲区生效：

| 按键 | 操作 |
| --- | --- |
| `gd` / `gr` | 定义 / 引用 |
| `gI` / `gy` | 实现 / 类型定义 |
| `K` / `<leader>cs` | 文档 / 签名帮助 |
| `<leader>cr` | 重命名符号 |
| `<leader>ca` | 代码操作，普通模式或可视模式 |
| `<leader>cd` | 当前行诊断 |
| `[d` / `]d` | 上一个 / 下一个诊断 |
| `<leader>cl` | 检查 LSP 健康状态 |
| `<leader>cf` | 格式化文件或选区 |
| `<leader>uf` | 切换保存时格式化，只作用于 C/C++、Python、Lua |
| `<leader>xx` / `<leader>xd` | 已加载缓冲区诊断列表 / 当前文件诊断 |
| `<leader>xq` | 显示 / 隐藏 Quickfix |
| `[q` / `]q` | 上一个 / 下一个 Quickfix 项目 |

补全在插入模式中使用：

| 按键 | 操作 |
| --- | --- |
| Ctrl+Space | 手动显示补全 |
| Ctrl+n / Ctrl+p | 选择下一个 / 上一个候选 |
| 回车 | 接受已选候选；没有选择时保持回车行为 |
| Tab / Shift+Tab | 片段的下一个 / 上一个占位符；否则保留默认按键行为 |

Tab 不用于强制接受补全，通常仍执行正常缩进。语言工具与项目配置见 [LANGUAGES.md](LANGUAGES.md)。

## 终端与构建

| 按键 / 命令 | 操作 |
| --- | --- |
| `<leader>tt` / `:TermToggle` | 显示 / 隐藏当前项目终端 |
| 终端中 Esc Esc | 离开终端输入模式 |
| 终端中 Ctrl+h / j / k / l | 离开终端输入模式并移到相邻窗口 |
| `<leader>tm` / `:Build` | 输入工程命令并异步运行 |
| `:Build make target` | 以给定命令作为输入框默认值，确认后运行 |
| `:BuildResults` | 查看当前项目最近的构建结果 |

切换项目会保留原终端进程和内容；同一个 Tab 一次显示一个受管理终端窗格。关闭 Tab 后终端可以隐藏保留，后续打开同一项目时复用。终端内手动 `cd` 不改变编辑器记录的创建项目。

构建使用工程目录执行，错误按源缓冲区 `errorformat` 解析。当前来源构建失败时打开 Quickfix；其它项目或已关闭 Tab 的后台结果不切换正在查看的错误列表。`:BuildResults` 显式选择当前项目结果，包括恢复被 Quickfix 历史挤出的列表。

编译运行磁盘上的文件，请先保存编辑。构建命令、环境变量、测试与仿真目标由工程决定。

## Git 与编辑操作

Git hunk 操作只在 GitSigns 已附加的缓冲区生效：

| 按键 | 操作 |
| --- | --- |
| `<leader>gg` | Git 状态 |
| `<leader>gp` | 预览当前 hunk |
| `<leader>gs` | 暂存当前 hunk |
| `<leader>gr` | 回退当前 hunk，会修改当前代码 |
| `<leader>gb` | 当前行作者 |
| `[h` / `]h` | 上一个 / 下一个 hunk |
| `gc` / `gcc` | 注释选区 / 当前行，使用 Neovim 内置操作 |
| `sa` / `sd` / `sr` | 添加 / 删除 / 替换包围字符 |
| 可视模式 `<` / `>` | 左 / 右缩进并保留选择 |
| `zc` / `zo` / `zM` / `zR` | 收起 / 展开折叠，全部收起 / 展开 |

`gr` 是 LSP 引用操作，`<leader>gr` 是 Git hunk 回退；两者是不同按键序列。

## 界面与维护

| 按键 / 命令 | 操作 |
| --- | --- |
| `<leader>uk` | 切换底栏按键记录 |
| `<leader>uv` / `:MinimapToggle` | 显示 / 隐藏右侧代码缩略图 |
| `:MinimapOpen` / `:MinimapClose` | 明确打开 / 关闭缩略图，重复执行不会创建多个窗格 |
| `<leader>uw` | 切换当前窗口的自动折行 |
| `<leader>ud` | 切换当前缓冲区诊断，同时更新缩略图的诊断点 |
| `<leader>uh` | 切换内联提示，实际显示取决于服务能力 |
| `<leader>ui` / `:DevTools` | 查看语言与工程工具状态 |
| `<leader>um` / `:Mason` | 管理语言工具 |
| `<leader>?` | 显示当前快捷键 |
| `:ConformInfo` | 查看当前格式化器 |
| `:LspRefresh` | 安装工具后重新检查语言服务 |
| `:TSInstallWorkbench` | 手动安装本配置的解析器 |
| `:lua vim.pack.update()` | 更新插件与锁文件 |

专用圆角字体和 Windows Terminal 行高设置见仓库 [README](../README.md)。快捷键源文件为 [keymaps.lua](../lua/core/keymaps.lua)，语言操作在 [languages.lua](../lua/config/languages.lua)，格式化操作在 [formatting.lua](../lua/config/formatting.lua)。

缩略图默认关闭，按空格 → `u` → `v` 切换。它跟随最近聚焦的正文窗口，文件树获得焦点时保留该文件的轮廓；键盘窗口导航跳过缩略图。当前视野以浅色背景与左侧竖线标示，光标用青色三角标记，诊断用彩色圆点标示。它是只读概览，不接收鼠标点击或键盘焦点。窄窗中临时隐藏不会清除开关状态；若只想关闭，仍可再次使用快捷键。超过 20,000 行或 1 MiB 时保留滚动位置指示，跳过代码轮廓编码。
