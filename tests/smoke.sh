#!/usr/bin/env bash
# Distro smoke tests: run install.sh in fresh containers and check the result.
# Usage: tests/smoke.sh [image...]   (default: five distros, run in parallel)
# Logs: tests/.smoke/<image>.log      Exit: non-zero if any image failed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
logs="$root/tests/.smoke"
mkdir -p "$logs"
images=("$@")
((${#images[@]})) || images=(ubuntu:24.04 debian:13 fedora:44 archlinux:latest alpine:3.24)

# Runs inside the container as root.
inner='
set -eu
command -v bash >/dev/null 2>&1 || apk add --no-cache bash >/dev/null
exec bash -euo pipefail -c "
mkdir -p /root/dotfiles && cp -a /src/. /root/dotfiles/ && rm -rf /root/dotfiles/.git /root/dotfiles/.superpowers
cd /root
echo \"== install (1st run)\"
bash /root/dotfiles/install.sh </dev/null
export PATH=\$HOME/.local/bin:\$HOME/.local/share/mise/shims:\$PATH
echo \"== nvim version\"
v=\$(nvim --version | sed -n 1p); echo \"\$v\"
minor=\$(echo \"\$v\" | sed -E \"s/^NVIM v0\\.([0-9]+).*/\\1/\")
[ \"\$minor\" -ge 11 ] || { echo \"FAIL: nvim too old\"; exit 1; }
echo \"== lazy sync\"
timeout 900 nvim --headless \"+Lazy! sync\" +qa
echo \"== startup\"
nvim --headless \"+lua vim.fn.writefile({vim.g.colors_name or \\\"\\\"}, \\\"/tmp/cs\\\")\" \"+lua vim.fn.writefile(vim.split(vim.fn.execute(\\\"messages\\\"), \\\"\\n\\\"), \\\"/tmp/msgs\\\")\" +qa
echo \"colorscheme: \$(cat /tmp/cs)\"
grep -q \"^tokyonight\" /tmp/cs || { echo \"FAIL: colorscheme\"; exit 1; }
if grep -iE \"error|E[0-9]{3,}:\" /tmp/msgs; then echo \"FAIL: startup messages contain errors\"; exit 1; fi
nvim --headless +qa >/tmp/start.out 2>&1 || { echo \"FAIL: plain startup exited non-zero\"; cat /tmp/start.out; exit 1; }
if grep -iE \"missing plugins|fatal:|error\" /tmp/start.out; then echo \"FAIL: startup output contains errors\"; exit 1; fi
echo \"== links\"
test -L \$HOME/.config/tmux/tmux.conf && test -L \$HOME/.config/nvim && test -L \$HOME/.bashrc
echo \"== shell\"
bash -ic \"alias n\" 2>/dev/null | grep -q nvim
echo \"== install (2nd run)\"
bash /root/dotfiles/install.sh </dev/null | tee /tmp/second
grep -q \"dotfiles: 0 linked, 0 backed up, 0 skipped\" /tmp/second
echo SMOKE-PASS
"
'

pids=()
for img in "${images[@]}"; do
  log="$logs/${img//[:\/]/_}.log"
  (docker run --rm -v "$root:/src:ro" "$img" sh -c "$inner" >"$log" 2>&1 && echo "PASS $img" || echo "FAIL $img (see $log)") &
  pids+=($!)
done
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done
for img in "${images[@]}"; do
  grep -q SMOKE-PASS "$logs/${img//[:\/]/_}.log" || rc=1
done
exit "$rc"
