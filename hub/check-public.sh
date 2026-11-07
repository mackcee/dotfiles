#!/usr/bin/env bash
# check-public.sh <repo-dir> [--staged|--history|--range <rev-range>]
#
# Fails (exit 1) if content about to become public contains:
#   - secrets (gitleaks), or
#   - private homelab details: Tailscale addresses (the CGNAT range and the
#     Tailscale IPv6 prefix), tailnet DNS names (*.ts.net), or any fixed string
#     listed in <repo>/hub/local.denylist (git-ignored; case-insensitive;
#     blank lines and # comments ignored).
#
# --staged   (default) the index: everything tracked plus what's staged
# --history  every commit reachable from any ref
# --range R  every commit in the git revision range R (e.g. origin/main..HEAD)
#
# Output, one finding per line (never the matched text itself):
#   secret<TAB><file><TAB><line><TAB><rule or commit>
#   private<TAB><file><TAB><line><TAB><commit, history mode only>
# Exit: 0 clean, 1 findings, 2 the check itself failed.
set -euo pipefail

usage="usage: check-public.sh <repo-dir> [--staged|--history|--range <rev-range>]"
repo=${1:?$usage}
mode=${2:---staged}
range=${3:-}
[[ "$mode" != --range || -n "$range" ]] || { echo "$usage" >&2; exit 2; }
GITLEAKS=${GITLEAKS:-gitleaks}
TS_RE='(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)|fd7a:115c:a1e0[:]|[A-Za-z0-9-]+\.ts\.net'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
findings=0

# --- secrets -----------------------------------------------------------------
printf '%s' '{{range .}}secret	{{.File}}	{{.StartLine}}	{{.RuleID}}{{"\n"}}{{end}}' >"$tmp/report.tmpl"
case "$mode" in
  --staged) gl=(git --pre-commit --staged) ;;
  --history) gl=(git) ;;
  --range) gl=(git "--log-opts=$range") ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
if ! "$GITLEAKS" "${gl[@]}" "$repo" --no-banner --redact --exit-code 0 \
  --report-format template --report-template "$tmp/report.tmpl" --report-path "$tmp/secrets.txt" >"$tmp/gitleaks.log" 2>&1; then
  echo "check-public: gitleaks failed:" >&2
  tail -5 "$tmp/gitleaks.log" >&2
  exit 2
fi
if [[ -s "$tmp/secrets.txt" ]]; then
  cat "$tmp/secrets.txt"
  findings=1
fi

# --- private details -----------------------------------------------------------
exclude=(':!hub/local.denylist' ':!hub/local.env')
deny=()
if [[ -f "$repo/hub/local.denylist" ]]; then
  grep -vE '^[[:space:]]*(#|$)' "$repo/hub/local.denylist" >"$tmp/deny" || true
  [[ -s "$tmp/deny" ]] && deny=(-i -F -f "$tmp/deny")
fi

# git grep exit codes: 0 match, 1 no match, anything else is an error. Errors
# must fail the check (fail closed), never read as "nothing found".
_git_grep() {
  local rc=0
  git -C "$repo" grep "$@" || rc=$?
  if ((rc > 1)); then
    echo "check-public: git grep failed ($rc)" >&2
    exit 2
  fi
}

# grep_private <pre-pattern options...> -- <revisions...>
grep_private() {
  local -a pre=() revs=()
  while (($#)) && [[ "$1" != -- ]]; do pre+=("$1"); shift; done
  shift || true
  revs=("$@")
  _git_grep -nI "${pre[@]}" -E "$TS_RE" "${revs[@]}" -- . "${exclude[@]}"
  if ((${#deny[@]})); then
    _git_grep -nI "${pre[@]}" "${deny[@]}" "${revs[@]}" -- . "${exclude[@]}"
  fi
}

if [[ "$mode" == --staged ]]; then
  grep_private --cached -- >"$tmp/raw.txt"
  awk -F: '{ printf "private\t%s\t%s\t\n", $1, $2 }' "$tmp/raw.txt" | sort -u >"$tmp/private.txt"
else
  if [[ "$mode" == --range ]]; then
    mapfile -t revs < <(git -C "$repo" rev-list "$range") || { echo "check-public: bad range $range" >&2; exit 2; }
  else
    mapfile -t revs < <(git -C "$repo" rev-list --all)
  fi
  : >"$tmp/raw.txt"
  ((${#revs[@]})) && grep_private -- "${revs[@]}" >"$tmp/raw.txt"
  awk -F: '{ printf "private\t%s\t%s\t%s\n", $2, $3, substr($1, 1, 7) }' "$tmp/raw.txt" | sort -u >"$tmp/private.txt"
fi
if [[ -s "$tmp/private.txt" ]]; then
  cat "$tmp/private.txt"
  findings=1
fi

exit "$findings"
