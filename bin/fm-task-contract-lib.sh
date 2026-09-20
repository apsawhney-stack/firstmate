#!/usr/bin/env bash
# fm-task-contract-lib.sh - the bash owner of the opt-in task-contract BINDING.
#
# Narrow scope C: the existing Markdown task instructions remain the single
# source of truth. There is no JSON-authored specification, no generated
# projection, and no semantic completeness check. This file owns exactly one
# thing: an opt-in, versioned binding record that identifies one unchanged
# brief by task, ship kind, monotonic revision, Firstmate-supplied risk levels,
# the intent and effective-spec digests, and one canonical binding digest.
#
# Sourced by bin/fm-task-contract.sh (the adoption/check CLI) and by
# bin/fm-spawn.sh (the launch/relaunch gate and the sole metadata emitter).
# bin/fm-dod-lib.sh remains the single owner of the Task-heading extraction, and
# bin/fm-backlog-transition-lib.sh owns atomic publication. Callers must source
# both alongside this file.
#
# Enrollment is opt-in and legacy-compatible. A task with no binding record and
# no `binding_*` task-record fields is unenrolled and behaves exactly as before;
# adoption never rewrites the brief, and no new dependency is required.
#
# Structural identity only: a passing gate proves that the binding exists, that
# it still matches the Markdown request/specification contract, and that the task
# record agrees. It does not prove the risk assessment was correct or the
# specification good.

# Output globals consumed by the sourcing caller: the launch gate's verdict
# fields and the human-readable refusal diagnostic.
# shellcheck disable=SC2034 # Output global, read by the sourcing caller.
FM_TASK_BINDING_ERROR=
FM_TASK_BINDING_VERSION_SUPPORTED=1
FM_TASK_BINDING_DIMENSIONS='invariant_complexity cross_object_coupling ambiguity blast_radius reversibility evidence_burden'
FM_TASK_BINDING_LEVELS='low elevated high unknown'
FM_TASK_BINDING_DISPOSITIONS='routine coupled unresolved authority-limited'

fm_task_binding_file() {  # <data-dir> <task-id>
  printf '%s/%s/binding\n' "$1" "$2"
}

fm_task_binding_sha256_valid() {  # <digest>
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in
    *[!0-9A-Fa-f]*) return 1 ;;
    *) return 0 ;;
  esac
}

fm_task_binding_sha256_text() {  # <text>
  local text=$1 output hash saw_tool=0 invalid=0
  if command -v shasum >/dev/null 2>&1; then
    saw_tool=1
    if output=$(printf '%s' "$text" | shasum -a 256 2>/dev/null); then
      hash=${output%%[[:space:]]*}
      if fm_task_binding_sha256_valid "$hash"; then
        printf '%s\n' "$hash"
        return 0
      fi
      invalid=1
    fi
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    saw_tool=1
    if output=$(printf '%s' "$text" | sha256sum 2>/dev/null); then
      hash=${output%%[[:space:]]*}
      if fm_task_binding_sha256_valid "$hash"; then
        printf '%s\n' "$hash"
        return 0
      fi
      invalid=1
    fi
  fi
  if [ "$invalid" -eq 1 ]; then
    FM_TASK_BINDING_ERROR="sha256 tool returned an invalid digest"
  elif [ "$saw_tool" -eq 1 ]; then
    FM_TASK_BINDING_ERROR="sha256 tool failed"
  else
    FM_TASK_BINDING_ERROR="no sha256 tool is available (need shasum or sha256sum)"
  fi
  return 1
}

# The exact bytes of one Task subsection with only a single trailing newline
# normalized, matching how the brief's heading bodies are compared.
fm_task_binding_subsection_text() {  # <brief> <heading>
  local body
  body=$(fm_brief_task_heading_body "$1" "$2")
  printf '%s\n' "$body"
}

fm_task_binding_intent_digest() {  # <brief>
  local text hash
  text=$(fm_task_binding_subsection_text "$1" "## Captain's intent") || return 1
  hash=$(fm_task_binding_sha256_text "$text") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="no sha256 tool is available (need shasum or sha256sum)"
    return 1
  }
  printf 'sha256:%s\n' "$hash"
}

