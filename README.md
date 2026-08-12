# zsh-wordnav

English | [简体中文](README.zh-CN.md)

Smart word navigation and deletion for Zsh.

Replaces the default word motion / deletion widgets with **vi-style "strict"
word motion** (skip one contiguous run of either word-chars or non-word-chars),
a **smarter Ctrl+W** that eats trailing whitespace too, and **consecutive kill
accumulation** so Ctrl+Y yanks the whole combined region at once.

## Features

- **`WORDCHARS='_'`** — only alphanumerics and underscore are word characters.
  Everything else (punctuation, symbols) is a separator.
- **Ctrl+Left / Ctrl+Right** — skip one contiguous run of word *or* non-word
  characters. Repeated presses walk through `foo` → `,` → ` ` → `bar` one
  run at a time, instead of jumping the whole `foo, bar`.
- **Ctrl+Backspace / Ctrl+Delete** — delete one contiguous run backward / forward,
  with the deleted text pushed to the kill ring.
- **Ctrl+W** — bash-style whitespace-delimited backward kill, but smarter:
  - If the cursor follows whitespace, delete only that whitespace run.
  - If it follows non-whitespace, delete the non-whitespace run *and* the
    whitespace run preceding it (so `foo  bar|` → `foo|`, not `foo  |`).
- **Consecutive kills accumulate** into a single kill-ring entry, so
  `Ctrl+W Ctrl+W Ctrl+W` followed by `Ctrl+Y` yanks everything back at once.
  Consecutive detection uses a `zle-line-pre-redraw` hook instead of
  `$LASTWIDGET`, so it works correctly alongside **zsh-autosuggestions**
  (whose async suggestion fetching otherwise corrupts `$LASTWIDGET` and breaks
  accumulation).
- **`yank-pop`** (usually `Meta-y` after `Ctrl+Y`) cycles through older
  kill-ring entries as usual.

## Installation

### Oh My Zsh

```zsh
git clone https://github.com/foursmonth/zsh-wordnav ~/.oh-my-zsh/custom/plugins/zsh-wordnav
```

Then add `zsh-wordnav` to your plugins list in `~/.zshrc`:

```zsh
plugins=(git z extract zsh-wordnav)
```

### zinit / zplug / etc.

```zsh
# zinit
zinit light foursmonth/zsh-wordnav

# zplug
zplug "foursmonth/zsh-wordnav"
```

### Manual

Just source the plugin file from your `~/.zshrc`:

```zsh
source /path/to/zsh-wordnav/zsh-wordnav.plugin.zsh
```

## Keybindings

| Key            | Widget              | Action                                                      |
|----------------|---------------------|-------------------------------------------------------------|
| `Ctrl+Left`    | `backward-word`     | Skip one run of word / non-word chars backward              |
| `Ctrl+Right`   | `forward-word`      | Skip one run of word / non-word chars forward               |
| `Ctrl+Backspace` | `backward-kill-word` | Delete one run backward (→ kill ring)                       |
| `Ctrl+Delete`  | `kill-word`         | Delete one run forward (→ kill ring)                         |
| `Ctrl+W`       | `unix-word-rubout`  | Delete whitespace-delimited token backward (→ kill ring)    |
| `Ctrl+Y`       | `yank`              | Yank the kill ring (built-in; uses the accumulated entry)    |
| `Meta+Y`       | `yank-pop`          | Cycle through older kill-ring entries (built-in)            |

The plugin replaces the standard widgets (`backward-word`, `forward-word`,
`kill-word`, `backward-kill-word`, `unix-word-rubout`, and their `vi-*`
variants), so any existing keybinding (including terminfo-resolved Ctrl+Arrow
sequences) automatically picks up the new behavior. Common Ctrl-modified key
sequences are also bound explicitly for terminals with non-standard terminfo.

## Behavior examples

Cursor position is shown as `|`.

### Word motion (Ctrl+Left / Ctrl+Right)

