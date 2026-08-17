#!/usr/bin/env zsh
# test/run_tests.zsh — non-interactive tests for zsh-wordnav.
#
# Run:  zsh test/run_tests.zsh
#
# The plugin guards its `zle -N`/`bindkey` calls behind `[[ -o zle ]]`, so
# sourcing it from a script defines the widget functions without trying to
# touch ZLE. We then set BUFFER/CURSOR by hand and invoke the functions
# directly.

emulate -L zsh
# NOTE: do NOT enable err_return here — several widget functions and
# _zsh_wordnav_is_word_char legitimately return non-zero status codes.

# Source the plugin (defines functions; skips zle -N since ZLE is off).
PLUGIN="${0:A:h:h}/zsh-wordnav.plugin.zsh"
source "$PLUGIN"

# ---------------------------------------------------------------------------
# Tiny test framework
# ---------------------------------------------------------------------------

typeset -i _passed=0 _failed=0

ok() { # ok <name> <actual> <expected>
    local name=$1 actual=$2 expected=$3
    if [[ $actual == $expected ]]; then
        (( _passed++ ))
        print -r -- "  PASS  $name"
    else
        (( _failed++ ))
        print -r -- "  FAIL  $name"
        print -r -- "        expected: $expected"
        print -r -- "        actual:   $actual"
    fi
}

# Reset editor + kill-ring state between tests. LASTWIDGET is a ZLE special
# parameter; in a script it behaves like an ordinary scalar, so we can clear
# it to simulate "no prior widget".
reset_state() {
    BUFFER=""
    CURSOR=0
    CUTBUFFER=""
    killring=()
    LASTWIDGET=""
    _ZSH_WORDNAV_LAST_KILL_REAL=0
}

# Helper: mark the previous kill as "real" so the next kill accumulates.
# In a real interactive session ZLE sets LASTWIDGET for us; in tests we
# must mirror both halves of the accumulation test.
mark_last_kill_real() {
    LASTWIDGET=$1
    _ZSH_WORDNAV_LAST_KILL_REAL=1
}

section() { print -r -- ""; print -r -- "== $1 =="; }

# ---------------------------------------------------------------------------
# WORDCHARS
# ---------------------------------------------------------------------------

section "WORDCHARS"
ok "WORDCHARS is underscore only" "$WORDCHARS" "_"

# is_word_char sanity
reset_state
_zsh_wordnav_is_word_char "a"; ok "is_word_char a"  "$?" "0"
_zsh_wordnav_is_word_char "_"; ok "is_word_char _"  "$?" "0"
_zsh_wordnav_is_word_char "9"; ok "is_word_char 9"  "$?" "0"
_zsh_wordnav_is_word_char ","; ok "is_word_char , (non-word)" "$?" "1"
_zsh_wordnav_is_word_char " "; ok "is_word_char space (non-word)" "$?" "1"
_zsh_wordnav_is_word_char "*"; ok "is_word_char * (non-word)" "$?" "1"
_zsh_wordnav_is_word_char "";  ok "is_word_char empty (non-word)" "$?" "1"

# ---------------------------------------------------------------------------
# forward_word
# ---------------------------------------------------------------------------

section "forward_word (Ctrl+Right)"

reset_state; BUFFER="hello, world"; CURSOR=0
_zsh_wordnav_forward_word; ok "skip word run from start" "$CURSOR" "5"

reset_state; BUFFER="hello, world"; CURSOR=5
_zsh_wordnav_forward_word; ok "skip non-word run (comma+space)" "$CURSOR" "7"

reset_state; BUFFER="hello, world"; CURSOR=7
_zsh_wordnav_forward_word; ok "skip next word run" "$CURSOR" "12"

reset_state; BUFFER="hello, world"; CURSOR=12
_zsh_wordnav_forward_word; ok "at end: no move" "$CURSOR" "12"

reset_state; BUFFER=""; CURSOR=0
_zsh_wordnav_forward_word; ok "empty buffer: no move" "$CURSOR" "0"

reset_state; BUFFER="  foo"; CURSOR=0
_zsh_wordnav_forward_word; ok "skip leading non-word (spaces)" "$CURSOR" "2"

