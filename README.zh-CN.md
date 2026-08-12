# zsh-wordnav

[English](README.md) | 简体中文

Zsh 智能单词导航与删除插件。

用 **vi 风格的"严格" word motion**（一次跳过/删除一段连续的 word 字符或非 word 字符）、**更聪明的 Ctrl+W**（连尾部空格一起删掉），以及**连续裁剪累积**机制（一次 Ctrl+Y 全部 yank 回来）替换 Zsh 默认的单词移动 / 删除 widgets。

## 功能特性

- **`WORDCHARS='_'`** —— 只有字母数字和下划线算 word 字符，其他所有标点 / 符号都作为分隔符。
- **Ctrl+Left / Ctrl+Right** —— 跳过一段连续的 word 字符 *或* 非 word 字符。反复按会在 `foo` → `, ` → `bar` 之间一段一段走，而不是一次跳过整个 `foo, bar`。
- **Ctrl+Backspace / Ctrl+Delete** —— 向前 / 向后删除一段连续的 run，删除内容进入 kill ring。
- **Ctrl+W** —— bash 风格的空白分隔 backward kill，但更聪明：
  - 光标前是空格：只删除那段空格。
  - 光标前是非空格：先删除连续非空格，*再* 删除其前的连续空格（`foo  bar|` → `foo|`，而不是 `foo  |`）。
- **连续裁剪累积** —— 连续按 kill widget（中间没有别的操作）会合并成 kill ring 里的**单条**记录，所以 `Ctrl+W Ctrl+W Ctrl+W` 后一次 `Ctrl+Y` 能把整段一起 yank 回来。连续检测用的是 `zle-line-pre-redraw` 钩子而非 `$LASTWIDGET`，因此在 **zsh-autosuggestions** 异步拉取建议时也能正确累积（异步建议会把 `$LASTWIDGET` 改成 `autosuggest-suggest`，破坏传统的 `$LASTWIDGET` 检测）。
- **`yank-pop`**（通常是 `Meta+Y`，在 `Ctrl+Y` 之后）照常轮换更早的 kill ring 条目。

## 安装

### Oh My Zsh

```zsh
git clone https://github.com/foursmonth/zsh-wordnav ~/.oh-my-zsh/custom/plugins/zsh-wordnav
```

然后在 `~/.zshrc` 的 plugins 列表里加上 `zsh-wordnav`：

```zsh
plugins=(git z extract zsh-wordnav)
```

### zinit / zplug 等

```zsh
# zinit
zinit light foursmonth/zsh-wordnav

# zplug
zplug "foursmonth/zsh-wordnav"
```

### 手动安装

在 `~/.zshrc` 里 source 插件文件即可：

```zsh
source /path/to/zsh-wordnav/zsh-wordnav.plugin.zsh
```

## 快捷键

| 按键             | Widget              | 行为                                            |
|------------------|---------------------|-------------------------------------------------|
| `Ctrl+Left`      | `backward-word`     | 向左跳过一段连续的 word / 非 word 字符          |
| `Ctrl+Right`     | `forward-word`      | 向右跳过一段连续的 word / 非 word 字符          |
| `Ctrl+Backspace` | `backward-kill-word` | 向左删除一段（→ kill ring）                     |
| `Ctrl+Delete`    | `kill-word`         | 向右删除一段（→ kill ring）                     |
| `Ctrl+W`         | `unix-word-rubout`  | 向左删除空白分隔的 token（→ kill ring）        |
| `Ctrl+Y`         | `yank`              | yank kill ring（Zsh 内置；使用累积后的条目）     |
| `Meta+Y`         | `yank-pop`          | 轮换更早的 kill ring 条目（Zsh 内置）           |

插件直接替换标准 widgets（`backward-word`、`forward-word`、`kill-word`、`backward-kill-word`、`unix-word-rubout` 以及 `vi-backward-kill-word`），所以任何已有的键绑定（包括通过 terminfo 解析的 Ctrl+方向键序列）都会自动套用新行为。同时显式绑定了常见的 Ctrl+修饰键序列，以兼容 terminfo 不标准的终端。

## 行为示例

光标位置用 `|` 表示。

### Word 移动（Ctrl+Left / Ctrl+Right）

