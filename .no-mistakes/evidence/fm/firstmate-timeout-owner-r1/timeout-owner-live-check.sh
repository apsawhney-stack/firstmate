#!/usr/bin/env bash
set -u
ROOT="/Users/aps/.no-mistakes/worktrees/65bf6513b0ae/01M2YQ5JSJTH37YEFZBKX7D4PF"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-timeout-owner-live.XXXXXX") || exit 1
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

make_toolbin() {
  local tb="$TMP/toolbin" tool real
  mkdir -p "$tb"
  for tool in bash git grep sed head cut tail dirname perl mktemp sleep cat rm ps awk date mkdir chmod printf tr wc; do
    real=$(command -v "$tool" 2>/dev/null || true)
    [ -n "$real" ] && ln -s "$real" "$tb/$tool"
  done
  printf '%s\n' "$tb"
}

make_git_repo() {
  local wt=$1
  mkdir -p "$wt"
  git -C "$wt" init -q
  git -C "$wt" -c user.name=Tester -c user.email=tester@example.invalid commit -q --allow-empty -m init
  git -C "$wt" checkout -q -b fm/timeout-proof
}

toolbin=$(make_toolbin)
printf 'selected-timeout-mechanism-without-timeout-binary: '
PATH="$toolbin" bash -c '. "$0/bin/fm-timeout-lib.sh"; fm_timeout_mechanism' "$ROOT"

# Scenario 1: shared bounded no-mistakes library preserves command semantics.
case1="$TMP/case1"; mkdir -p "$case1/fakebin" "$case1/work dir"
cat > "$case1/fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf 'stdout: cwd=<%s> argc=<%s>' "$PWD" "$#"
for arg in "$@"; do printf ' arg=<%s>' "$arg"; done
printf '\n'
printf 'stderr: marker\n' >&2
printf 'call:%s\n' "${1:-}" >> "$FM_FAKE_NM_CALLS"
case "${1:-}" in
  fail) exit 37 ;;
  hangdesc)
    ( trap '' TERM; while :; do sleep 1; done ) &
    echo $! > "$FM_DESC_PID_FILE"
    wait
    ;;
esac
SH
chmod +x "$case1/fakebin/no-mistakes"
cat > "$case1/driver.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR=caller-owned
. "$1"
[ "$SCRIPT_DIR" = caller-owned ] || { echo "SCRIPT_DIR was clobbered"; exit 98; }
shift
case "${FM_ENTRY:-bounded}" in
  bounded) fm_nm_run_bounded "$@" ;;
  checked) fm_nm_run_checked "$@" ;;
  query) fm_nm_run "$@" ;;
esac
SH
chmod +x "$case1/driver.sh"

calls="$case1/calls"; descpid="$case1/desc.pid"; : > "$calls"
printf '\n-- bounded success preserves cwd argv stdout stderr --\n'
status=0
out=$(FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" \
  "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 2 ok "argument with spaces" 2>&1) || status=$?
printf 'exit=%s\n%s\n' "$status" "$out"
[ "$status" -eq 0 ] || exit 10
printf '%s\n' "$out" | grep -F "cwd=<" >/dev/null || exit 11
printf '%s\n' "$out" | grep -F "work dir>" >/dev/null || exit 11
printf '%s\n' "$out" | grep -F "argc=<2> arg=<ok> arg=<argument with spaces>" >/dev/null || exit 11
printf '%s\n' "$out" | grep -F "stderr: marker" >/dev/null || exit 11

printf '\n-- bounded failure preserves non-timeout exit status --\n'
status=0
FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" \
  "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 2 fail >/tmp/fm-timeout-owner-fail.$$ 2>&1 || status=$?
printf 'exit=%s\n' "$status"
[ "$status" -eq 37 ] || { cat /tmp/fm-timeout-owner-fail.$$; rm -f /tmp/fm-timeout-owner-fail.$$; exit 12; }
rm -f /tmp/fm-timeout-owner-fail.$$

printf '\n-- checked suppresses stderr while preserving stdout and status --\n'
status=0
out=$(FM_ENTRY=checked FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" \
  "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 2 fail 2>&1) || status=$?
printf 'exit=%s\n%s\n' "$status" "$out"
[ "$status" -eq 37 ] || exit 13
if printf '%s\n' "$out" | grep -F "stderr: marker" >/dev/null; then exit 14; fi
printf '%s\n' "$out" | grep -F "cwd=<" >/dev/null || exit 15
printf '%s\n' "$out" | grep -F "work dir>" >/dev/null || exit 15

printf '\n-- query wrapper is fail-open but keeps stdout and suppresses stderr --\n'
status=0
out=$(FM_ENTRY=query FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" \
  "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 2 fail 2>&1) || status=$?
printf 'exit=%s\n%s\n' "$status" "$out"
[ "$status" -eq 0 ] || exit 16
if printf '%s\n' "$out" | grep -F "stderr: marker" >/dev/null; then exit 17; fi

printf '\n-- invalid timeout does not invoke no-mistakes --\n'
: > "$calls"
status=0; FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 0 ok >/dev/null 2>&1 || status=$?
printf 'zero-timeout-exit=%s calls=%s\n' "$status" "$(wc -l < "$calls" | tr -d ' ')"
[ "$status" -eq 1 ] && [ ! -s "$calls" ] || exit 18

printf '\n-- timeout returns 124 and cleans descendant process --\n'
: > "$calls"; rm -f "$descpid"
status=0
FM_FAKE_NM_CALLS="$calls" FM_DESC_PID_FILE="$descpid" PATH="$case1/fakebin:$toolbin" \
  "$case1/driver.sh" "$ROOT/bin/fm-nm-run-lib.sh" "$case1/work dir" 1 hangdesc >/dev/null 2>&1 || status=$?
sleep 1
pid=$(cat "$descpid" 2>/dev/null || true)
alive=no
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=yes
printf 'timeout-exit=%s descendant-pid=%s descendant-alive-after-timeout=%s\n' "$status" "${pid:-missing}" "$alive"
[ "$status" -eq 124 ] && [ -n "$pid" ] && [ "$alive" = no ] || exit 19

# Scenario 2: fm-crew-state remains bounded with no ambient timeout binary and falls back to pane evidence.
case2="$TMP/case2"; mkdir -p "$case2/fakebin" "$case2/state"
make_git_repo "$case2/wt"
cat > "$case2/state/timeout.meta" <<EOF
window=fm:fm-timeout
worktree=$case2/wt
kind=ship
harness=claude
EOF
cat > "$case2/fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf 'nm-call:%s\n' "${1:-}" >> "$FM_FAKE_NM_CALLS"
while :; do sleep 1; done
SH
cat > "$case2/fakebin/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'work in progress\nesc to interrupt\n' ;;
esac
exit 0
SH
chmod +x "$case2/fakebin/no-mistakes" "$case2/fakebin/tmux"
printf '\n-- fm-crew-state bounded no-mistakes read falls back to pane --\n'
: > "$case2/calls"
start=$(date +%s)
out=$(FM_CREW_STATE_NM_TIMEOUT=1 FM_STATE_OVERRIDE="$case2/state" FM_FAKE_NM_CALLS="$case2/calls" PATH="$case2/fakebin:$toolbin" \
  "$ROOT/bin/fm-crew-state.sh" timeout)
status=$?
elapsed=$(( $(date +%s) - start ))
printf 'exit=%s elapsed=%ss calls=%s\n%s\n' "$status" "$elapsed" "$(wc -l < "$case2/calls" | tr -d ' ')" "$out"
[ "$status" -eq 0 ] || exit 20
printf '%s\n' "$out" | grep -F "source: pane" >/dev/null || exit 21
[ "$elapsed" -lt 5 ] || exit 22
[ "$(wc -l < "$case2/calls" | tr -d ' ')" -eq 1 ] || exit 23

printf '\nALL LIVE TIMEOUT OWNER CHECKS PASSED\n'
