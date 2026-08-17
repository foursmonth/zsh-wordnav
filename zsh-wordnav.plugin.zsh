# zsh-wordnav.plugin.zsh
# Smart word navigation and deletion for Zsh.
#
# Features:
#   - WORDCHARS restricted to '_' (underscore). Alphanumerics are always word
#     characters; punctuation is treated as a separator.
#   - Ctrl+Left / Ctrl+Right / Ctrl+Backspace / Ctrl+Delete skip or delete one
#     contiguous run of EITHER word characters OR non-word characters
#     (vi-style "strict" word motion).
#   - Ctrl+W deletes a whitespace-delimited token backward. When the cursor
#     follows whitespace it deletes the whitespace run plus the preceding
#     word; when it follows a word it deletes the word plus the preceding
#     whitespace run, unless the cursor is mid-word (non-whitespace to its
#     right), in which case only the word is deleted. (Smarter than bash's
#     unix-word-rubout.)
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

# Whether to fix zsh-autosuggestions's interaction with Ctrl+Y (yank).
#
# By default zsh-autosuggestions lists `yank` and `yank-pop` in
# ZSH_AUTOSUGGEST_IGNORE_WIDGETS, so after Ctrl+Y the previously shown
# suggestion is NOT refreshed. The result is a stale "ghost" suggestion
# that no longer matches the restored buffer — e.g. type `ls -a`, accept
# the `/etc` suggestion, Ctrl+W it away (suggestion re-fetches to `/etc`),
# then Ctrl+Y to yank it back: the buffer is `ls -a /etc` but the old
# `/etc` suggestion stays on screen, producing `ls -a /etc| /etc`.
#
# When this flag is set (the default), zsh-wordnav removes yank/yank-pop
# from the ignore list on the first precmd after zsh-autosuggestions has
# loaded, so yank becomes a "modify" widget and fetches a fresh suggestion
# matching the new buffer. Set to 0 to disable.
(( ${+_ZSH_WORDNAV_AUTOSUGGEST_FIXUP} )) || _ZSH_WORDNAV_AUTOSUGGEST_FIXUP=1