```
缓冲区:  foo, bar
从每个位置按 Ctrl+Right：
  |foo, bar   →  foo|, bar   （跳过 word "foo"）
  foo|, bar   →  foo, |bar   （跳过非 word ", " — 逗号和空格一起）
  foo, |bar   →  foo, bar|   （跳过 word "bar"）
```

说明：一次按键只跳过**一段连续的 run** —— 要么是 word run，要么是非 word run。因为 `,` 和 ` ` 都是非 word，所以会被当作一个 run 一起跳过。走完 `foo, bar` 需要 3 次：word → 非 word → word。

### Ctrl+W（更聪明的 unix-word-rubout）

```
foo  bar|        Ctrl+W →  foo|              （删除 "  bar"，含前导空格）
foo  bar  |      Ctrl+W →  foo  bar|         （只删除 "  "，尾部空格）
abc|             Ctrl+W →  |                  （删除 "abc"，前面没有空格）
```

对比 bash 默认的 `unix-word-rubout`：在 `foo  bar|` 上只会删 `bar`、留下 `foo  |`。

### 连续裁剪与 Ctrl+Y

```
foo  bar  baz|   Ctrl+W  →  foo  bar|        （CUTBUFFER = "  baz"）
                  Ctrl+W  →  foo|             （CUTBUFFER = "  bar  baz"）
                  Ctrl+W  →  |                （CUTBUFFER = "foo  bar  baz"）
Ctrl+Y            →  foo  bar  baz|          （一次 yank 整段合并内容）
```

如果两次 kill 之间插入了非 kill widget，累积会断开，更早的内容会轮转到 kill ring（可用 `Meta+Y` / `yank-pop` 取出）。

## 配置项

两个变量都可以在 **source 插件之后**设置。

### `WORDCHARS`

默认：`'_'`。除字母数字外，被当作 word 字符参与移动的额外字符。设为 `''` 表示纯字母数字 word motion；设为 `'-_'` 则连字符也算 word 字符。

```zsh
source /path/to/zsh-wordnav/zsh-wordnav.plugin.zsh
WORDCHARS='-_'   # word 包含连字符和下划线
```

### `_ZSH_WORDNAV_KILLRING_MAX`

默认：`32`。kill ring 保留的最大条目数，超出时丢弃最旧的。

```zsh
_ZSH_WORDNAV_KILLRING_MAX=64
```

### `_ZSH_WORDNAV_AUTOSUGGEST_FIXUP`

默认：`1`（启用）。为 `1` 时，zsh-wordnav 会修复与
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) 的一个
交互问题：`Ctrl+Y`（yank）撤销删除后，过期的灰色历史建议不会被刷新。

zsh-autosuggestions 默认把 `yank` 和 `yank-pop` 列在
`ZSH_AUTOSUGGEST_IGNORE_WIDGETS` 里，导致 `Ctrl+Y` 之后建议永远不会刷新。表现
就是你看到的 `ls -a /etc| /etc` —— 光标后面那个 `/etc` 是 yank 之前残留的旧
建议，并不是基于当前 buffer 的新建议。

启用本修复后，zsh-wordnav 会在两个插件都加载完后的第一个 `precmd` 上，把
`yank` / `yank-pop` 从忽略列表里移除并重新绑定，让 `yank` 变成一个普通的
buffer 修改 widget，从而基于恢复后的 buffer 重新拉取建议。该修复对插件加载
顺序不敏感，执行一次后自动从 precmd 钩子中卸载。

如需关闭（保留 zsh-autosuggestions 默认的 yank 忽略行为）：

```zsh
_ZSH_WORDNAV_AUTOSUGGEST_FIXUP=0
```

## 测试

```zsh
zsh test/run_tests.zsh
```

共 147 个非交互式测试，覆盖：word 字符分类、所有移动 widgets、所有删除 widgets、连续裁剪累积（含模拟 zsh-autosuggestions 异步拉取建议的场景）、混合向前 / 向后删除顺序、kill ring 轮转，**空操作 kill 不会污染下一次 kill** 的回归测试，zsh-autosuggestions 的 yank 建议刷新修复，以及 `zle-line-pre-redraw` 连续 kill 追踪钩子的分类逻辑（kill widgets、插件内部 widgets、用户操作 widgets 都正确处理）。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