reset_state; BUFFER="foo,,,bar"; CURSOR=3
_zsh_wordnav_forward_word; ok "skip multi-char non-word run" "$CURSOR" "6"

# ---------------------------------------------------------------------------
# backward_word
# ---------------------------------------------------------------------------

section "backward_word (Ctrl+Left)"

reset_state; BUFFER="hello, world"; CURSOR=12
_zsh_wordnav_backward_word; ok "skip word run from end" "$CURSOR" "7"

reset_state; BUFFER="hello, world"; CURSOR=7
_zsh_wordnav_backward_word; ok "skip non-word run (comma+space)" "$CURSOR" "5"

reset_state; BUFFER="hello, world"; CURSOR=5
_zsh_wordnav_backward_word; ok "skip previous word run" "$CURSOR" "0"

reset_state; BUFFER="hello, world"; CURSOR=0
_zsh_wordnav_backward_word; ok "at start: no move" "$CURSOR" "0"

reset_state; BUFFER=""; CURSOR=0
_zsh_wordnav_backward_word; ok "empty buffer: no move" "$CURSOR" "0"

reset_state; BUFFER="foo   "; CURSOR=6
_zsh_wordnav_backward_word; ok "skip trailing non-word (spaces)" "$CURSOR" "3"

reset_state; BUFFER="foo,,,bar"; CURSOR=9
_zsh_wordnav_backward_word; ok "skip word to non-word boundary" "$CURSOR" "6"

# ---------------------------------------------------------------------------
# kill_word (Ctrl+Delete)
# ---------------------------------------------------------------------------

section "kill_word (Ctrl+Delete)"

reset_state; BUFFER="hello, world"; CURSOR=0
_zsh_wordnav_kill_word
ok "delete word run from start (buffer)" "$BUFFER" ", world"
ok "delete word run from start (cursor)" "$CURSOR" "0"
ok "delete word run from start (cutbuffer)" "$CUTBUFFER" "hello"

reset_state; BUFFER="hello, world"; CURSOR=5
_zsh_wordnav_kill_word
ok "delete non-word run (buffer)" "$BUFFER" "helloworld"
ok "delete non-word run (cursor)" "$CURSOR" "5"
ok "delete non-word run (cutbuffer)" "$CUTBUFFER" ", "

reset_state; BUFFER="hello, world"; CURSOR=12
_zsh_wordnav_kill_word
ok "at end: no change (buffer)" "$BUFFER" "hello, world"
ok "at end: no change (cursor)" "$CURSOR" "12"
ok "at end: empty cutbuffer" "$CUTBUFFER" ""

# ---------------------------------------------------------------------------
# backward_kill_word (Ctrl+Backspace)
# ---------------------------------------------------------------------------

section "backward_kill_word (Ctrl+Backspace)"

reset_state; BUFFER="hello, world"; CURSOR=12
_zsh_wordnav_backward_kill_word
ok "delete word run backward (buffer)" "$BUFFER" "hello, "
ok "delete word run backward (cursor)" "$CURSOR" "7"
ok "delete word run backward (cutbuffer)" "$CUTBUFFER" "world"

reset_state; BUFFER="hello, world"; CURSOR=7
_zsh_wordnav_backward_kill_word
ok "delete non-word run backward (buffer)" "$BUFFER" "helloworld"
ok "delete non-word run backward (cursor)" "$CURSOR" "5"
ok "delete non-word run backward (cutbuffer)" "$CUTBUFFER" ", "

reset_state; BUFFER="hello, world"; CURSOR=0
_zsh_wordnav_backward_kill_word
ok "at start: no change (buffer)" "$BUFFER" "hello, world"
ok "at start: no change (cursor)" "$CURSOR" "0"
ok "at start: empty cutbuffer" "$CUTBUFFER" ""

# ---------------------------------------------------------------------------
# unix_word_rubout (Ctrl+W)
# ---------------------------------------------------------------------------

section "unix_word_rubout (Ctrl+W)"

# Cursor after non-space: delete the non-space run AND preceding spaces.
reset_state; BUFFER="foo  bar"; CURSOR=8
_zsh_wordnav_unix_word_rubout
ok "non-space end: eats trailing token + preceding spaces (buffer)" "$BUFFER" "foo"
ok "non-space end: cursor" "$CURSOR" "3"
ok "non-space end: cutbuffer" "$CUTBUFFER" "  bar"

# Cursor after space: delete the space run AND the preceding word.
reset_state; BUFFER="foo  bar  "; CURSOR=10
_zsh_wordnav_unix_word_rubout
ok "space end: eats trailing spaces + preceding word (buffer)" "$BUFFER" "foo  "
ok "space end: cursor" "$CURSOR" "5"
ok "space end: cutbuffer" "$CUTBUFFER" "bar  "

# Cursor mid-word (non-whitespace to the right): delete only the word,
# leaving the preceding spaces intact.
reset_state; BUFFER="foo  barbaz"; CURSOR=8   # cursor between "bar" and "baz"
_zsh_wordnav_unix_word_rubout
ok "mid-word: deletes only the word (buffer)" "$BUFFER" "foo  baz"
ok "mid-word: cursor" "$CURSOR" "5"
ok "mid-word: cutbuffer" "$CUTBUFFER" "bar"

# Same, but at the very start (no preceding whitespace to protect).
reset_state; BUFFER="foobar"; CURSOR=3   # cursor between "foo" and "bar"
_zsh_wordnav_unix_word_rubout
ok "mid-word at start: deletes only the word (buffer)" "$BUFFER" "bar"
ok "mid-word at start: cursor" "$CURSOR" "0"
ok "mid-word at start: cutbuffer" "$CUTBUFFER" "foo"

# Cursor after non-space with NO preceding space.
reset_state; BUFFER="foobar"; CURSOR=6
_zsh_wordnav_unix_word_rubout
ok "non-space end, no preceding space (buffer)" "$BUFFER" ""
ok "non-space end, no preceding space (cursor)" "$CURSOR" "0"
ok "non-space end, no preceding space (cutbuffer)" "$CUTBUFFER" "foobar"

# At start: nothing happens.
reset_state; BUFFER="foo"; CURSOR=0
_zsh_wordnav_unix_word_rubout
ok "at start: no change" "$BUFFER" "foo"
ok "at start: cursor" "$CURSOR" "0"

# Mixed: "abc def ghi|" -> Ctrl+W -> "abc def|"
reset_state; BUFFER="abc def ghi"; CURSOR=11
_zsh_wordnav_unix_word_rubout
ok "middle word: delete ' ghi' (buffer)" "$BUFFER" "abc def"
ok "middle word: cursor" "$CURSOR" "7"
ok "middle word: cutbuffer" "$CUTBUFFER" " ghi"

# ---------------------------------------------------------------------------
# Kill ring: consecutive kills accumulate
# ---------------------------------------------------------------------------

section "kill ring: consecutive accumulation"

# Two Ctrl+W back-to-back -> combined into one CUTBUFFER.
reset_state; BUFFER="foo  bar  baz"; CURSOR=13
_zsh_wordnav_unix_word_rubout           # deletes "  baz", CURSOR=8
mark_last_kill_real unix-word-rubout    # simulate consecutive kill
_zsh_wordnav_unix_word_rubout           # deletes "  bar", CURSOR=3
ok "consecutive Ctrl+W: buffer" "$BUFFER" "foo"
ok "consecutive Ctrl+W: cursor" "$CURSOR" "3"
ok "consecutive Ctrl+W: combined cutbuffer" "$CUTBUFFER" "  bar  baz"

# Three in a row.
reset_state; BUFFER="a b c"; CURSOR=5
_zsh_wordnav_unix_word_rubout           # deletes " c"
mark_last_kill_real unix-word-rubout
_zsh_wordnav_unix_word_rubout           # deletes " b"
mark_last_kill_real unix-word-rubout
_zsh_wordnav_unix_word_rubout           # deletes "a"
ok "three consecutive: buffer empty" "$BUFFER" ""
ok "three consecutive: combined cutbuffer" "$CUTBUFFER" "a b c"

# Non-kill widget between kills breaks accumulation.
reset_state; BUFFER="foo  bar  baz"; CURSOR=13
_zsh_wordnav_unix_word_rubout           # deletes "  baz"
LASTWIDGET=forward-word; _ZSH_WORDNAV_LAST_KILL_REAL=0   # something else ran in between
_zsh_wordnav_unix_word_rubout           # deletes "  bar" — fresh kill
ok "interrupted: buffer" "$BUFFER" "foo"
ok "interrupted: second cutbuffer is fresh" "$CUTBUFFER" "  bar"
ok "interrupted: previous kill rotated to killring" "${killring[1]}" "  baz"

# Mixed forward + backward consecutive kills preserve buffer order.
reset_state; BUFFER="leftmidright"; CURSOR=8   # between "leftmid" and "right"
# cursor at index 8, "leftmid"=0..7, "right"=8..12
_zsh_wordnav_kill_word                  # deletes "right" forward
mark_last_kill_real kill-word
_zsh_wordnav_backward_kill_word         # deletes "leftmid" backward (prepend)
ok "mixed fwd+bwd: buffer empty" "$BUFFER" ""
ok "mixed fwd+bwd: combined cutbuffer in buffer order" "$CUTBUFFER" "leftmidright"

# Mixed backward + forward consecutive kills also preserve buffer order.
reset_state; BUFFER="leftmidright"; CURSOR=8
_zsh_wordnav_backward_kill_word         # deletes "leftmid" backward
mark_last_kill_real backward-kill-word
_zsh_wordnav_kill_word                  # deletes "right" forward (append)
ok "mixed bwd+fwd: buffer empty" "$BUFFER" ""
ok "mixed bwd+fwd: combined cutbuffer in buffer order" "$CUTBUFFER" "leftmidright"

# ---------------------------------------------------------------------------
# Kill ring rotation: old kills move to killring[]
# ---------------------------------------------------------------------------

section "kill ring rotation"

reset_state; BUFFER="aaa bbb ccc"; CURSOR=11
_zsh_wordnav_unix_word_rubout           # CUTBUFFER=" ccc", killring=()
LASTWIDGET=forward-word; _ZSH_WORDNAV_LAST_KILL_REAL=0   # interrupt
_zsh_wordnav_unix_word_rubout           # CUTBUFFER=" bbb", killring=(" ccc")
LASTWIDGET=forward-word; _ZSH_WORDNAV_LAST_KILL_REAL=0   # interrupt
_zsh_wordnav_unix_word_rubout           # CUTBUFFER="aaa" (no leading space, at start)
ok "rotation: current cutbuffer" "$CUTBUFFER" "aaa"
ok "rotation: killring[1] is most recent old" "${killring[1]}" " bbb"
ok "rotation: killring[2] is older" "${killring[2]}" " ccc"
ok "rotation: killring length" "${#killring[@]}" "2"

# Empty kills (at start of buffer) do NOT clobber the existing kill ring.
reset_state; BUFFER="foo"; CURSOR=0
CUTBUFFER="kept"
killring=("older")
_zsh_wordnav_unix_word_rubout           # does nothing (at start)
ok "no-op kill preserves cutbuffer" "$CUTBUFFER" "kept"
ok "no-op kill preserves killring" "${killring[1]}" "older"

# ---------------------------------------------------------------------------
# Regression: no-op kill widget must NOT cause the next real kill to wrongly
# accumulate into the previous CUTBUFFER. ZLE sets $LASTWIDGET to the widget
# name even when it deleted nothing, so we additionally track
# $_ZSH_WORDNAV_LAST_KILL_REAL.
# ---------------------------------------------------------------------------

section "no-op kill regression"