fm_task_binding_heading_tail() {  # <brief> <heading>
  local file=$1 heading=$2
  [ -f "$file" ] || return 1
  awk -v heading="$heading" '
    {
      line = $0
      scan = line
      spaces = 0
      while (spaces < 3 && substr(scan, 1, 1) == " ") {
        scan = substr(scan, 2)
        spaces++
      }
      marker = substr(scan, 1, 1)
      marker_len = 0
      if (marker == "`" || marker == "~") {
        while (substr(scan, marker_len + 1, 1) == marker) marker_len++
      }
      is_fence = marker_len >= 3
      was_fenced = fenced
      if (is_fence) {
        rest = substr(scan, marker_len + 1)
        if (!fenced) {
          fenced = 1
          fence_marker = marker
          fence_len = marker_len
        } else if (marker == fence_marker && marker_len >= fence_len && rest ~ /^[[:space:]]*$/) {
          fenced = 0
        }
      }
      if (!found && !was_fenced && line == heading) found = 1
      if (found) print line
    }
    END { if (!found) exit 1 }
  ' "$file"
}

fm_task_binding_effective_spec_text() {  # <brief>
  local brief=$1 task_spec promoted_spec promoted_contract
  task_spec=$(fm_task_binding_subsection_text "$brief" "## Firstmate spec") || return 1
  printf '# Task/## Firstmate spec\n%s\n' "$task_spec"
  if fm_brief_heading_present "$brief" "# Current ship Firstmate spec"; then
    promoted_spec=$(fm_brief_heading_body "$brief" "# Current ship Firstmate spec") || return 1
    printf '\n# Current ship Firstmate spec\n%s\n' "$promoted_spec"
  fi
  if fm_brief_heading_present "$brief" "# Current delivery mode contract"; then
    promoted_contract=$(fm_task_binding_heading_tail "$brief" "# Current delivery mode contract") || return 1
    printf '\n%s\n' "$promoted_contract"
  fi
}

fm_task_binding_spec_digest() {  # <brief>
  local text hash
  text=$(fm_task_binding_effective_spec_text "$1") || return 1
  hash=$(fm_task_binding_sha256_text "$text") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="no sha256 tool is available (need shasum or sha256sum)"
    return 1
  }
  printf 'sha256:%s\n' "$hash"
}

# Canonical serialization of the binding identity, sorted by key and without the
# self-referential binding_digest. This exact text is what the binding digest
# covers, so any edited field is detected without trusting field order.
fm_task_binding_canonical() {  # <version> <task> <kind> <revision> <disposition> <dims...> <intent> <spec>
  local version=$1 task=$2 kind=$3 revision=$4 disposition=$5
  local invariant=$6 coupling=$7 ambiguity=$8 blast=$9 rever=${10} evidence=${11}
  local intent=${12} spec=${13}
  printf 'ambiguity=%s\n' "$ambiguity"
  printf 'binding_version=%s\n' "$version"
  printf 'blast_radius=%s\n' "$blast"
  printf 'cross_object_coupling=%s\n' "$coupling"
  printf 'disposition=%s\n' "$disposition"
  printf 'evidence_burden=%s\n' "$evidence"
  printf 'intent_digest=%s\n' "$intent"
  printf 'invariant_complexity=%s\n' "$invariant"
  printf 'kind=%s\n' "$kind"
  printf 'reversibility=%s\n' "$rever"
  printf 'revision=%s\n' "$revision"
  printf 'spec_digest=%s\n' "$spec"
  printf 'task=%s\n' "$task"
}

fm_task_binding_compute_digest() {  # same args as fm_task_binding_canonical
  local text hash
  text=$(fm_task_binding_canonical "$@") || return 1
  hash=$(fm_task_binding_sha256_text "$text") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="no sha256 tool is available (need shasum or sha256sum)"
    return 1
  }
  printf 'sha256:%s\n' "$hash"
}

# Last value of one key in a flat key=value record. A missing file, missing key,
# or unreadable record prints nothing and returns non-zero only for a missing
# tool.
fm_task_binding_record_get() {  # <file> <key>
  local file=$1 key=$2 line value=''
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*) value=${line#*=} ;;
    esac
  done <"$file" 2>/dev/null || true
  printf '%s' "$value"
}

# Print the keys that appear more than once in a binding-style record; empty when
# every key is unique. Used to refuse a duplicated preserved relaunch binding.
fm_task_binding_duplicate_keys() {  # <file>
  local file=$1
  [ -f "$file" ] || return 0
  sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$file" 2>/dev/null | LC_ALL=C sort | uniq -d
}

fm_task_binding_meta_present() {  # <meta-file>
  [ -f "$1" ] || return 1
  grep -q '^binding_' "$1" 2>/dev/null
}

