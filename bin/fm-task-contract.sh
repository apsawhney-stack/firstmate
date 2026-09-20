#!/usr/bin/env bash
# fm-task-contract.sh - read-only check and guarded adoption for an opt-in task-contract binding.
#
# Usage:
#   fm-task-contract.sh check <task-id>
#   fm-task-contract.sh adopt <task-id> --disposition <routine|coupled|unresolved|authority-limited> \
#     --invariant-complexity <low|elevated|high|unknown> \
#     --cross-object-coupling <low|elevated|high|unknown> \
#     --ambiguity <low|elevated|high|unknown> \
#     --blast-radius <low|elevated|high|unknown> \
#     --reversibility <low|elevated|high|unknown> \
#     --evidence-burden <low|elevated|high|unknown>
#
# The brief's `## Captain's intent` and `## Firstmate spec` remain the only
# editable task specification. `adopt` records an opt-in identity binding to
# them: the task id, ship kind, a monotonic revision, the six risk levels and
# disposition Firstmate supplied, the exact subsection digests, and one canonical
# binding digest. It never rewrites the brief.
#
# `check` is read-only and verifies the authoritative record at
# data/<id>/binding against the brief and, when present, the task record. A
# missing, corrupt, stale, wrong-task, wrong-kind, or hash-mismatched binding
# refuses with a specific diagnostic. An unenrolled task reports
# `ok: unenrolled` and is never changed. Only ship tasks may enroll.
#
# Re-run `adopt` after any material intent, specification, kind, or risk change;
# an enrolled launch otherwise refuses rather than accepting stale identity.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

# shellcheck source=bin/fm-dod-lib.sh
. "$SCRIPT_DIR/fm-dod-lib.sh"
# shellcheck source=bin/fm-task-contract-lib.sh
. "$SCRIPT_DIR/fm-task-contract-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-backlog-transition-lib.sh
. "$SCRIPT_DIR/fm-backlog-transition-lib.sh"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

COMMAND=${1:-}
case "$COMMAND" in
  check | adopt) ;;
  *)
    echo "usage: fm-task-contract.sh check|adopt <task-id>" >&2
    exit 2
    ;;
esac
ID=${2:-}
fm_task_id_creation_valid "$ID" || {
  echo "error: invalid task id" >&2
  exit 2
}
shift 2

DISPOSITION=
DECLARED_DIMS='invariant_complexity cross_object_coupling ambiguity blast_radius reversibility evidence_burden'
DIM_invariant_complexity=
DIM_cross_object_coupling=
DIM_ambiguity=
DIM_blast_radius=
DIM_reversibility=
DIM_evidence_burden=

fm_dim_set() {  # <dimension> <value>
  case "$1" in
    invariant_complexity) DIM_invariant_complexity=$2 ;;
    cross_object_coupling) DIM_cross_object_coupling=$2 ;;
    ambiguity) DIM_ambiguity=$2 ;;
    blast_radius) DIM_blast_radius=$2 ;;
    reversibility) DIM_reversibility=$2 ;;
    evidence_burden) DIM_evidence_burden=$2 ;;
  esac
}

fm_dim_get() {  # <dimension>
  case "$1" in
    invariant_complexity) printf '%s' "$DIM_invariant_complexity" ;;
    cross_object_coupling) printf '%s' "$DIM_cross_object_coupling" ;;
    ambiguity) printf '%s' "$DIM_ambiguity" ;;
    blast_radius) printf '%s' "$DIM_blast_radius" ;;
    reversibility) printf '%s' "$DIM_reversibility" ;;
    evidence_burden) printf '%s' "$DIM_evidence_burden" ;;
  esac
}

want=
for arg in "$@"; do
  if [ -n "$want" ]; then
    case "$want" in
      disposition) DISPOSITION=$arg ;;
      *) fm_dim_set "$want" "$arg" ;;
    esac
    want=
    continue
  fi
  case "$arg" in
    --disposition) want=disposition ;;
    --disposition=*) DISPOSITION=${arg#--disposition=} ;;
    --invariant-complexity) want=invariant_complexity ;;
    --invariant-complexity=*) fm_dim_set invariant_complexity "${arg#--invariant-complexity=}" ;;
    --cross-object-coupling) want=cross_object_coupling ;;
    --cross-object-coupling=*) fm_dim_set cross_object_coupling "${arg#--cross-object-coupling=}" ;;
    --ambiguity) want=ambiguity ;;
    --ambiguity=*) fm_dim_set ambiguity "${arg#--ambiguity=}" ;;
    --blast-radius) want=blast_radius ;;
    --blast-radius=*) fm_dim_set blast_radius "${arg#--blast-radius=}" ;;
    --reversibility) want=reversibility ;;
    --reversibility=*) fm_dim_set reversibility "${arg#--reversibility=}" ;;
    --evidence-burden) want=evidence_burden ;;
    --evidence-burden=*) fm_dim_set evidence_burden "${arg#--evidence-burden=}" ;;
    *)
      echo "error: unexpected argument: $arg" >&2
      exit 2
      ;;
  esac
done
[ -z "$want" ] || {
  echo "error: --$want requires a value" >&2
  exit 2
}

BRIEF="$DATA/$ID/brief.md"
META="$STATE/$ID.meta"
BINDING_FILE=$(fm_task_binding_file "$DATA" "$ID")

if [ "$COMMAND" = check ]; then
  [ "$#" -eq 0 ] || {
    echo "error: check takes only a task id" >&2
    exit 2
  }
  if ! fm_task_binding_enrolled "$DATA" "$STATE" "$ID"; then
    echo "ok: unenrolled"
    exit 0
  fi
  WORKER_KIND=ship
  if [ -f "$META" ]; then
    recorded_kind=$(fm_task_binding_record_get "$META" kind)
    [ -z "$recorded_kind" ] || WORKER_KIND=$recorded_kind
  fi
  if ! fm_task_binding_gate "$DATA" "$STATE" "$ID" "$WORKER_KIND" "$BRIEF"; then
    echo "error: $FM_TASK_BINDING_ERROR" >&2
    exit 1
  fi
  echo "ok: enrolled rev=$FM_TASK_BINDING_REV digest=$FM_TASK_BINDING_DIGEST"
  exit 0
fi

# adopt
[ -n "$DISPOSITION" ] || {
  echo "error: adopt requires --disposition <routine|coupled|unresolved|authority-limited>" >&2
  exit 2
}
fm_task_binding_disposition_valid "$DISPOSITION" || {
  echo "error: --disposition must be one of routine, coupled, unresolved, authority-limited (got '$DISPOSITION')" >&2
  exit 2
}
for dim in $DECLARED_DIMS; do
  value=$(fm_dim_get "$dim")
  [ -n "$value" ] || {
    echo "error: adopt requires --${dim//_/-} <low|elevated|high|unknown>" >&2
    exit 2
  }
  fm_task_binding_level_valid "$value" || {
    echo "error: --${dim//_/-} must be one of low, elevated, high, unknown (got '$value')" >&2
    exit 2
  }
done
if [ "$DISPOSITION" = routine ]; then
  for dim in $DECLARED_DIMS; do
    value=$(fm_dim_get "$dim")
    if [ "$value" = unknown ]; then
      echo "error: disposition routine cannot cover an unknown risk level" >&2
      exit 1
    fi
  done
fi
if [ "$DIM_ambiguity" = high ] && [ "$DISPOSITION" != unresolved ]; then
  echo "error: ambiguity high requires disposition unresolved, not $DISPOSITION" >&2
  exit 1
fi

# Only ship tasks may enroll. The recorded kind wins when a task record exists;
# otherwise the brief's ship-only delivery-contract line is the evidence.
TASK_KIND=
if [ -f "$META" ]; then
  TASK_KIND=$(fm_task_binding_record_get "$META" kind)
fi
if [ -z "$TASK_KIND" ]; then
  if grep -q '^Delivery contract: mode=' "$BRIEF" 2>/dev/null; then
    TASK_KIND=ship
  fi
fi
if [ "$TASK_KIND" != ship ]; then
  echo "error: only ship tasks may enroll a task-contract binding; $ID is '${TASK_KIND:-not a recorded ship task}'" >&2
  exit 1
fi
[ -f "$BRIEF" ] || {
  echo "error: task $ID has no brief at $BRIEF" >&2
  exit 1
}
if [ -z "$(fm_brief_task_heading_body "$BRIEF" "## Captain's intent" | tr -d '[:space:]')" ]; then
  echo "error: $BRIEF has an empty ## Captain's intent; write the captain's words before adoption" >&2
  exit 1
fi
if [ -z "$(fm_brief_task_heading_body "$BRIEF" "## Firstmate spec" | tr -d '[:space:]')" ]; then
  echo "error: $BRIEF has an empty ## Firstmate spec; write the specification before adoption" >&2
  exit 1
fi

CONTROL_LOCK="$STATE/.control-$ID.lock"
CONTROL_LOCK_HELD=0
META_LOCK=
META_LOCK_HELD=0
BINDING_TMP=
BINDING_ROLLBACK_TMP=
META_TMP=
adopt_cleanup() {
  local status=$?
  [ -z "$BINDING_TMP" ] || rm -f -- "$BINDING_TMP" 2>/dev/null || true
  [ -z "$BINDING_ROLLBACK_TMP" ] || rm -f -- "$BINDING_ROLLBACK_TMP" 2>/dev/null || true
  [ -z "$META_TMP" ] || rm -f -- "$META_TMP" 2>/dev/null || true
  if [ "$META_LOCK_HELD" = 1 ]; then
    META_LOCK_HELD=0
    fm_lock_release "$META_LOCK" || true
  fi
  if [ "$CONTROL_LOCK_HELD" = 1 ]; then
    CONTROL_LOCK_HELD=0
    fm_lock_release "$CONTROL_LOCK" || true
  fi
  return "$status"
}
trap adopt_cleanup EXIT

[ -d "$STATE" ] || {
  echo "error: state dir not found: $STATE" >&2
  exit 1
}
fm_lock_try_acquire "$CONTROL_LOCK" || {
  echo "error: another lifecycle action is already running for task $ID; nothing was changed" >&2
  exit 1
}
CONTROL_LOCK_HELD=1
META_LOCK=$(fm_meta_lock_path "$META") || exit 1
fm_lock_acquire_wait "$META_LOCK"
META_LOCK_HELD=1

# The existing revision is monotonic. A record that names another task, or a
# symlinked record, is refused rather than adopted over.
REVISION=1
if [ -L "$BINDING_FILE" ]; then
  echo "error: binding record must not be a symlink: $BINDING_FILE" >&2
  exit 1
fi
if [ -e "$BINDING_FILE" ]; then
  [ -f "$BINDING_FILE" ] || {
    echo "error: binding record is not a regular file: $BINDING_FILE" >&2
    exit 1
  }
  recorded_task=$(fm_task_binding_record_get "$BINDING_FILE" task)
  if [ -n "$recorded_task" ] && [ "$recorded_task" != "$ID" ]; then
    echo "error: existing binding record belongs to another task ('$recorded_task'); refusing to adopt over it" >&2
    exit 1
  fi
  previous=$(fm_task_binding_record_get "$BINDING_FILE" revision)
  case "$previous" in
    ''|*[!0-9]*) ;;
    *) REVISION=$((previous + 1)) ;;
  esac
fi

INTENT_DIGEST=$(fm_task_binding_intent_digest "$BRIEF") || {
  echo "error: $FM_TASK_BINDING_ERROR" >&2
  exit 1
}
SPEC_DIGEST=$(fm_task_binding_spec_digest "$BRIEF") || {
  echo "error: $FM_TASK_BINDING_ERROR" >&2
  exit 1
}
BINDING_DIGEST=$(fm_task_binding_compute_digest "$FM_TASK_BINDING_VERSION_SUPPORTED" "$ID" ship \
  "$REVISION" "$DISPOSITION" "$DIM_invariant_complexity" "$DIM_cross_object_coupling" \
  "$DIM_ambiguity" "$DIM_blast_radius" "$DIM_reversibility" "$DIM_evidence_burden" \
  "$INTENT_DIGEST" "$SPEC_DIGEST") || {
  echo "error: $FM_TASK_BINDING_ERROR" >&2
  exit 1
}

BINDING_TMP="$DATA/$ID/.binding.${BASHPID:-$$}"
BINDING_ROLLBACK_TMP="$DATA/$ID/.binding.rollback.${BASHPID:-$$}"
mkdir -p "$DATA/$ID"
fm_task_binding_render "$FM_TASK_BINDING_VERSION_SUPPORTED" "$ID" ship "$REVISION" "$DISPOSITION" \
  "$DIM_invariant_complexity" "$DIM_cross_object_coupling" "$DIM_ambiguity" \
  "$DIM_blast_radius" "$DIM_reversibility" "$DIM_evidence_burden" \
  "$INTENT_DIGEST" "$SPEC_DIGEST" "$BINDING_DIGEST" >"$BINDING_TMP" || {
  echo "error: could not render the binding record for $ID" >&2
  exit 1
}
if [ -f "$BINDING_FILE" ]; then
  cp -- "$BINDING_FILE" "$BINDING_ROLLBACK_TMP" || {
    echo "error: could not stage the previous binding record for $ID" >&2
    exit 1
  }
fi
if [ -e "$META" ]; then
  META_TMP="$META.binding.${BASHPID:-$$}"
  if ! fm_task_binding_meta_stage "$STATE" "$META" "$FM_TASK_BINDING_VERSION_SUPPORTED" "$REVISION" "$BINDING_DIGEST" "$META_TMP"; then
    echo "error: $FM_TASK_BINDING_ERROR" >&2
    exit 1
  fi
fi
if ! fm_backlog_atomic_transition publish "$BINDING_TMP" "$BINDING_FILE" "binding record" "$DATA/$ID"; then
  echo "error: $FM_BACKLOG_TRANSITION_ERROR" >&2
  exit 1
fi
BINDING_TMP=

if [ -n "$META_TMP" ]; then
  if ! fm_task_binding_meta_publish "$STATE" "$META" "$META_TMP"; then
    meta_error=$FM_TASK_BINDING_ERROR
    rollback_failed=0
    if [ -f "$BINDING_ROLLBACK_TMP" ]; then
      fm_backlog_atomic_transition publish "$BINDING_ROLLBACK_TMP" "$BINDING_FILE" "binding record" "$DATA/$ID" || rollback_failed=1
      BINDING_ROLLBACK_TMP=
    else
      fm_backlog_atomic_transition remove "$BINDING_FILE" "binding record" "$DATA/$ID" || rollback_failed=1
    fi
    if [ "$rollback_failed" -ne 0 ]; then
      echo "error: $meta_error; rollback failed: $FM_BACKLOG_TRANSITION_ERROR" >&2
    else
      echo "error: $meta_error" >&2
    fi
    exit 1
  fi
  META_TMP=
fi
[ -z "$BINDING_ROLLBACK_TMP" ] || rm -f -- "$BINDING_ROLLBACK_TMP"
BINDING_ROLLBACK_TMP=

echo "adopted: $ID rev=$REVISION digest=$BINDING_DIGEST"