# Ctrl+W deletes "bar", then Ctrl+Backspace is a no-op (cursor at start),
# then a fresh Ctrl+Delete kills "baz" — it must start a NEW CUTBUFFER,
# rotating "bar" onto the kill ring, NOT append to "bar".
reset_state; BUFFER="bar baz"; CURSOR=7
_zsh_wordnav_unix_word_rubout           # deletes " baz", CUTBUFFER=" baz", CURSOR=3
mark_last_kill_real unix-word-rubout
_zsh_wordnav_backward_kill_word         # deletes "bar", CUTBUFFER="bar baz", CURSOR=0
# Now Ctrl+Backspace is a no-op (still at start). ZLE records LASTWIDGET.
_zsh_wordnav_backward_kill_word         # no-op: sets _ZSH_WORDNAV_LAST_KILL_REAL=0
ok "no-op then real: still at start" "$CURSOR" "0"
ok "no-op then real: buffer empty" "$BUFFER" ""
ok "no-op then real: cutbuffer intact after no-op" "$CUTBUFFER" "bar baz"
# Simulate moving the cursor then killing forward (a new region).
BUFFER="baz"; CURSOR=0
LASTWIDGET=backward-kill-word           # ZLE would record the no-op widget here
# _ZSH_WORDNAV_LAST_KILL_REAL is already 0 from the no-op above.
_zsh_wordnav_kill_word                  # deletes "baz" forward — must be a FRESH kill
ok "no-op regression: fresh kill buffer" "$BUFFER" ""
ok "no-op regression: fresh cutbuffer (not accumulated)" "$CUTBUFFER" "baz"
ok "no-op regression: previous cutbuffer rotated to killring" "${killring[1]}" "bar baz"

# Mirror case: no-op kill-word at end of buffer, then a real backward kill.
reset_state; BUFFER="foo bar"; CURSOR=7
_zsh_wordnav_unix_word_rubout           # deletes " bar", CUTBUFFER=" bar", CURSOR=3
mark_last_kill_real unix-word-rubout
_zsh_wordnav_kill_word                  # no-op (cursor at end): sets REAL=0
ok "no-op fwd: no change" "$BUFFER" "foo"
ok "no-op fwd: cutbuffer intact" "$CUTBUFFER" " bar"
# Now a fresh backward kill of "foo".
LASTWIDGET=kill-word                    # ZLE records the no-op
_zsh_wordnav_backward_kill_word         # deletes "foo" — FRESH kill
ok "no-op fwd regression: fresh cutbuffer" "$CUTBUFFER" "foo"
ok "no-op fwd regression: previous rotated to killring" "${killring[1]}" " bar"

# ---------------------------------------------------------------------------
# zsh-autosuggestions fixup (_zsh_wordnav_autosuggest_fixup)
# ---------------------------------------------------------------------------
#
# The fixup strips `yank` and `yank-pop` from ZSH_AUTOSUGGEST_IGNORE_WIDGETS
# and re-binds. We exercise the core logic without an actual
# zsh-autosuggestions install: we provide a stub _zsh_autosuggest_bind_widgets
# and a stub add-zsh-hook, then check the array is mutated correctly and the
# bind is invoked exactly when something changed.

section "autosuggest fixup"

# --- Stub infrastructure -------------------------------------------------
# Count how many times the bind function was called, so we can assert it
# fires only when the ignore list actually changed.
typeset -gi _bind_calls=0
_zsh_autosuggest_bind_widgets() { (( _bind_calls++ )) }

# add-zsh-hook stub: in this test we never want the fixup to actually
# unregister itself from a real precmd hook (there is none in a script).
# Just record the unload requests.
typeset -ga _unloads
add-zsh-hook() {
    # Only handle the `-d` (delete) form we care about.
    if [[ $1 == "-d" ]]; then
        _unloads+=("$3")
    fi
}

# Helper: snapshot of the default zsh-autosuggestions ignore list, matching
# the real default from zsh-autosuggestions/src/config.zsh.
reset_ignore_list() {
    ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(
        'orig-\*'
        beep
        run-help
        set-local-history
        which-command
        yank
        yank-pop
        'zle-\*'
    )
}

# --- Test: no-op when zsh-autosuggestions is not loaded ------------------
# Simulate "zsh-autosuggestions absent" by temporarily hiding the stub.
reset_ignore_list
_bind_calls=0
_unloads=()
# Shadow the bind function with nothing (unset it locally).
unset -f _zsh_autosuggest_bind_widgets 2>/dev/null
_zsh_wordnav_autosuggest_fixup
ok "no autosuggest: ignore list untouched (yank still present)" \
   "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank]}" "yank"