# Tracks whether the most recently invoked kill widget *actually deleted
# something*, so a no-op kill (e.g. Ctrl+W at the start of the line) does not
# make the *next* kill wrongly look "consecutive" and accumulate.
#
# Consecutive-kill detection uses ONLY this flag — NOT $LASTWIDGET. The
# previous implementation matched $LASTWIDGET against a fixed list of kill
# widget names, but that breaks under zsh-autosuggestions (async mode,
# default in zsh >= 5.0.8): between two user kills, zsh-autosuggestions runs
# its `autosuggest-suggest` widget via `zle autosuggest-suggest`, which
# overwrites $LASTWIDGET. The next Ctrl+W then sees $LASTWIDGET ==
# 'autosuggest-suggest', the match fails, and the kills don't accumulate —
# Ctrl+Y only yanks the most recent one.
#
# Instead of trusting $LASTWIDGET, we reset this flag to 0 from a
# `zle-line-pre-redraw` hook whenever a *user-facing* widget (anything that
# isn't one of our kills and isn't an internal/plugin bookkeeping widget)
# runs between two kills. See _zsh_wordnav_pre_redraw below.
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
# intervening user-facing widget, AND the previous kill actually deleted
# text) accumulate into a single CUTBUFFER so Ctrl+Y yanks the combined
# region.
#
# Consecutive detection uses ONLY $_ZSH_WORDNAV_LAST_KILL_REAL. The flag is
# set to 1 by every real kill below, and reset to 0 by _zsh_wordnav_pre_redraw
# (a zle-line-pre-redraw hook) whenever a user-facing widget runs between two
# kills. This is robust against zsh-autosuggestions wrapping/async behavior
# that corrupts $LASTWIDGET — see the doc on _ZSH_WORDNAV_LAST_KILL_REAL.
_zsh_wordnav_kill_add() {
    emulate -L zsh
    local text=$1 mode=$2
    if (( _ZSH_WORDNAV_LAST_KILL_REAL )); then
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
# Behavior (two branches, chosen by what sits just before the cursor):
#   - If the char before the cursor is whitespace: delete the contiguous
#     whitespace run AND then the contiguous non-whitespace run preceding it.
#     (consecutive whitespace + consecutive non-whitespace)
#     e.g. "foo  |bar" -> "|bar"  (eats the spaces AND "foo")
#   - If the char before the cursor is non-whitespace: delete the contiguous
#     non-whitespace run, then the contiguous whitespace run preceding it —
#     UNLESS the char to the right of the cursor (at the original cursor
#     position) is non-whitespace, in which case the whitespace is left
#     alone (deleting from the middle of a word must not merge the two words).
#     e.g. "foo  bar|"   -> "foo|"      (right side is EOL: eats spaces too)
#          "foo  bar|baz"-> "foo  baz"  (right side is non-space: keeps spaces)
_zsh_wordnav_unix_word_rubout() {
    emulate -L zsh
    local buf=$BUFFER cur=$CURSOR
    if (( cur == 0 )); then
        _ZSH_WORDNAV_LAST_KILL_REAL=0   # no-op: no text deleted
        return
    fi
    local end=$cur start=$cur
    if [[ ${buf:$((cur-1)):1} == [[:space:]] ]]; then
        # Cursor follows whitespace: eat the whitespace run, then the
        # non-whitespace run before it.
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} == [[:space:]] ]]; do
            (( start-- ))
        done
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} != [[:space:]] ]]; do
            (( start-- ))
        done
    else
        # Cursor follows non-whitespace: eat the non-whitespace run first.
        while (( start > 0 )) && [[ ${buf:$((start-1)):1} != [[:space:]] ]]; do
            (( start-- ))
        done
        # Then eat the whitespace run preceding it, unless the right side at
        # the original cursor position is non-whitespace (mid-word deletion).
        if (( cur >= ${#buf} )) || [[ ${buf:$cur:1} == [[:space:]] ]]; then
            while (( start > 0 )) && [[ ${buf:$((start-1)):1} == [[:space:]] ]]; do
                (( start-- ))
            done
        fi
    fi
    local deleted=${buf:$start:$((end-start))}
    _zsh_wordnav_kill_add "$deleted" prepend
    BUFFER=${buf:0:$start}${buf:$end}
    CURSOR=$start
}

# ---------------------------------------------------------------------------
# zsh-autosuggestions integration
# ---------------------------------------------------------------------------
#
# See the _ZSH_WORDNAV_AUTOSUGGEST_FIXUP doc above. We can't just edit
# ZSH_AUTOSUGGEST_IGNORE_WIDGETS at load time: zsh-autosuggestions sets
# its defaults lazily (the `(( ! ${+VAR} )) && ...` idiom) when its own
# plugin file is sourced, which may happen before OR after us. We also
# can't reorder load sequence from inside here.
#
# So we register a one-shot precmd hook. precmd hooks fire after all
# plugin files have been sourced, by which point (a) the
# _zsh_autosuggest_bind_widgets function exists if zsh-autosuggestions is
# installed, and (b) ZSH_AUTOSUGGEST_IGNORE_WIDGETS already holds its
# final value. We then strip yank/yank-pop from the ignore list and
# re-bind so yank becomes a "modify" widget (fetch a fresh suggestion
# based on the new buffer). The hook self-unloads once it has run.
#
# Load-order tolerant:
#   - If zsh-autosuggestions loads AFTER us, its add-zsh-hook runs after
#     ours on each precmd; on the first precmd our hook sees the bind
#     function already defined (functions are defined at source time),
#     fixes the list, and re-binds. zsh-autosuggestions's own precmd
#     hook then re-binds again (idempotent).
#   - If zsh-autosuggestions loads BEFORE us, our hook still runs after
#     their bind on the first precmd; we strip the ignore entries and
#     re-bind. From then on, zsh-autosuggestions's per-precmd re-bind
#     picks up the modified list.
#
# Defined unconditionally (so tests can exercise it), but only registered
# on precmd when ZLE is active.
_zsh_wordnav_autosuggest_fixup() {
    emulate -L zsh

    # Bail out silently if zsh-autosuggestions isn't loaded.
    (( ${+functions[_zsh_autosuggest_bind_widgets]} )) || return 0

    local changed=0 w
    for w in yank yank-pop; do
        # ${(r)…[(r)$w]} returns $w if it's present in the array,
        # empty otherwise — non-empty means it's still in the list.
        if [[ -n ${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)$w]} ]]; then
            # ${…:#$w} filters out every element equal to $w.
            ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(${ZSH_AUTOSUGGEST_IGNORE_WIDGETS:#$w})
            changed=1
        fi
    done

    if (( changed )); then
        # Re-bind so the new ignore list takes effect immediately.
        # zsh-autosuggestions also re-binds on every precmd by default,
        # but calling it here avoids a one-cycle lag where the stale
        # suggestion could reappear.
        _zsh_autosuggest_bind_widgets
    fi

    # Self-unload: the fixup only needs to run once.
    add-zsh-hook -d precmd _zsh_wordnav_autosuggest_fixup
}

# ---------------------------------------------------------------------------
# Consecutive-kill tracking (zle-line-pre-redraw hook)
# ---------------------------------------------------------------------------
#
# zle-line-pre-redraw fires after every widget finishes. We use it to detect
# "a non-kill widget ran between two kills" and reset
# _ZSH_WORDNAV_LAST_KILL_REAL so the next kill starts a fresh kill-ring
# entry instead of accumulating.
#
# Why we can't use $LASTWIDGET directly inside _zsh_wordnav_kill_add:
#   zsh-autosuggestions (async mode, default in zsh >= 5.0.8) runs its
#   `autosuggest-suggest` widget between two user kills via `zle`, which
#   overwrites $LASTWIDGET. By the time the second Ctrl+W runs,
#   $LASTWIDGET == 'autosuggest-suggest', and the old exact-match check
#   failed to recognize the kills as consecutive.
#
# The hook approach sidesteps this: during pre-redraw, $LASTWIDGET reflects
# the widget that JUST ran. We reset the flag UNLESS that widget is one that
# shouldn't break the kill sequence — i.e. our own kills, or plugin/zle
# internals that run between user actions (autosuggest-*, zle-*, etc.).
#
# Registered via `add-zle-hook-widget` (zsh >= 5.3) so we coexist with other
# plugins hooking the same event (e.g. zsh-syntax-highlighting) instead of
# overwriting them.
_zsh_wordnav_pre_redraw() {
    emulate -L zsh

    # Don't reset if the previous widget was one of our kills (including the
    # autosuggest-wrapped form `_zsh_autosuggest_bound_<N>_<kill>`), or an
    # internal/bookkeeping widget that doesn't represent a user action.
    case $LASTWIDGET in
        # Our kill widgets, plain or autosuggest-wrapped (wrapped form uses
        # '_' as separator: _zsh_autosuggest_bound_<N>_<kill-widget>).
        kill-word|backward-kill-word|vi-backward-kill-word|unix-word-rubout|\
        *_kill-word|*_backward-kill-word|*_vi-backward-kill-word|*_unix-word-rubout)
            return 0
            ;;
        # Plugin / zle internals that run between user keystrokes.
        autosuggest-*|zle-*|beep|run-help|which-command|set-local-history|\
        *line-pre-redraw|*line-init|*line-finish|isearch-*|vi-*)
            return 0
            ;;
    esac

    # Anything else (self-insert, forward-char, yank, motion, ...) is a real
    # user action that breaks the kill sequence.
    _ZSH_WORDNAV_LAST_KILL_REAL=0
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

    # Register the autosuggest fixup on precmd (interactive shells only).
    if (( _ZSH_WORDNAV_AUTOSUGGEST_FIXUP )); then
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _zsh_wordnav_autosuggest_fixup
    fi

    # Register the consecutive-kill tracker on zle-line-pre-redraw.
    # Use add-zle-hook-widget (zsh >= 5.3) so we COEXIST with other plugins
    # hooking the same event (e.g. zsh-syntax-highlighting) instead of
    # overwriting their hook. On older zsh, fall back to direct zle -N.
    if (( ${+functions[add-zle-hook-widget]} )) || {
        autoload -Uz add-zle-hook-widget && (( ${+functions[add-zle-hook-widget]} ))
    }; then
        add-zle-hook-widget zle-line-pre-redraw _zsh_wordnav_pre_redraw
    else
        zle -N zle-line-pre-redraw _zsh_wordnav_pre_redraw
    fi
fi

# vim: set ft=zsh ts=4 sw=4 et:
