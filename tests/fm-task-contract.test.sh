#!/usr/bin/env bash
# Behavior tests for the opt-in task-contract binding
# (bin/fm-task-contract.sh, bin/fm-task-contract-lib.sh).
#
# The existing Markdown task instructions stay the single source of truth; the
# binding only identifies them. These tests drive the public CLI (`check` and
# `adopt`) and the real launch/relaunch seam through public interfaces, never
# implementation-source bytes.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TC="$ROOT/bin/fm-task-contract.sh"
TMP_ROOT=$(fm_test_tmproot fm-task-contract)

make_home() {  # <name>
  local home="$TMP_ROOT/$1/home"
  mkdir -p "$home/data" "$home/state" "$home/config"
  printf '%s\n' "$home"
}

# A ship brief carries the ship-only "Delivery contract: mode=" line that the
# adoption command uses to confirm the task is a ship before a record exists.
write_ship_brief() {  # <home> <id> [<intent>] [<spec>]
  local home=$1 id=$2 intent=${3:-Do the requested work.} spec=${4:-Implement the requested behavior.}
  mkdir -p "$home/data/$id"
  {
    printf 'You are a crewmate.\n\n# Task\n## Captain'\''s intent\n%s\n\n## Firstmate spec\n%s\n\n' "$intent" "$spec"
    printf '# Definition of done\nDelivery contract: mode=no-mistakes\n'
  } >"$home/data/$id/brief.md"
}

run_tc() {  # <home> <args...>
  local home=$1
  shift
  FM_HOME="$home" FM_DATA_OVERRIDE="$home/data" FM_STATE_OVERRIDE="$home/state" "$TC" "$@" 2>&1
}

run_check() {  # <home> <id>
  run_tc "$1" check "$2"
}

adopt_task() {  # <home> <id> <disposition> <inv> <coup> <amb> <blast> <reversibility> <evidence>
  local home=$1 id=$2
  run_tc "$home" adopt "$id" \
    --disposition "$3" --invariant-complexity "$4" --cross-object-coupling "$5" \
    --ambiguity "$6" --blast-radius "$7" --reversibility "$8" --evidence-burden "$9"
}

adopt_default() {  # <home> <id>
  adopt_task "$1" "$2" coupled elevated elevated low elevated low elevated
}

binding_file() {  # <home> <id>
  printf '%s/data/%s/binding\n' "$1" "$2"
}

test_adoption_records_identity_and_never_rewrites_the_brief() {
  local home brief out before after
  home=$(make_home adopt)
  write_ship_brief "$home" t-adopt
  brief="$home/data/t-adopt/brief.md"
  before=$(cat "$brief")
  out=$(adopt_default "$home" t-adopt)
  assert_contains "$out" "adopted: t-adopt rev=1 digest=sha256:" "adoption did not record a revision and digest"
  after=$(cat "$brief")
  [ "$before" = "$after" ] || fail "adoption must never rewrite the brief"
  assert_grep 'binding_version=1' "$(binding_file "$home" t-adopt)" "the record is missing its version"
  assert_grep 'task=t-adopt' "$(binding_file "$home" t-adopt)" "the record is missing its task id"
  assert_grep 'kind=ship' "$(binding_file "$home" t-adopt)" "the record is missing its ship kind"
  assert_grep 'revision=1' "$(binding_file "$home" t-adopt)" "the record is missing its revision"
  assert_grep 'disposition=coupled' "$(binding_file "$home" t-adopt)" "the record is missing its disposition"
  assert_grep 'ambiguity=low' "$(binding_file "$home" t-adopt)" "the record is missing a risk level"
  assert_grep 'intent_digest=sha256:' "$(binding_file "$home" t-adopt)" "the record is missing the intent digest"
  assert_grep 'spec_digest=sha256:' "$(binding_file "$home" t-adopt)" "the record is missing the spec digest"
  assert_grep 'binding_digest=sha256:' "$(binding_file "$home" t-adopt)" "the record is missing the binding digest"
  out=$(run_check "$home" t-adopt)
  assert_contains "$out" "ok: enrolled rev=1 digest=sha256:" "check did not accept the adopted binding"
  pass "fm-task-contract: adoption records identity and leaves the brief untouched"
}

test_unchanged_identity_is_stable_across_checks() {
  local home first second
  home=$(make_home stable)
  write_ship_brief "$home" t-stable
  adopt_default "$home" t-stable >/dev/null
  first=$(run_check "$home" t-stable)
  second=$(run_check "$home" t-stable)
  [ "$first" = "$second" ] || fail "an unchanged binding must report identical identity: '$first' vs '$second'"
  pass "fm-task-contract: an unchanged binding keeps its revision and digest"
}

test_hash_helper_falls_back_and_rejects_invalid_digests() {
  local home dir fakebin out rc digest
  home=$(make_home hashes)
  write_ship_brief "$home" t-hash
  dir="$TMP_ROOT/hashes"
  fakebin="$dir/fakebin"
  mkdir -p "$fakebin"
  cat >"$fakebin/shasum" <<'SH'
#!/usr/bin/env bash
exit 9
SH
  cat >"$fakebin/sha256sum" <<'SH'
#!/usr/bin/env bash
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  -\n'
SH
  chmod +x "$fakebin/shasum" "$fakebin/sha256sum"
  out=$(PATH="$fakebin:$PATH" adopt_default "$home" t-hash)
  rc=$?
  expect_code 0 "$rc" "adoption should fall back from a failing shasum to sha256sum: $out"
  digest=$(sed -n 's/^intent_digest=//p' "$(binding_file "$home" t-hash)")
  assert_equals "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$digest" \
    "adoption must record the fallback digest, not an empty digest"

  write_ship_brief "$home" t-invalid
  cat >"$fakebin/shasum" <<'SH'
#!/usr/bin/env bash
printf '\n'
SH
  rm -f "$fakebin/sha256sum"
  out=$(PATH="$fakebin:$PATH" adopt_default "$home" t-invalid)
  rc=$?
  expect_code 1 "$rc" "adoption must refuse an empty hash digest: $out"
  assert_contains "$out" "could not compute intent digest" "the refusal should explain the digest failure"
  assert_absent "$(binding_file "$home" t-invalid)" "a refused hash must not write a binding"
  pass "fm-task-contract: hash helper falls back and rejects invalid digests"
}