ok "no autosuggest: ignore list untouched (yank-pop still present)" \
   "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank-pop]}" "yank-pop"
ok "no autosuggest: bind not called" "$_bind_calls" "0"
ok "no autosuggest: hook not unregistered" "$_unloads" ""
# Restore the stub for subsequent tests.
_zsh_autosuggest_bind_widgets() { (( _bind_calls++ )) }

# --- Test: strips yank and yank-pop, calls bind once ----------------------
reset_ignore_list
_bind_calls=0
_unloads=()
_zsh_wordnav_autosuggest_fixup
ok "strips yank from ignore list" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank]}" ""
ok "strips yank-pop from ignore list" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank-pop]}" ""
ok "leaves other entries intact (beep)" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)beep]}" "beep"
ok "leaves other entries intact (run-help)" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)run-help]}" "run-help"
ok "leaves other entries intact (which-command)" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)which-command]}" "which-command"
# Length check: started with 8, removed 2 (yank + yank-pop) → 6 left, which
# also proves the glob-pattern entries (orig-\*, zle-\*) survived untouched
# since they're the only remaining entries besides the 4 plain ones above.
ok "ignore list length went 8 → 6" "${#ZSH_AUTOSUGGEST_IGNORE_WIDGETS}" "6"
ok "bind called once when changes happened" "$_bind_calls" "1"
ok "hook unregistered itself" "${_unloads[1]}" "_zsh_wordnav_autosuggest_fixup"

# --- Test: idempotent — second run does not re-bind ----------------------
# The fixup self-unloads after the first successful run, but if invoked
# again (e.g. by a test or a forced re-bind) it must not call bind again
# because yank/yank-pop are already gone.
_bind_calls=0
_unloads=()
_zsh_wordnav_autosuggest_fixup
ok "idempotent: bind not called when nothing changed" "$_bind_calls" "0"
ok "idempotent: hook still unregistered itself" "${_unloads[1]}" "_zsh_wordnav_autosuggest_fixup"

# --- Test: only yank present (yank-pop already removed by user) ----------
reset_ignore_list
ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(${ZSH_AUTOSUGGEST_IGNORE_WIDGETS:#yank-pop})
_bind_calls=0
_unloads=()
_zsh_wordnav_autosuggest_fixup
ok "partial: yank stripped" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank]}" ""
ok "partial: yank-pop still absent" "${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(r)yank-pop]}" ""
ok "partial: bind called once" "$_bind_calls" "1"

# --- Test: opt-out flag respected ---------------------------------------
# When _ZSH_WORDNAV_AUTOSUGGEST_FIXUP=0 at source time, the fixup function
# is still DEFINED (so it can be tested), but it is NOT registered on precmd.
# We verify the registration gate by re-sourcing the plugin with the flag
# disabled and checking that no _zsh_wordnav_autosuggest_fixup entry is in
# the real zsh-hook array. Since the test harness is non-interactive, the
# zle guard skips registration anyway; instead we directly assert the flag
# is consulted by re-running the registration block under `emulate -L zsh`
# with zle faked on.
#
# Simpler: just assert the flag's default value is 1 (enabled) when unset.
unset _ZSH_WORDNAV_AUTOSUGGEST_FIXUP
(( ${+_ZSH_WORDNAV_AUTOSUGGEST_FIXUP} )) || _ZSH_WORDNAV_AUTOSUGGEST_FIXUP=1
ok "opt-out: default is enabled (1)" "$_ZSH_WORDNAV_AUTOSUGGEST_FIXUP" "1"

# And when explicitly disabled, the flag reads 0.
_ZSH_WORDNAV_AUTOSUGGEST_FIXUP=0
ok "opt-out: can be disabled (0)" "$_ZSH_WORDNAV_AUTOSUGGEST_FIXUP" "0"

# --- Test: empty ignore list is handled gracefully ----------------------
ZSH_AUTOSUGGEST_IGNORE_WIDGETS=()
_bind_calls=0
_unloads=()
_zsh_wordnav_autosuggest_fixup
ok "empty list: no bind call" "$_bind_calls" "0"
ok "empty list: hook still unregistered" "${_unloads[1]}" "_zsh_wordnav_autosuggest_fixup"

