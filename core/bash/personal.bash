# shellcheck shell=bash
# Charlie's shell additions, loaded by ~/.bashrc on every machine.
# Keep this free of Omarchy assumptions: it also runs on plain VMs.

# Put the `dot` helper on PATH.
__dot_bin="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../bin" && pwd)"
case ":$PATH:" in
  *":$__dot_bin:"*) ;;
  *) PATH="$__dot_bin:$PATH" ;;
esac
unset __dot_bin

[[ $- == *i* ]] || return 0

# Clipboard (Wayland desktops only)
if command -v wl-copy >/dev/null 2>&1; then
  alias pbc='wl-copy'
  alias pbp='wl-paste'
fi

command -v bat >/dev/null 2>&1 && alias cat='bat'
command -v eza >/dev/null 2>&1 && alias lm='eza -lah --icons --sort=modified'
alias n='nvim'
alias gca='git commit --amend'
alias gundo='git reset --soft HEAD~1'

# Vim keybindings on the command line (Esc for normal mode, i/a to insert).
set -o vi

# ble.sh line editor, when installed: load (if ~/.bashrc didn't already) and attach.
if [[ -r "$HOME/.local/share/blesh/ble.sh" ]]; then
  # shellcheck source=/dev/null
  [[ ${BLE_VERSION-} ]] || source "$HOME/.local/share/blesh/ble.sh" --attach=none
  [[ ${BLE_ATTACHED-} ]] || ble-attach
fi
