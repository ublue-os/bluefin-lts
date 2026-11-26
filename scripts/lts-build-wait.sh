#!/usr/bin/env bash
# Wait for the LTS builds dispatched by scheduled-lts-release.yml.
set -euo pipefail

ERR_FILE=$(mktemp)
trap 'rm -f "$ERR_FILE"' EXIT

is_transient_api_error() {
  grep -Eqi 'HTTP (429|5[0-9][0-9])|rate limit exceeded|secondary rate limit|abuse detection|error connecting to|connection refused|connection reset|context deadline exceeded|i/o timeout|TLS handshake timeout|unexpected EOF|(^|: )EOF($| )' "$1"
}

find_lts_run() {
  local workflow=$1
  local run_id

  for i in $(seq 1 20); do
    if run_id=$(gh run list \
      --workflow "$workflow" \
      --branch lts \
      --event workflow_dispatch \
      --repo "${REPO:?REPO must be set}" \
      --limit 10 \
      --json databaseId,createdAt \
      --jq ".[] | select(.createdAt >= \"${DISPATCH_TIME:?DISPATCH_TIME must be set}\") | .databaseId" \
      2>"$ERR_FILE" | head -1); then
      if [ -n "$run_id" ]; then
        echo "$run_id"
        return 0
      fi
      echo "Waiting for $workflow run to appear in API (attempt $i/20)..." >&2
    elif is_transient_api_error "$ERR_FILE"; then
      echo "Transient API error listing $workflow runs (attempt $i/20); retrying..." >&2
      cat "$ERR_FILE" >&2
    else
      echo "ERROR: gh run list failed for $workflow, not retryable:" >&2
      cat "$ERR_FILE" >&2
      return 1
    fi
    sleep "${FIND_POLL_INTERVAL:-30}"
  done

  echo "ERROR: Could not locate $workflow run dispatched at $DISPATCH_TIME" >&2
  return 1
}

wait_for_lts_build() {
  local run_id=$1 repo=$2
  local poll=${POLL_INTERVAL:-30} max_failures=${MAX_API_FAILURES:-10}
  local base=${RETRY_BASE_DELAY:-15} cap=${RETRY_MAX_DELAY:-120}
  local failures=0 status conclusion delay status_line

  while :; do
    if [ "${BUILD_DEADLINE:-0}" != 0 ] && [ "$(date +%s)" -ge "$BUILD_DEADLINE" ]; then
      echo "ERROR: deadline reached waiting for run $run_id" >&2
      return 1
    fi

    delay=$poll
    if status_line=$(gh run view "$run_id" --json status,conclusion \
        --jq '[.status, (.conclusion // "")] | @tsv' \
        --repo "$repo" 2>"$ERR_FILE"); then
      failures=0
      IFS=$'\t' read -r status conclusion <<<"$status_line"
      case "$status" in
        completed)
          if [ "$conclusion" = success ]; then
            echo "Run $run_id completed successfully"
            return 0
          fi
          echo "ERROR: run $run_id completed with conclusion '$conclusion'" >&2
          return 1
          ;;
        queued | in_progress | waiting | requested | pending) ;;
        *)
          echo "ERROR: unexpected status '$status' for run $run_id" >&2
          return 1
          ;;
      esac
    else
      failures=$((failures + 1))
      if ! is_transient_api_error "$ERR_FILE"; then
        echo "ERROR: gh run view failed for $run_id, not retryable:" >&2
        cat "$ERR_FILE" >&2
        return 1
      fi
      if [ "$failures" -ge "$max_failures" ]; then
        echo "ERROR: $failures consecutive API errors for $run_id, giving up:" >&2
        cat "$ERR_FILE" >&2
        return 1
      fi
      delay=$((base * (1 << (failures - 1))))
      if [ "$delay" -gt "$cap" ]; then
        delay=$cap
      fi
      echo "Transient API error $failures/$max_failures for $run_id, retry in ${delay}s:" >&2
      cat "$ERR_FILE" >&2
    fi
    sleep "$delay"
  done
}

case "${1:-}" in
  find-run) find_lts_run "${2:?usage: $0 find-run WORKFLOW}" ;;
  wait) wait_for_lts_build "${2:?usage: $0 wait RUN_ID REPO}" "${3:?usage: $0 wait RUN_ID REPO}" ;;
  *)
    echo "usage: $0 find-run WORKFLOW | wait RUN_ID REPO" >&2
    exit 2
    ;;
esac