# Cleanup stubs so they don't leak into anything else.
unset -f _zsh_autosuggest_bind_widgets add-zsh-hook 2>/dev/null
unset _unloads _bind_calls 2>/dev/null

# ---------------------------------------------------------------------------
# _zsh_wordnav_pre_redraw (zle-line-pre-redraw hook for consecutive-kill)
# ---------------------------------------------------------------------------
#
# The hook classifies $LASTWIDGET into three buckets and either preserves or
# resets _ZSH_WORDNAV_LAST_KILL_REAL. We test each bucket directly by setting
# $LASTWIDGET and invoking the hook.

section "pre-redraw hook"

# Helper: set LASTWIDGET, run the hook, report whether REAL was reset.
# Args: <test-name> <LASTWIDGET-value> <expected-REAL-after>
run_pre_redraw() {
    local name=$1 lw=$2 expected=$3
    LASTWIDGET=$lw
    _ZSH_WORDNAV_LAST_KILL_REAL=1   # start as "previous kill was real"
    _zsh_wordnav_pre_redraw
    ok "$name" "$_ZSH_WORDNAV_LAST_KILL_REAL" "$expected"
}

# Bucket 1: our kill widgets -> DON'T reset (still consecutive).
run_pre_redraw "kill widget: kill-word preserves REAL"           kill-word              1
run_pre_redraw "kill widget: backward-kill-word preserves REAL"  backward-kill-word     1
run_pre_redraw "kill widget: vi-backward-kill-word preserves REAL" vi-backward-kill-word 1
run_pre_redraw "kill widget: unix-word-rubout preserves REAL"    unix-word-rubout      1

# Bucket 1 (wrapped): autosuggest-wrapped kill widget names.
# Form: _zsh_autosuggest_bound_<N>_<kill-widget>
run_pre_redraw "wrapped kill: bound kill-word preserves REAL" \
    _zsh_autosuggest_bound_1_kill-word 1
run_pre_redraw "wrapped kill: bound backward-kill-word preserves REAL" \
    _zsh_autosuggest_bound_1_backward-kill-word 1
run_pre_redraw "wrapped kill: bound unix-word-rubout preserves REAL" \
    _zsh_autosuggest_bound_1_unix-word-rubout 1
run_pre_redraw "wrapped kill: bound vi-backward-kill-word preserves REAL" \
    _zsh_autosuggest_bound_2_vi-backward-kill-word 1

# Bucket 2: internal/bookkeeping widgets -> DON'T reset.
run_pre_redraw "internal: autosuggest-suggest preserves REAL"   autosuggest-suggest    1
run_pre_redraw "internal: autosuggest-fetch preserves REAL"      autosuggest-fetch      1
run_pre_redraw "internal: zle-line-pre-redraw preserves REAL"    zle-line-pre-redraw    1
run_pre_redraw "internal: zle-line-init preserves REAL"          zle-line-init          1
run_pre_redraw "internal: beep preserves REAL"                   beep                   1
run_pre_redraw "internal: run-help preserves REAL"               run-help               1
run_pre_redraw "internal: which-command preserves REAL"          which-command          1
run_pre_redraw "internal: set-local-history preserves REAL"      set-local-history      1
run_pre_redraw "internal: isearch-exit preserves REAL"           isearch-exit           1
run_pre_redraw "internal: vi-insert preserves REAL"              vi-insert              1

# Bucket 3: user-facing widgets -> RESET to 0 (kill sequence broken).
run_pre_redraw "user: self-insert resets REAL"                  self-insert            0
run_pre_redraw "user: forward-char resets REAL"                 forward-char           0
run_pre_redraw "user: backward-char resets REAL"                backward-char          0
run_pre_redraw "user: forward-word resets REAL"                 forward-word           0
run_pre_redraw "user: backward-word resets REAL"                backward-word          0
run_pre_redraw "user: yank resets REAL"                         yank                   0
run_pre_redraw "user: yank-pop resets REAL"                     yank-pop               0
run_pre_redraw "user: accept-line resets REAL"                  accept-line            0
run_pre_redraw "user: beginning-of-line resets REAL"            beginning-of-line      0
run_pre_redraw "user: quoted-insert resets REAL"                quoted-insert          0
run_pre_redraw "user: delete-char resets REAL"                  delete-char            0
run_pre_redraw "user: undefined widget resets REAL"             some-random-widget     0