```
Buffer:  foo, bar
Press Ctrl+Right from each position:
  |foo, bar   →  foo|, bar   (skip word "foo")
  foo|, bar   →  foo, |bar   (skip non-word ", " — comma AND space together)
  foo, |bar   →  foo, bar|   (skip word "bar")
```

Note: one press skips a single contiguous run — *either* a word run *or* a
non-word run. Since `,` and ` ` are both non-word, they're skipped together
as one run. Traversing `foo, bar` takes 3 presses: word → non-word → word.

### Ctrl+W (smarter unix-word-rubout)

```
foo  bar|        Ctrl+W →  foo|              (deletes "  bar", with leading spaces)
foo  bar  |      Ctrl+W →  foo  bar|         (deletes only "  ", trailing spaces)
abc|             Ctrl+W →  |                  (deletes "abc", no preceding space)
```

Compare with bash's default `unix-word-rubout`, which on `foo  bar|` would
delete only `bar` and leave `foo  |` behind.

### Consecutive kills & Ctrl+Y

```
foo  bar  baz|   Ctrl+W  →  foo  bar|        (CUTBUFFER = "  baz")
                  Ctrl+W  →  foo|             (CUTBUFFER = "  bar  baz")
                  Ctrl+W  →  |                (CUTBUFFER = "foo  bar  baz")
Ctrl+Y            →  foo  bar  baz|          (yanks the combined region)
```

If a non-kill widget runs between two kills, the accumulation breaks and the
older text rotates onto the kill ring (reachable via `Meta+Y` / `yank-pop`).

## Configuration

Both variables can be set **after** sourcing the plugin.

### `WORDCHARS`

Default: `'_'`. Extra characters (beyond alphanumerics) treated as word
characters for motion. Set to `''` for pure alphanumeric word motion, or to
e.g. `'-_'` to also treat hyphens as word characters.

```zsh
source /path/to/zsh-wordnav.plugin.zsh
WORDCHARS='-_'   # words include hyphens and underscores
```

### `_ZSH_WORDNAV_KILLRING_MAX`

Default: `32`. Maximum number of entries kept in the kill ring. Older entries
are dropped when the ring overflows.

```zsh
_ZSH_WORDNAV_KILLRING_MAX=64
```

### `_ZSH_WORDNAV_AUTOSUGGEST_FIXUP`

Default: `1` (enabled). When `1`, zsh-wordnav fixes an interaction with
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) where
`Ctrl+Y` (yank) leaves a stale ghost suggestion on screen.

By default zsh-autosuggestions lists `yank` and `yank-pop` in
`ZSH_AUTOSUGGEST_IGNORE_WIDGETS`, so after `Ctrl+Y` the suggestion is never
refreshed. The result is a confusing display like `ls -a /etc| /etc` — the
second `/etc` is the stale suggestion left over from before the yank, not the
fresh suggestion for the new buffer.

When this flag is on, zsh-wordnav removes `yank`/`yank-pop` from the ignore
list on the first `precmd` after both plugins have loaded, then re-binds so
`yank` becomes a normal buffer-modifying widget that fetches a fresh
suggestion matching the restored buffer. The fixup is load-order tolerant and
self-unloads after running once.

Set to `0` to disable (e.g. if you prefer zsh-autosuggestions's default
yank-ignored behavior):

```zsh
_ZSH_WORDNAV_AUTOSUGGEST_FIXUP=0
```

## Tests

```zsh
zsh test/run_tests.zsh
```

147 non-interactive tests covering word classification, all motion widgets,
all kill widgets, consecutive-kill accumulation (including under simulated
zsh-autosuggestions async suggestion fetching), mixed forward/backward kills,
kill-ring rotation, no-op-kill regression (a no-op kill widget must not cause
the next real kill to wrongly accumulate), the zsh-autosuggestions
yank-suggestion fixup, and the `zle-line-pre-redraw` consecutive-kill tracker
classification (kill widgets, internal/plugin widgets, and user-facing widgets
all handled correctly).

## License

MIT — see [LICENSE](LICENSE).
