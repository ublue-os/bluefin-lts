#!/usr/bin/env bash
# Reproduces the API-blip failure and verifies the wait helper.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/lts-build-wait.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
n=$(cat "$GH_FAKE_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$GH_FAKE_STATE"

case "${SCENARIO:-}" in
  one500)
    if [ "$n" -eq 1 ]; then
      echo "failed to get run: HTTP 500: An error occurred" >&2
      exit 1
    fi
    if [ "$n" -eq 2 ]; then printf 'in_progress\t\n'; else printf 'completed\tsuccess\n'; fi
    ;;
  failed)
    if [ "$n" -eq 1 ]; then printf 'in_progress\t\n'; else printf 'completed\tfailure\n'; fi
    ;;
  one429)
    if [ "$n" -eq 1 ]; then
      echo "HTTP 429: rate limit exceeded" >&2
      exit 1
    fi
    if [ "$n" -eq 2 ]; then printf 'in_progress\t\n'; else printf 'completed\tsuccess\n'; fi
    ;;
  deadline-mid-wait)
    if [ "$n" -eq 1 ]; then printf 'in_progress\t\n'; else printf 'completed\tsuccess\n'; fi
    ;;
  cancelled) printf 'completed\tcancelled\n' ;;
  persistent5xx)
    echo "failed to get jobs: HTTP 502: Bad Gateway" >&2
    exit 1
    ;;
  nonretryable)
    echo "failed to get run: HTTP 404: Not Found" >&2
    exit 1
    ;;
  find-one500)
    if [ "$n" -eq 1 ]; then
      echo "HTTP 500: upstream error" >&2
      exit 1
    fi
    printf '123\n'
    ;;
  find-empty-then-found)
    if [ "$n" -eq 1 ]; then printf ''; else printf '123\n'; fi
    ;;
  find-failure)
    echo "HTTP 404: Not Found" >&2
    exit 1
    ;;
  *)
    echo "unknown scenario ${SCENARIO:-}" >&2
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$tmp/gh"

failures=0

run_case() {
  local scenario=$1 want_code=$2 want_out=$3 want_calls=$4
  shift 4
  local -a args=("$@")
  local deadline=0 poll=0 code calls out
  if [ "$scenario" = deadline ]; then
    deadline=$(( $(date +%s) - 1 ))
  elif [ "$scenario" = deadline-mid-wait ]; then
    deadline=$(( $(date +%s) + 1 ))
    poll=1
  fi

  echo 0 >"$tmp/state"
  set +e
  PATH="$tmp:$PATH" \
    POLL_INTERVAL=$poll FIND_POLL_INTERVAL=0 MAX_API_FAILURES=3 \
    RETRY_BASE_DELAY=0 RETRY_MAX_DELAY=0 BUILD_DEADLINE=$deadline \
    REPO=o/r DISPATCH_TIME=2026-11-24T00:00:00Z \
    GH_FAKE_STATE="$tmp/state" SCENARIO="$scenario" \
    "$helper" "${args[@]}" >"$tmp/out" 2>"$tmp/err"
  code=$?
  set -e

  calls=$(cat "$tmp/state")
  out=$(cat "$tmp/out")
  if [ "$code" -eq "$want_code" ] && [ "$calls" -eq "$want_calls" ] && [ "$out" = "$want_out" ]; then
    echo "PASS $scenario: exit=$code calls=$calls out='${out:-}'"
  else
    echo "FAIL $scenario: exit=$code (want $want_code) calls=$calls (want $want_calls) out='$out' (want '$want_out')"
    cat "$tmp/err" >&2
    failures=$((failures + 1))
  fi
}

run_case one500 0 'Run 123 completed successfully' 3 wait 123 o/r
run_case one429 0 'Run 123 completed successfully' 3 wait 123 o/r
run_case deadline-mid-wait 1 '' 1 wait 123 o/r
run_case failed 1 '' 2 wait 123 o/r
run_case cancelled 1 '' 1 wait 123 o/r
run_case persistent5xx 1 '' 3 wait 123 o/r
run_case nonretryable 1 '' 1 wait 123 o/r
run_case deadline 1 '' 0 wait 123 o/r
run_case find-one500 0 '123' 2 find-run build-regular.yml
run_case find-empty-then-found 0 '123' 2 find-run build-regular.yml
run_case find-failure 1 '' 1 find-run build-regular.yml

if [ "$failures" -ne 0 ]; then
  echo "$failures case(s) failed" >&2
  exit 1
fi
echo "all cases passed"
