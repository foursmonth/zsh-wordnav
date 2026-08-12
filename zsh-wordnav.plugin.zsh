# zsh-wordnav.plugin.zsh
# Smart word navigation and deletion for Zsh.
#
# Features:
#   - WORDCHARS restricted to '_' (underscore). Alphanumerics are always word
#     characters; punctuation is treated as a separator.
#   - Ctrl+Left / Ctrl+Right / Ctrl+Backspace / Ctrl+Delete skip or delete one
#     contiguous run of EITHER word characters OR non-word characters
#     (vi-style "strict" word motion).
#   - Ctrl+W deletes a whitespace-delimited token backward, including the
#     trailing whitespace run (smarter than bash's unix-word-rubout).
#   - All deleted text is pushed to the kill ring, and consecutive kills
#     accumulate into a single CUTBUFFER entry so Ctrl+Y yanks the whole
#     combined region in one shot.
#
# Author: ly
# License: MIT

# Guard against double sourcing.
(( ${+_ZSH_WORDNAV_LOADED} )) && return
_ZSH_WORDNAV_LOADED=1

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Restrict WORDCHARS to underscore. Alphanumerics are always word chars;
# everything else is treated as a non-word separator for word motion.
# This is set unconditionally because the plugin's entire purpose is this
# behavior — override AFTER sourcing if you need a different set.
WORDCHARS='_'

# Maximum number of entries kept in the kill ring.
(( ${+_ZSH_WORDNAV_KILLRING_MAX} )) || _ZSH_WORDNAV_KILLRING_MAX=32

# Tracks whether the most recently invoked kill widget *actually deleted
# something*. ZLE sets $LASTWIDGET to the widget name regardless of whether
# it modified the buffer, so a no-op kill (e.g. Ctrl+W at the start of the
# line) would still make the *next* kill look "consecutive" and wrongly
# accumulate. We pair LASTWIDGET with this flag to detect the real situation.
typeset -g _ZSH_WORDNAV_LAST_KILL_REAL=0

# ---------------------------------------------------------------------------
# Word-char classification
# ---------------------------------------------------------------------------

# _zsh_wordnav_is_word_char <char>
# Returns 0 (true) if $1 is a word character: alphanumeric (locale-aware) or
# present in $WORDCHARS. The "$1" on the WORDCHARS check is quoted so special
# pattern chars (e.g. '*') only ever match themselves.
_zsh_wordnav_is_word_char() {
    [[ -n $1 && $1 == [[:alnum:]] ]] && return 0
    [[ -n $1 && $WORDCHARS == *"$1"* ]]
}

# ---------------------------------------------------------------------------
# Kill ring helpers
# ---------------------------------------------------------------------------

# _zsh_wordnav_kill_add <text> <mode>
#   mode = "append"  : text was killed forward  -> append to CUTBUFFER
#   mode = "prepend" : text was killed backward -> prepend to CUTBUFFER
# Consecutive kills (any of our kill widgets invoked back-to-back, with no
# intervening non-kill widget, AND the previous kill actually deleted text)
# accumulate into a single CUTBUFFER so Ctrl+Y yanks the combined region.
#
# Accumulation test is two-fold:
#   1. $LASTWIDGET must be one of our kill widgets (rules out motion widgets
#      and other commands run between the two kills), AND
#   2. $_ZSH_WORDNAV_LAST_KILL_REAL must be 1 (rules out the case where the
#      previous kill was a no-op — e.g. Ctrl+W at the start of the line —
#      which ZLE still records in $LASTWIDGET but deleted nothing).
_zsh_wordnav_kill_add() {
    emulate -L zsh
    local text=$1 mode=$2
    local consecutive=0
    case $LASTWIDGET in
        kill-word|backward-kill-word|vi-backward-kill-word|unix-word-rubout)
            (( _ZSH_WORDNAV_LAST_KILL_REAL )) && consecutive=1
            ;;
    esac
    if (( consecutive )); then
        # Accumulate into the current CUTBUFFER, preserving buffer order.
        if [[ $mode == append ]]; then
            CUTBUFFER+=$text
        else
            CUTBUFFER=$text$CUTBUFFER
        fi
    else
        # Fresh kill: rotate the previous CUTBUFFER onto the kill ring.
        if [[ -n $CUTBUFFER ]]; then
            killring=("$CUTBUFFER" "${killring[@]}")
            (( ${#killring[@]} > _ZSH_WORDNAV_KILLRING_MAX )) \
                && killring=("${killring[@]:0:_ZSH_WORDNAV_KILLRING_MAX}")
        fi
        CUTBUFFER=$text
    fi
    _ZSH_WORDNAV_LAST_KILL_REAL=1
}

# ---------------------------------------------------------------------------
# Motion widgets (no deletion)
# ---------------------------------------------------------------------------

# Ctrl+Right — forward-word.
# If the char under the cursor is a word char, skip the whole run of word
# chars. Otherwise skip the whole run of non-word chars.
_zsh_wordnav_forward_word() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    local len=${#buf}
    (( cur >= len )) && return
    if _zsh_wordnav_is_word_char "${buf:$cur:1}"; then
        while (( cur < len )) && _zsh_wordnav_is_word_char "${buf:$cur:1}"; do
            (( cur++ ))
        done
    else
        while (( cur < len )) && ! _zsh_wordnav_is_word_char "${buf:$cur:1}"; do
            (( cur++ ))
        done
    fi
    CURSOR=$cur
}

# Ctrl+Left — backward-word.
# Mirror of forward-word: skip one run of word or non-word chars backward.
_zsh_wordnav_backward_word() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    (( cur == 0 )) && return
    if _zsh_wordnav_is_word_char "${buf:$((cur-1)):1}"; then
        while (( cur > 0 )) && _zsh_wordnav_is_word_char "${buf:$((cur-1)):1}"; do
            (( cur-- ))
        done
    else
        while (( cur > 0 )) && ! _zsh_wordnav_is_word_char "${buf:$((cur-1)):1}"; do
            (( cur-- ))
        done
    fi
    CURSOR=$cur
}

# ---------------------------------------------------------------------------
# Kill widgets (deletion + kill ring)
# ---------------------------------------------------------------------------

# Ctrl+Delete — kill-word. Delete one contiguous run forward.
_zsh_wordnav_kill_word() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    local len=${#buf}
    if (( cur >= len )); then
        _ZSH_WORDNAV_LAST_KILL_REAL=0   # no-op: no text deleted
        return
    fi
    local start=$cur end=$cur
    if _zsh_wordnav_is_word_char "${buf:$cur:1}"; then
        while (( end < len )) && _zsh_wordnav_is_word_char "${buf:$end:1}"; do
            (( end++ ))
        done
    else
        while (( end < len )) && ! _zsh_wordnav_is_word_char "${buf:$end:1}"; do
            (( end++ ))
        done
    fi
    local deleted=${buf:$start:$((end-start))}
    _zsh_wordnav_kill_add "$deleted" append
    BUFFER=${buf:0:$start}${buf:$end}
    CURSOR=$start
}

# Ctrl+Backspace — backward-kill-word. Delete one contiguous run backward.
_zsh_wordnav_backward_kill_word() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    if (( cur == 0 )); then
        _ZSH_WORDNAV_LAST_KILL_REAL=0   # no-op: no text deleted
        return
    fi
    local end=$cur start=$cur
    if _zsh_wordnav_is_word_char "${buf:$((cur-1)):1}"; then
        while (( start > 0 )) && _zsh_wordnav_is_word_char "${buf:$((start-1)):1}"; do
            (( start-- ))
        done
    else
        while (( start > 0 )) && ! _zsh_wordnav_is_word_char "${buf:$((start-1)):1}"; do
            (( start-- ))
        done
    fi
    local deleted=${buf:$start:$((end-start))}
    _zsh_wordnav_kill_add "$deleted" prepend
    BUFFER=${buf:0:$start}${buf:$end}
    CURSOR=$start
}