# Enrollment is positive evidence in either durable place: the authoritative
# record exists (even as a broken symlink, so it refuses), or the task record
# already carries binding fields.
fm_task_binding_enrolled() {  # <data-dir> <state-dir> <task-id>
  local data=$1 state=$2 id=$3
  if [ -e "$data/$id/binding" ] || [ -L "$data/$id/binding" ]; then
    return 0
  fi
  if fm_task_binding_meta_present "$state/$id.meta"; then
    return 0
  fi
  return 1
}

fm_task_binding_level_valid() {  # <value>
  local want=$1 level
  for level in $FM_TASK_BINDING_LEVELS; do
    [ "$want" = "$level" ] && return 0
  done
  return 1
}

fm_task_binding_disposition_valid() {  # <value>
  local want=$1 disposition
  for disposition in $FM_TASK_BINDING_DISPOSITIONS; do
    [ "$want" = "$disposition" ] && return 0
  done
  return 1
}

fm_task_binding_dim_value() {  # <dimension> <invariant> <coupling> <ambiguity> <blast> <reversibility> <evidence>
  case "$1" in
    invariant_complexity) printf '%s' "$2" ;;
    cross_object_coupling) printf '%s' "$3" ;;
    ambiguity) printf '%s' "$4" ;;
    blast_radius) printf '%s' "$5" ;;
    reversibility) printf '%s' "$6" ;;
    evidence_burden) printf '%s' "$7" ;;
  esac
}

# Print the exact key=value record for one binding. Callers compare it against the
# canonical digest; the six risk levels and disposition come from Firstmate.
fm_task_binding_render() {  # <version> <task> <kind> <revision> <disposition> <dims...> <intent> <spec> <digest>
  local version=$1 task=$2 kind=$3 revision=$4 disposition=$5
  local invariant=$6 coupling=$7 ambiguity=$8 blast=$9 rever=${10} evidence=${11}
  local intent=${12} spec=${13} digest=${14}
  printf 'binding_version=%s\n' "$version"
  printf 'task=%s\n' "$task"
  printf 'kind=%s\n' "$kind"
  printf 'revision=%s\n' "$revision"
  printf 'disposition=%s\n' "$disposition"
  printf 'invariant_complexity=%s\n' "$invariant"
  printf 'cross_object_coupling=%s\n' "$coupling"
  printf 'ambiguity=%s\n' "$ambiguity"
  printf 'blast_radius=%s\n' "$blast"
  printf 'reversibility=%s\n' "$rever"
  printf 'evidence_burden=%s\n' "$evidence"
  printf 'intent_digest=%s\n' "$intent"
  printf 'spec_digest=%s\n' "$spec"
  printf 'binding_digest=%s\n' "$digest"
}

# Validate the authoritative binding record against the brief and, when it
# exists, the task record. Sets FM_TASK_BINDING_VERSION/REV/DIGEST on success.
fm_task_binding_gate() {  # <data-dir> <state-dir> <task-id> <worker-kind> <brief>
  local data=$1 state=$2 id=$3 worker_kind=$4 brief=$5
  local file="$data/$id/binding" meta="$state/$id.meta"
  local version task kind revision disposition
  local invariant coupling ambiguity blast rever evidence
  local intent_digest spec_digest binding_digest expected_digest
  local recorded_intent recorded_spec duplicates key value
  FM_TASK_BINDING_ERROR=
  FM_TASK_BINDING_VERSION=
  FM_TASK_BINDING_REV=
  FM_TASK_BINDING_DIGEST=

  if [ "$worker_kind" != ship ]; then
    FM_TASK_BINDING_ERROR="only ship tasks may enroll, but this task is kind '$worker_kind'"
    return 1
  fi
  if [ -L "$file" ]; then
    FM_TASK_BINDING_ERROR="binding record must not be a symlink: $file"
    return 1
  fi
  if [ ! -f "$file" ]; then
    FM_TASK_BINDING_ERROR="enrolled task has no authoritative binding record at $file; run bin/fm-task-contract.sh adopt $id"
    return 1
  fi
  if [ ! -r "$file" ]; then
    FM_TASK_BINDING_ERROR="binding record is unreadable: $file"
    return 1
  fi
  if [ ! -f "$brief" ]; then
    FM_TASK_BINDING_ERROR="enrolled task has no brief at $brief"
    return 1
  fi

  duplicates=$(fm_task_binding_duplicate_keys "$file")
  if [ -n "$duplicates" ]; then
    FM_TASK_BINDING_ERROR="binding record repeats key(s): $(printf '%s' "$duplicates" | tr '\n' ' ' | sed 's/ $//')"
    return 1
  fi

  version=$(fm_task_binding_record_get "$file" binding_version)
  task=$(fm_task_binding_record_get "$file" task)
  kind=$(fm_task_binding_record_get "$file" kind)
  revision=$(fm_task_binding_record_get "$file" revision)
  disposition=$(fm_task_binding_record_get "$file" disposition)
  invariant=$(fm_task_binding_record_get "$file" invariant_complexity)
  coupling=$(fm_task_binding_record_get "$file" cross_object_coupling)
  ambiguity=$(fm_task_binding_record_get "$file" ambiguity)
  blast=$(fm_task_binding_record_get "$file" blast_radius)
  rever=$(fm_task_binding_record_get "$file" reversibility)
  evidence=$(fm_task_binding_record_get "$file" evidence_burden)
  intent_digest=$(fm_task_binding_record_get "$file" intent_digest)
  spec_digest=$(fm_task_binding_record_get "$file" spec_digest)
  binding_digest=$(fm_task_binding_record_get "$file" binding_digest)

  if [ "$version" != "$FM_TASK_BINDING_VERSION_SUPPORTED" ]; then
    FM_TASK_BINDING_ERROR="unsupported binding version: ${version:-<missing>} (this reader supports $FM_TASK_BINDING_VERSION_SUPPORTED)"
    return 1
  fi
  if [ "$task" != "$id" ]; then
    FM_TASK_BINDING_ERROR="binding belongs to another task: records '${task:-<missing>}', expected '$id'"
    return 1
  fi
  if [ "$kind" != ship ]; then
    FM_TASK_BINDING_ERROR="binding kind must be ship, records '${kind:-<missing>}'"
    return 1
  fi
  case "$revision" in
    ''|*[!0-9]*) FM_TASK_BINDING_ERROR="binding revision must be a positive integer, records '${revision:-<missing>}'"; return 1 ;;
  esac
  [ "$revision" -ge 1 ] || {
    FM_TASK_BINDING_ERROR="binding revision must be a positive integer, records '$revision'"
    return 1
  }
  fm_task_binding_disposition_valid "$disposition" || {
    FM_TASK_BINDING_ERROR="invalid binding disposition: '${disposition:-<missing>}'"
    return 1
  }
  local dim
  for dim in $FM_TASK_BINDING_DIMENSIONS; do
    value=$(fm_task_binding_dim_value "$dim" "$invariant" "$coupling" "$ambiguity" "$blast" "$rever" "$evidence")
    fm_task_binding_level_valid "$value" || {
      FM_TASK_BINDING_ERROR="invalid risk level for $dim: '${value:-<missing>}'"
      return 1
    }
  done
  if [ "$disposition" = routine ]; then
    for dim in $FM_TASK_BINDING_DIMENSIONS; do
      value=$(fm_task_binding_dim_value "$dim" "$invariant" "$coupling" "$ambiguity" "$blast" "$rever" "$evidence")
      if [ "$value" = unknown ]; then
        FM_TASK_BINDING_ERROR="disposition routine cannot cover an unknown risk level"
        return 1
      fi
    done
  fi
  if [ "$ambiguity" = high ] && [ "$disposition" != unresolved ]; then
    FM_TASK_BINDING_ERROR="ambiguity high requires disposition unresolved, not $disposition"
    return 1
  fi

  recorded_intent=$(fm_task_binding_intent_digest "$brief") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="could not compute intent digest"
    return 1
  }
  recorded_spec=$(fm_task_binding_spec_digest "$brief") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="could not compute spec digest"
    return 1
  }
  if [ "$intent_digest" != "$recorded_intent" ]; then
    FM_TASK_BINDING_ERROR="intent digest mismatch: the ## Captain's intent body changed after adoption; re-run bin/fm-task-contract.sh adopt $id"
    return 1
  fi
  if [ "$spec_digest" != "$recorded_spec" ]; then
    FM_TASK_BINDING_ERROR="spec digest mismatch: the ## Firstmate spec body changed after adoption; re-run bin/fm-task-contract.sh adopt $id"
    return 1
  fi
  expected_digest=$(fm_task_binding_compute_digest "$version" "$task" "$kind" "$revision" \
    "$disposition" "$invariant" "$coupling" "$ambiguity" "$blast" "$rever" "$evidence" \
    "$intent_digest" "$spec_digest") || {
    [ -n "$FM_TASK_BINDING_ERROR" ] || FM_TASK_BINDING_ERROR="could not compute binding digest"
    return 1
  }
  if [ "$binding_digest" != "$expected_digest" ]; then
    FM_TASK_BINDING_ERROR="binding digest mismatch: the binding record was edited after adoption; re-run bin/fm-task-contract.sh adopt $id"
    return 1
  fi

  if fm_task_binding_meta_present "$meta"; then
    duplicates=$(fm_task_binding_duplicate_keys "$meta")
    if [ -n "$duplicates" ]; then
      FM_TASK_BINDING_ERROR="task record repeats binding key(s): $(printf '%s' "$duplicates" | tr '\n' ' ' | sed 's/ $//')"
      return 1
    fi
    value=$(fm_task_binding_record_get "$meta" binding_version)
    [ "$value" = "$version" ] || {
      FM_TASK_BINDING_ERROR="stale binding version: task record records '${value:-<missing>}', binding record is '$version'"
      return 1
    }
    value=$(fm_task_binding_record_get "$meta" binding_rev)
    [ "$value" = "$revision" ] || {
      FM_TASK_BINDING_ERROR="stale binding revision: binding record is revision $revision, task record records '${value:-<missing>}'"
      return 1
    }
    value=$(fm_task_binding_record_get "$meta" binding_digest)
    [ "$value" = "$binding_digest" ] || {
      FM_TASK_BINDING_ERROR="stale binding digest: task record no longer matches the authoritative binding record"
      return 1
    }
  fi

  # shellcheck disable=SC2034 # Output globals, read by the sourcing caller.
  FM_TASK_BINDING_VERSION=$version
  # shellcheck disable=SC2034 # Output global, read by the sourcing caller.
  FM_TASK_BINDING_REV=$revision
  # shellcheck disable=SC2034 # Output global, read by the sourcing caller.
  FM_TASK_BINDING_DIGEST=$binding_digest
  return 0
}

# The launch/relaunch serializer is the sole emitter of the binding fields, so a
# deliberate re-adoption updates the durable task record here, exactly once, by
# dropping every existing binding_* line and appending the validated values.
fm_task_binding_meta_stage() {  # <state-dir> <meta> <version> <revision> <digest> <tmp>
  local meta=$2 version=$3 revision=$4 digest=$5 tmp=$6
  local root rc
  root=$(dirname "$meta")
  if ! fm_backlog_record_present "$meta" "task record" "$root"; then
    # shellcheck disable=SC2034 # Output global, read by the sourcing caller.
    FM_TASK_BINDING_ERROR="$FM_BACKLOG_TRANSITION_ERROR"
    return 1
  fi
  if grep -v '^binding_' "$meta" >"$tmp"; then
    :
  else
    rc=$?
    if [ "$rc" -ne 1 ]; then
      rm -f -- "$tmp"
      FM_TASK_BINDING_ERROR="could not stage the task-record binding"
      return 1
    fi
  fi
  {
    printf 'binding_version=%s\n' "$version"
    printf 'binding_rev=%s\n' "$revision"
    printf 'binding_digest=%s\n' "$digest"
  } >>"$tmp" || {
    rm -f -- "$tmp"
    FM_TASK_BINDING_ERROR="could not stage the task-record binding"
    return 1
  }
  if ! fm_backlog_record_present "$tmp" "staged task record" "$root"; then
    rm -f -- "$tmp"
    FM_TASK_BINDING_ERROR="$FM_BACKLOG_TRANSITION_ERROR"
    return 1
  fi
}

fm_task_binding_meta_publish() {  # <state-dir> <meta> <tmp>
  local meta=$2 tmp=$3
  local root
  root=$(dirname "$meta")
  if ! fm_backlog_atomic_transition publish "$tmp" "$meta" "task record" "$root"; then
    rm -f -- "$tmp"
    FM_TASK_BINDING_ERROR="$FM_BACKLOG_TRANSITION_ERROR"
    return 1
  fi
}

fm_task_binding_meta_bind() {  # <state-dir> <meta> <version> <revision> <digest>
  local state=$1 meta=$2 version=$3 revision=$4 digest=$5
  local tmp="$meta.binding.${BASHPID:-$$}"
  fm_task_binding_meta_stage "$state" "$meta" "$version" "$revision" "$digest" "$tmp" || return 1
  fm_task_binding_meta_publish "$state" "$meta" "$tmp"
}
