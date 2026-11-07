# shellcheck shell=bash
# Link resolution and linking for ~/dotfiles. Source this file; it has no side
# effects beyond defining functions and defaulting DOTFILES_DIR.
#
# links.conf: one link per line, three whitespace-separated fields:
#   <layer>  <repo-path>  <target-path>
# layer: core | vm | desktop | host:<hostname>
#   core     every machine
#   vm       only machines without Omarchy
#   desktop  only Omarchy machines
#   host:X   only the machine whose short hostname is X
# A repo-path ending in "/" is linked as a whole folder, otherwise as a file.
# When two lines share a target, the later line wins.

: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Counters for summaries (reset by dot_link_all).
DOT_N_LINKED=0
DOT_N_BACKUP=0
DOT_N_SKIPPED=0

dot_is_omarchy() {
  command -v omarchy >/dev/null 2>&1 && [[ -d "${DOTFILES_OMARCHY_ROOT:-/usr/share/omarchy}" ]]
}

dot_hostname() {
  if [[ -n "${DOT_HOSTNAME:-}" ]]; then
    printf '%s\n' "$DOT_HOSTNAME"
  else
    local h
    h=$(hostname -s 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname)
    printf '%s\n' "${h%%.*}"
  fi
}

_dot_expand() {
  case "$1" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$HOME" "$1" ;;
  esac
}

# dot_resolve_links <conf> <omarchy 0|1> <hostname>
# Prints: src<TAB>target<TAB>kind   (kind = dir|file)
dot_resolve_links() {
  local conf=$1 omarchy=$2 host=$3
  local n=0 line layer src tgt extra kind t
  local -a order=()
  local -A out=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r layer src tgt extra <<<"$line"
    if [[ -z "${tgt:-}" || -n "${extra:-}" ]]; then
      echo "links.conf line $n: expected 3 fields: <layer> <repo-path> <target> (paths may not contain spaces)" >&2
      return 1
    fi
    case "$layer" in
      core) ;;
      vm) [[ "$omarchy" == 0 ]] || continue ;;
      desktop) [[ "$omarchy" == 1 ]] || continue ;;
      host:?*) [[ "${layer#host:}" == "$host" ]] || continue ;;
      *)
        echo "links.conf line $n: unknown layer '$layer'" >&2
        return 1
        ;;
    esac
    kind="file"
    [[ "$src" == */ ]] && kind=dir
    src="$DOTFILES_DIR/${src%/}"
    tgt=$(_dot_expand "$tgt")
    [[ -v "out[$tgt]" ]] || order+=("$tgt")
    out[$tgt]="$src"$'\t'"$tgt"$'\t'"$kind"
  done <"$conf"
  for t in "${order[@]}"; do
    printf '%s\n' "${out[$t]}"
  done
}

_dot_backup() {
  local tgt=$1 rel dest
  : "${DOT_BACKUP_TS:=$(date +%Y%m%d-%H%M%S)}"
  if [[ "$tgt" == "$HOME"/* ]]; then rel=${tgt#"$HOME"/}; else rel="_root${tgt}"; fi
  dest="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backup/$DOT_BACKUP_TS/$rel"
  mkdir -p "$(dirname "$dest")"
  while [[ -e "$dest" || -L "$dest" ]]; do dest="$dest.1"; done
  mv "$tgt" "$dest"
}

# dot_link_one <src> <target> <force 0|1>
# Returns 0 linked/ok, 2 foreign link skipped, 3 source missing skipped.
dot_link_one() {
  local src=$1 tgt=$2 force=${3:-0} cur word=linked
  if [[ ! -e "$src" ]]; then
    echo "skip-missing  $tgt"
    return 3
  fi
  if [[ -L "$tgt" ]]; then
    cur=$(readlink "$tgt")
    if [[ "$cur" == "$src" ]]; then
      echo "ok  $tgt"
      return 0
    fi
    if [[ "$force" != 1 ]]; then
      echo "skip-foreign  $tgt -> $cur"
      return 2
    fi
    _dot_backup "$tgt"
    word=backup+linked
  elif [[ -e "$tgt" ]]; then
    _dot_backup "$tgt"
    word=backup+linked
  fi
  mkdir -p "$(dirname "$tgt")"
  ln -sn "$src" "$tgt"
  echo "$word  $tgt"
}

# dot_link_all <conf> <force 0|1>
# Links every entry that applies to this machine. Non-zero if any entry was a
# foreign link that was skipped (or the conf is malformed).
dot_link_all() {
  local conf=$1 force=${2:-0} omarchy=0 resolved src tgt rc msg failed=0
  dot_is_omarchy && omarchy=1
  resolved=$(dot_resolve_links "$conf" "$omarchy" "$(dot_hostname)") || return 1
  DOT_N_LINKED=0 DOT_N_BACKUP=0 DOT_N_SKIPPED=0
  while IFS=$'\t' read -r src tgt _; do
    [[ -n "$src" ]] || continue
    rc=0
    msg=$(dot_link_one "$src" "$tgt" "$force") || rc=$?
    printf '%s\n' "$msg"
    case "$msg" in
      linked*) DOT_N_LINKED=$((DOT_N_LINKED + 1)) ;;
      backup+linked*) DOT_N_LINKED=$((DOT_N_LINKED + 1)) DOT_N_BACKUP=$((DOT_N_BACKUP + 1)) ;;
    esac
    case $rc in
      0) : ;;
      2) failed=1 DOT_N_SKIPPED=$((DOT_N_SKIPPED + 1)) ;;
      3) DOT_N_SKIPPED=$((DOT_N_SKIPPED + 1)) ;;
      *) return "$rc" ;;
    esac
  done <<<"$resolved"
  return "$failed"
}
