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

# Cursor after space: delete only the space run.
reset_state; BUFFER="foo  bar  "; CURSOR=10
_zsh_wordnav_unix_word_rubout
ok "space end: eats only trailing spaces (buffer)" "$BUFFER" "foo  bar"
ok "space end: cursor" "$CURSOR" "8"
ok "space end: cutbuffer" "$CUTBUFFER" "  "

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
# Summary
# ---------------------------------------------------------------------------

print -r -- ""
print -r -- "== Summary =="
print -r -- "  passed: $_passed"
print -r -- "  failed: $_failed"
(( _failed == 0 )) && { print -r -- "  result: OK"; exit 0 } || { print -r -- "  result: FAIL"; exit 1 }