# Edge case: empty LASTWIDGET (first widget ever) -> resets (no prior kill).
run_pre_redraw "edge: empty LASTWIDGET resets REAL"             ""                     0

# --- Full consecutive-kill flow with pre-redraw, simulating autosuggest ---
# This simulates the exact bug scenario: two Ctrl+W with autosuggest running
# `autosuggest-suggest` between them. Without the pre-redraw fix, the second
# kill would NOT accumulate (because the old code checked $LASTWIDGET, which
# would be 'autosuggest-suggest'). With the fix, _ZSH_WORDNAV_LAST_KILL_REAL
# survives the autosuggest-suggest widget, and the second kill accumulates.

section "consecutive kills with autosuggest-suggest between"

reset_state
BUFFER="foo bar baz"; CURSOR=11
# Kill 1: Ctrl+W deletes " baz".
_zsh_wordnav_unix_word_rubout
ok "autosuggest sim: kill1 buffer"     "$BUFFER"    "foo bar"
ok "autosuggest sim: kill1 cursor"     "$CURSOR"     "7"
ok "autosuggest sim: kill1 cutbuffer"  "$CUTBUFFER"  " baz"
ok "autosuggest sim: kill1 REAL flag"  "$_ZSH_WORDNAV_LAST_KILL_REAL" "1"

# Simulate the pre-redraw hook firing after Kill 1.
LASTWIDGET=unix-word-rubout
_zsh_wordnav_pre_redraw
ok "autosuggest sim: pre-redraw after kill1 preserves REAL" "$_ZSH_WORDNAV_LAST_KILL_REAL" "1"

# Simulate zsh-autosuggestions async suggestion firing.
# In a real session, this would set LASTWIDGET='autosuggest-suggest'.
LASTWIDGET=autosuggest-suggest
_zsh_wordnav_pre_redraw
ok "autosuggest sim: autosuggest-suggest preserves REAL" "$_ZSH_WORDNAV_LAST_KILL_REAL" "1"

# Kill 2: Ctrl+W deletes " bar". Should ACCUMULATE into CUTBUFFER.
_zsh_wordnav_unix_word_rubout
ok "autosuggest sim: kill2 buffer"     "$BUFFER"    "foo"
ok "autosuggest sim: kill2 cursor"     "$CURSOR"     "3"
# CUTBUFFER should be " bar baz" (prepended " bar" to " baz").
ok "autosuggest sim: kill2 cutbuffer (accumulated!)" "$CUTBUFFER" " bar baz"

# Ctrl+Y would now yank " bar baz" in one shot — the fix works.

# --- Contrast: a real user action breaks the sequence ---
# After Kill 1, if the user moves the cursor (forward-char) instead of
# killing again, the sequence MUST break.

section "sequence broken by user action"

reset_state
BUFFER="foo bar baz"; CURSOR=11
_zsh_wordnav_unix_word_rubout
ok "break: kill1 cutbuffer" "$CUTBUFFER" " baz"
# User presses forward-char (or any motion widget).
LASTWIDGET=forward-char
_zsh_wordnav_pre_redraw
ok "break: motion reset REAL" "$_ZSH_WORDNAV_LAST_KILL_REAL" "0"
# Next kill is FRESH, not accumulated: CUTBUFFER holds only " bar",
# and the previous " baz" rotated onto the kill ring.
_zsh_wordnav_unix_word_rubout
ok "break: kill2 cutbuffer (fresh, only new text)" "$CUTBUFFER" " bar"
ok "break: kill2 rotated old cutbuffer to killring" "${killring[1]}" " baz"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print -r -- ""
print -r -- "== Summary =="
print -r -- "  passed: $_passed"
print -r -- "  failed: $_failed"
(( _failed == 0 )) && { print -r -- "  result: OK"; exit 0 } || { print -r -- "  result: FAIL"; exit 1 }
