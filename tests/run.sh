#!/usr/bin/env bash
# Run shellcheck and the bats suite in Docker. Usage: tests/run.sh [bats args...]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="dotfiles-test:latest"

docker build -q -t "$image" "$root/tests" >/dev/null 2>&1 || docker build -t "$image" "$root/tests"

mapfile -t scripts < <(cd "$root" && ls install.sh bin/* lib/*.sh hub/*.sh \
  desktop/omarchy/hooks/theme-set.d/* 2>/dev/null || true)
if ((${#scripts[@]})); then
  docker run --rm -v "$root:/mnt:ro" -w /mnt koalaman/shellcheck:stable -x "${scripts[@]}"
fi

args=("$@")
((${#args[@]})) || args=(tests)
docker run --rm -v "$root:/code:ro" -w /code "$image" "${args[@]}"