test_intent_and_spec_edits_require_readoption() {
  local home out brief
  home=$(make_home readopt)
  write_ship_brief "$home" t-intent
  adopt_default "$home" t-intent >/dev/null
  brief="$home/data/t-intent/brief.md"
  python3 - "$brief" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    content = handle.read()
content = content.replace("Do the requested work.", "Do the requested work.\nAnd a later request.", 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(content)
PY
  out=$(run_check "$home" t-intent)
  assert_contains "$out" "intent digest mismatch" "an edited intent must refuse"
  assert_contains "$out" "re-run bin/fm-task-contract.sh adopt t-intent" "the refusal must name re-adoption"
  out=$(adopt_default "$home" t-intent)
  assert_contains "$out" "rev=2" "re-adoption must increment the revision"
  out=$(run_check "$home" t-intent)
  assert_contains "$out" "ok: enrolled rev=2 " "the re-adopted binding should check cleanly"

  python3 - "$brief" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    content = handle.read()
content = content.replace("Implement the requested behavior.", "Implement the revised behavior.", 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(content)
PY
  out=$(run_check "$home" t-intent)
  assert_contains "$out" "spec digest mismatch" "an edited spec must refuse"
  pass "fm-task-contract: editing either Markdown subsection requires re-adoption"
}

test_promoted_ship_instructions_edits_require_readoption() {
  local home brief out
  home=$(make_home promoted)
  write_ship_brief "$home" t-promoted "Investigate and fix." "Scout-time findings are context."
  brief="$home/data/t-promoted/brief.md"
  {
    printf '\n# Current ship Firstmate spec\n'
    printf 'Carry the promoted fix to completion.\n\n'
    printf '# Current delivery mode contract\n'
    printf 'Delivery contract: mode=no-mistakes\n\n'
    printf '# Current ship safety rule\n'
    printf 'Never push to the default branch.\n\n'
    printf '# Definition of done\n'
    printf 'Deliver through no-mistakes.\n'
  } >>"$brief"
  adopt_default "$home" t-promoted >/dev/null
  python3 - "$brief" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    content = handle.read()
content = content.replace("Carry the promoted fix to completion.", "Carry the revised promoted fix to completion.", 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(content)
PY
  out=$(run_check "$home" t-promoted)
  assert_contains "$out" "spec digest mismatch" "an edited promoted ship spec must refuse"
  out=$(adopt_default "$home" t-promoted)
  assert_contains "$out" "rev=2" "re-adoption after a promoted ship spec edit must increment the revision"
  python3 - "$brief" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    content = handle.read()
content = content.replace("Never push to the default branch.", "Never push to any protected branch.", 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(content)
PY
  out=$(run_check "$home" t-promoted)
  assert_contains "$out" "spec digest mismatch" "an edited promoted delivery contract must refuse"
  pass "fm-task-contract: promoted ship instruction edits require re-adoption"
}

test_risk_change_requires_readoption_and_hashes() {
  local home out first second
  home=$(make_home risk)
  write_ship_brief "$home" t-risk
  adopt_default "$home" t-risk >/dev/null
  first=$(run_check "$home" t-risk)
  # Tampering with a recorded risk level is caught by the binding digest.
  python3 - "$(binding_file "$home" t-risk)" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
with open(path, "w", encoding="utf-8") as handle:
    for line in lines:
        handle.write("blast_radius=low\n" if line.startswith("blast_radius=") else line)
PY
  out=$(run_check "$home" t-risk)
  assert_contains "$out" "binding digest mismatch" "an edited risk level must refuse"

  out=$(adopt_task "$home" t-risk unresolved high high high low high high)
  assert_contains "$out" "rev=2" "a deliberate risk revision must increment the revision"
  out=$(run_check "$home" t-risk)
  assert_contains "$out" "ok: enrolled rev=2 " "the revised risk binding should check cleanly"
  second=$(run_check "$home" t-risk)
  [ "$first" != "$second" ] || fail "a material risk change must produce a new binding digest"
  pass "fm-task-contract: risk changes need re-adoption and change the digest"
}

test_risk_floor_is_enforced_at_adoption() {
  local home out
  home=$(make_home floor)
  write_ship_brief "$home" t-floor
  out=$(adopt_task "$home" t-floor routine unknown low low low low low)
  assert_contains "$out" "disposition routine cannot cover an unknown risk level" \
    "an unknown risk level must not be labelled routine"
  out=$(adopt_task "$home" t-floor routine low low high low low low)
  assert_contains "$out" "ambiguity high requires disposition unresolved" \
    "high ambiguity must require the unresolved disposition"
  assert_absent "$(binding_file "$home" t-floor)" "a refused adoption must not write a binding record"
  pass "fm-task-contract: the minimal objective risk floor is enforced"
}

test_copied_wrong_kind_and_missing_bindings_refuse() {
  local home out
  home=$(make_home refuse)
  write_ship_brief "$home" t-source
  write_ship_brief "$home" t-target
  adopt_default "$home" t-source >/dev/null
  cp "$(binding_file "$home" t-source)" "$(binding_file "$home" t-target)"
  out=$(run_check "$home" t-target)
  assert_contains "$out" "binding belongs to another task" "a binding copied from another task must refuse"

  python3 - "$(binding_file "$home" t-target)" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
with open(path, "w", encoding="utf-8") as handle:
    for line in lines:
        if line.startswith("task="):
            handle.write("task=t-target\n")
        elif line.startswith("kind="):
            handle.write("kind=scout\n")
        else:
            handle.write(line)
PY
  out=$(run_check "$home" t-target)
  assert_contains "$out" "binding kind must be ship" "a scout-kind binding must refuse"

  # A recorded task-record binding with no authoritative record is an error,
  # never a fallback to legacy.
  rm -f "$(binding_file "$home" t-target)"
  printf 'window=w\nkind=ship\nbinding_version=1\nbinding_rev=1\nbinding_digest=sha256:%064d\n' 0 \
    >"$home/state/t-target.meta"
  out=$(run_check "$home" t-target)
  assert_contains "$out" "no authoritative binding record" "a missing authoritative record must refuse"
  pass "fm-task-contract: copied, wrong-kind, and missing bindings refuse"
}

test_task_record_disagreement_refuses() {
  local home out
  home=$(make_home meta)
  write_ship_brief "$home" t-meta
  printf 'window=w\nkind=ship\n' >"$home/state/t-meta.meta"
  adopt_default "$home" t-meta >/dev/null
  out=$(run_check "$home" t-meta)
  assert_contains "$out" "ok: enrolled rev=1 " "adoption should bind the existing task record"

  # Duplicate preserved metadata keys are refused rather than trusted.
  printf 'binding_rev=1\n' >>"$home/state/t-meta.meta"
  out=$(run_check "$home" t-meta)
  assert_contains "$out" "task record repeats binding key(s): binding_rev" "duplicate metadata keys must refuse"

  # A stale preserved revision is refused.
  printf 'window=w\nkind=ship\nbinding_version=1\nbinding_rev=99\nbinding_digest=sha256:deadbeef\n' \
    >"$home/state/t-meta.meta"
  out=$(run_check "$home" t-meta)
  assert_contains "$out" "stale binding revision" "a stale preserved revision must refuse"
  pass "fm-task-contract: duplicated or stale task-record bindings refuse"
}

test_only_ship_tasks_may_enroll() {
  local home out
  home=$(make_home shiponly)
  mkdir -p "$home/data/t-scout"
  {
    printf '# Task\n## Captain'\''s intent\nInvestigate.\n\n## Firstmate spec\nReport findings.\n'
  } >"$home/data/t-scout/brief.md"
  out=$(adopt_default "$home" t-scout)
  assert_contains "$out" "only ship tasks may enroll" "a brief with no ship evidence must refuse enrollment"
  printf 'window=w\nkind=scout\n' >"$home/state/t-scout.meta"
  out=$(adopt_default "$home" t-scout)
  assert_contains "$out" "only ship tasks may enroll" "a recorded scout task must refuse enrollment"
  assert_absent "$(binding_file "$home" t-scout)" "a refused scout adoption must not write a record"
  pass "fm-task-contract: only ship tasks may enroll"
}

test_legacy_task_is_unenrolled_and_unchanged() {
  local home out rc
  home=$(make_home legacy)
  write_ship_brief "$home" t-legacy "A legacy request." "A legacy spec."
  printf 'window=w\nkind=ship\nmode=no-mistakes\n' >"$home/state/t-legacy.meta"
  out=$(run_check "$home" t-legacy)
  rc=$?
  expect_code 0 "$rc" "an unenrolled task must check cleanly: $out"
  assert_contains "$out" "ok: unenrolled" "an unenrolled task must report unenrolled"
  assert_absent "$(binding_file "$home" t-legacy)" "check must not enroll a legacy task"
  assert_grep 'A legacy spec.' "$home/data/t-legacy/brief.md" "check must not rewrite a legacy brief"
  pass "fm-task-contract: an unenrolled legacy task stays unchanged"
}

test_adoption_serializes_against_the_task_lock() {
  local home holder lock out rc waited=0
  home=$(make_home lock)
  write_ship_brief "$home" t-lock
  adopt_default "$home" t-lock >/dev/null
  lock="$home/state/.control-t-lock.lock"
  bash -c '
    . "$1/bin/fm-wake-lib.sh"
    fm_lock_acquire_wait "$2"
    : >"$3"
    sleep 2
    fm_lock_release "$2"
  ' _ "$ROOT" "$lock" "$home/state/holder-ready" &
  holder=$!
  while [ ! -e "$home/state/holder-ready" ] && [ "$waited" -lt 100 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
  [ -e "$home/state/holder-ready" ] || fail "the lock holder never acquired the task lock"
  out=$(adopt_default "$home" t-lock)
  rc=$?
  expect_code 1 "$rc" "adoption must refuse while another lifecycle action holds the lock: $out"
  assert_contains "$out" "another lifecycle action is already running" "the lock refusal did not explain the contention"
  wait "$holder" || true
  pass "fm-task-contract: adoption serializes against the task control lock"
}

test_adoption_failure_preserves_existing_binding_pair() {
  local home dir fakebin real_mv out rc check
  home=$(make_home transactional)
  write_ship_brief "$home" t-transactional
  printf 'window=w\nkind=ship\n' >"$home/state/t-transactional.meta"
  adopt_default "$home" t-transactional >/dev/null
  dir="$TMP_ROOT/transactional"
  fakebin="$dir/fakebin"
  mkdir -p "$fakebin"
  real_mv=$(command -v mv)
  cat >"$fakebin/mv" <<'SH'
#!/usr/bin/env bash
last=
for arg in "$@"; do
  last=$arg
done
if [ "$last" = "$FM_FAIL_META_PUBLISH" ]; then
  exit 1
fi
exec "$FM_REAL_MV" "$@"
SH
  chmod +x "$fakebin/mv"
  out=$(FM_REAL_MV="$real_mv" FM_FAIL_META_PUBLISH="$home/state/t-transactional.meta" \
    PATH="$fakebin:$PATH" adopt_default "$home" t-transactional)
  rc=$?
  expect_code 1 "$rc" "adoption must fail when task-record publication fails: $out"
  assert_contains "$out" "error:" "the failed adoption should explain the publication failure"
  check=$(run_check "$home" t-transactional)
  assert_contains "$check" "ok: enrolled rev=1 " \
    "a failed re-adoption must preserve the previous binding and task-record pair"
  pass "fm-task-contract: failed task-record publication preserves the binding pair"
}

test_scripts_parse_under_bash() {
  local f
  for f in "$ROOT/bin/fm-task-contract.sh" "$ROOT/bin/fm-task-contract-lib.sh"; do
    bash -n "$f" || fail "bash -n failed for $f"
  done
  pass "fm-task-contract: scripts parse cleanly"
}

test_adoption_records_identity_and_never_rewrites_the_brief
test_unchanged_identity_is_stable_across_checks
test_hash_helper_falls_back_and_rejects_invalid_digests
test_intent_and_spec_edits_require_readoption
test_promoted_ship_instructions_edits_require_readoption
test_risk_change_requires_readoption_and_hashes
test_risk_floor_is_enforced_at_adoption
test_copied_wrong_kind_and_missing_bindings_refuse
test_task_record_disagreement_refuses
test_only_ship_tasks_may_enroll
test_legacy_task_is_unenrolled_and_unchanged
test_adoption_serializes_against_the_task_lock
test_adoption_failure_preserves_existing_binding_pair
test_scripts_parse_under_bash

echo "ok - fm-task-contract"