# Ctrl+W — unix-word-rubout. Whitespace-delimited backward kill.
#
# Behavior:
#   - If the char before the cursor is whitespace: delete only that contiguous
#     whitespace run. (e.g. "foo  |" -> "foo|")
#   - If it is non-whitespace: delete the contiguous non-whitespace run, and
#     then also delete the contiguous whitespace run preceding it.
#     (e.g. "foo  bar|" -> "foo|")
#
# This is bash's unix-word-rubout made smarter: bash leaves trailing
# whitespace behind, this plugin eats it too.
_zsh_wordnav_unix_word_rubout() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    if (( cur == 0 )); then
        _ZSH_WORDNAV_LAST_KILL_REAL=0   # no-op: no text deleted
        return
    fi
    local end=$cur start=$cur
    if [[ ${buf:$((cur-1)):1} == [[:space:]] ]]; then
        # Cursor follows whitespace: delete only the whitespace run.
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} == [[:space:]] ]]; do
            (( start-- ))
        done
    else
        # First: the non-whitespace run.
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} != [[:space:]] ]]; do
            (( start-- ))
        done
        # Then: the whitespace run preceding it.
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} == [[:space:]] ]]; do
            (( start-- ))
        done
    fi
    local deleted=${buf:$start:$((end-start))}
    _zsh_wordnav_kill_add "$deleted" prepend
    BUFFER=${buf:0:$start}${buf:$end}
    CURSOR=$start
}

# ---------------------------------------------------------------------------
# Widget registration & key bindings
# ---------------------------------------------------------------------------

# Register only when ZLE is actually active (i.e. interactive shells). This
# makes the plugin safe to source from non-interactive scripts and tests.
if [[ -o zle ]]; then
    # Replace the standard widgets so all existing key bindings (including
    # terminal-specific Ctrl+Arrow sequences resolved via terminfo) pick up
    # the new behavior automatically.
    zle -N backward-word          _zsh_wordnav_backward_word
    zle -N forward-word           _zsh_wordnav_forward_word
    zle -N kill-word              _zsh_wordnav_kill_word
    zle -N backward-kill-word     _zsh_wordnav_backward_kill_word
    zle -N vi-backward-kill-word  _zsh_wordnav_backward_kill_word
    zle -N unix-word-rubout       _zsh_wordnav_unix_word_rubout
    # NOTE: zsh has no vi-unix-word-rubout widget; Ctrl+W in vi insert mode
    # maps to unix-word-rubout directly.

    # Explicit key bindings for common terminal sequences. These complement
    # the widget replacements above; terminals emitting a different sequence
    # still work as long as it was originally bound to one of our widgets.
    bindkey '^[[1;5D' backward-word         # Ctrl+Left  (xterm / gnome-terminal)
    bindkey '^[[1;5C' forward-word          # Ctrl+Right (xterm / gnome-terminal)
    bindkey '^[[3;5~' kill-word             # Ctrl+Delete
    bindkey '^H'      backward-kill-word    # Ctrl+Backspace (common)
    bindkey '^W'      unix-word-rubout      # Ctrl+W

    # Alternative sequences emitted by some terminals (rxvt, app cursor mode).
    bindkey '^[Od' backward-word
    bindkey '^[Oc' forward-word
fi

# vim: set ft=zsh ts=4 sw=4 et:
