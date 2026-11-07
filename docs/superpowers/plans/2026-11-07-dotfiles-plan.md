# Dotfiles Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `mackcee/dotfiles` with a layered, symlink-based config repo that stays in sync live between Omarchy machines via Syncthing, auto-commits daily from the homelab hub, and bootstraps any Linux VM with one command.

**Architecture:** Bash only. `links.conf` declares links by layer (`core`, `vm`, `desktop`, `host:<name>`). `lib/links.sh` resolves and creates them, `install.sh` bootstraps, and `bin/dot` is the day-to-day helper. `hub/` holds the daily autocommit, which runs in the homelab Syncthing hub container with a gitleaks and privacy check.

**Tech Stack:**
- bash 5, git, mise (non-Omarchy tool installs)
- gitleaks
- systemd timers and user path units
- Syncthing
- Tests: bats-core and shellcheck, run through Docker images (`bats/bats`, `koalaman/shellcheck:stable`), plus Docker distro smoke tests.

**Spec:** private (`~/projects/dotfiles-design/` on the Hermes VM); a sanitised copy is published as `docs/design.md` in Task 10. Homelab specifics (addresses, container IDs, NAS paths) are deliberately omitted from this public copy.

**Working copy:** `/home/mackc/projects/dotfiles`: a clone of `mackcee/dotfiles` on the Hermes VM, branch `omarchy-rebuild`. Nothing is pushed to GitHub before Task 10.

## Global Constraints

- Layers are exactly `core`, `vm`, `desktop` and `host:<hostname>`.
  - `vm` is linked only when Omarchy is absent; `desktop` only when it is present.
  - Omarchy is present when the `omarchy` command exists and `/usr/share/omarchy` is a directory.
- Linking is idempotent. It never deletes: existing real files go to `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backup/<YYYYmmdd-HHMMSS>/<path relative to $HOME>`.
- A link that points somewhere unexpected is reported and skipped, unless `--force` is given.
- `install.sh` must work when piped from curl (`curl -fsSL https://raw.githubusercontent.com/mackcee/dotfiles/main/install.sh | bash`). The whole body runs inside `main "$@"` on the last line.
- `install.sh` must also work in a `~/dotfiles` that has no `.git` (Syncthing copy). It never runs `git pull` there.
- Neovim on non-Omarchy machines: ≥ 0.11, installed via mise. On Omarchy, no mise Neovim.
- Never commit Tailscale IPs, Proxmox CT IDs, NAS paths or secrets. The hub reads these from git-ignored `hub/local.env`.
- Never sync or commit: `gh/hosts.yml`, `gcloud/`, `1Password/`, `syncthing/`, `~/.ssh`, `.netrc`, browser profiles.
- Default branch is `main`. The daily autocommit runs at 03:00 Europe/Amsterdam.
- Every script passes shellcheck with no warnings.
- Live-system tasks (8, 10, 11, 12) start only after Charlie's explicit go-ahead for that task.

## Review Focus

1. **The target is a real folder with content.** On a fresh Omarchy machine `~/.config/nvim` already exists. Expected: the whole folder moves to backup and is replaced by one link, not merged or partially linked. Test in Task 1.
2. **Paths and names with spaces.** Theme names like "Tokyo Night", and `~` in `links.conf`. Expected: correct expansion and quoting everywhere. Tests in Tasks 1 and 5.
3. **Running as root without sudo.** This is what minimal containers do. Expected: package install proceeds without sudo when root. When neither root nor sudo is available, skip packages with one clear message and continue to linking. Test in Task 3.
4. **Syncthing not finished yet.** A `links.conf` entry whose source file doesn't exist yet. Expected: warn and skip, never create a dangling link. Test in Task 1.
5. **Re-run in a non-git `~/dotfiles`, with stdin not a TTY.** Expected: no git operations and no interactive prompts. Exit 0 with "nothing to do". Test in Task 3.

---

### Task 0: Working copy and test harness

**Files:**
- Create: `tests/run.sh`, `tests/helpers.bash`, `.gitignore`, `.stignore`

**Interfaces:**
- Produces:
  - `tests/run.sh [bats-args]` runs shellcheck on `install.sh bin/* lib/*.sh hub/*.sh`, then bats on `tests/*.bats`, both in Docker.
  - `tests/helpers.bash` provides `setup_fake_home` (temp `$HOME`, `XDG_STATE_HOME`, repo copy at `$HOME/dotfiles`) and `fake_omarchy on|off`, which puts a stub `omarchy` on PATH and sets `DOTFILES_OMARCHY_ROOT` to a temp dir that stands in for `/usr/share/omarchy`.

Steps:
- [ ] **Step 1:** Clone the repo and create the branch. Tag the current main locally (the tag isn't pushed until Task 10).

  ```bash
  gh repo clone mackcee/dotfiles ~/projects/dotfiles
  git -C ~/projects/dotfiles tag pre-omarchy main
  git -C ~/projects/dotfiles switch -c omarchy-rebuild
  ```

- [ ] **Step 2:** `git rm -r` the old content (`kitty/ zsh/ starship/ nvim/ .DS_Store`).
- [ ] **Step 3:** Write `.gitignore` and `.stglobalignore`. Both carry the secret list from Global Constraints, plus `hub/local.env`, `hub/local.denylist` and `.hub-status`.
  - `.gitignore` also has `*.bak.*`, `*.sync-conflict-*`, `.stignore`, `.stfolder` and `.stversions`.
  - `.stglobalignore` also has `.git`, `*.bak.*`, `**/.nvimlog` and `lazy/`.
  - Syncthing never syncs `.stignore` itself. So `.stglobalignore` is the tracked, synced file, and each device's local `.stignore` holds only `#include .stglobalignore`.
  - On a new device, start with an empty `.stignore`, wait for `.stglobalignore` to arrive, then add the include line. A missing include file puts the folder in an error state. (Seen with `~/portal`, 2026-11-07.)
- [ ] **Step 4:** Write `tests/run.sh` and `tests/helpers.bash`, plus `tests/smoke.bats` containing `@test "harness runs" { true; }`.
- [ ] **Step 5:** Run `tests/run.sh`. Expected: `1 test, 0 failures`, and shellcheck silent.
- [ ] **Step 6:** Commit: `chore: reset repo for omarchy layout, add test harness`.

### Task 1: Link resolution and linking (`lib/links.sh`)

**Files:**
- Create: `lib/links.sh`, `links.conf`, `tests/links.bats`

**Interfaces:**
- Produces (sourced library, no side effects on source):
  - `dot_is_omarchy` returns 0 or 1. It honours `DOTFILES_OMARCHY_ROOT` (default `/usr/share/omarchy`).
  - `dot_resolve_links <conf> <omarchy 0|1> <hostname>` prints `src<TAB>target<TAB>kind`.
    - `src` is absolute under `$DOTFILES_DIR` (default `$HOME/dotfiles`); `target` has `~` expanded; `kind` is `dir` or `file`.
    - It applies layer rules. When two lines share a target, the later line wins, so a host entry overrides an earlier desktop entry.
    - Blank lines and `#` comments are ignored. Fields are separated by runs of whitespace. Spaces inside paths are not supported in `links.conf`; reject such a line with an error naming the line number.
  - `dot_link_one <src> <target> <force 0|1>` returns 0 (linked or already correct), 3 (source missing, skipped) or 2 (unexpected link, skipped). It prints one status line: `linked|ok|backup+linked|skip-missing|skip-foreign  <target>`.
  - `dot_link_all <conf> <force>` loops over `dot_resolve_links` and returns non-zero if any entry returned 2.

Steps:
- [ ] **Step 1:** Write failing tests in `tests/links.bats`:
  - `resolve: vm layer only without omarchy`: the conf has one core, one vm and one desktop line. With omarchy=0 the output has 2 lines, including vm and not desktop. With omarchy=1 it has core and desktop.
  - `resolve: host entry overrides desktop for same target`: both lines target `~/.config/hypr/input.lua`. With hostname `polaris` the output has 1 line whose src contains `hosts/polaris/`. With hostname `aurora-2` the src contains `desktop/`.
  - `resolve: comment and blank lines ignored; malformed line errors with line number`.
  - `link: creates parent dirs and symlink`: `[ -L target ]` and `readlink target == src`.
  - `link: idempotent`: the second call prints `ok` and the backup dir doesn't exist.
  - `link: real directory target is backed up whole` (Review Focus 1): pre-create `~/.config/nvim/init.lua`. After linking, `~/.config/nvim` is a link and `backup/*/.config/nvim/init.lua` exists.
  - `link: missing source is skipped, no dangling link` (Review Focus 4): rc 3 and target absent.
  - `link: foreign symlink skipped unless force`: rc 2 with the target unchanged; with force=1 it becomes our link.
  - `link: tilde expansion with HOME containing a space` (Review Focus 2).
- [ ] **Step 2:** Run `tests/run.sh tests/links.bats`. Expected: failures, because the functions aren't defined yet.
- [ ] **Step 3:** Implement `lib/links.sh`. Use `ln -sfn` only after the backup move. Timestamp the backup dir once per process (`DOT_BACKUP_TS`).
- [ ] **Step 4:** Run the tests. Expected: all pass, shellcheck clean.
- [ ] **Step 5:** Write the initial `links.conf` with the header comment explaining the columns. Entries are added in Task 4.
- [ ] **Step 6:** Commit: `feat: links.conf resolution and idempotent linking`.

### Task 2: `bin/dot` helper

**Files:**
- Create: `bin/dot`, `tests/dot.bats`

**Interfaces:**
- Consumes: Task 1 functions.
- Produces:
  - `dot link [--force]` calls `dot_link_all`.
  - `dot track <path> [--layer core|desktop|host]` (default `desktop` on Omarchy, `core` otherwise).
    - `<path>` is relative to `~/.config` or absolute under `$HOME`.
    - It moves the file to `<layer-dir>/<path relative to ~/.config>`. `host` uses `hosts/$(hostname -s)/`, and the line gets layer `host:<hostname>`.
    - It appends the `links.conf` line, then links. It refuses if the path is already a link into the repo, or is a secret-listed path.
  - `dot status` prints sections `links`, `stock`, `conflicts` and `hub`. It exits 1 if any section has problems.
    - `links`: missing, dangling or foreign links.
    - `stock`: on Omarchy, a linked desktop file byte-identical to `$DOTFILES_OMARCHY_ROOT/config/<rel>`. This is the "omarchy refresh wrote through" warning.
    - `conflicts`: `*.sync-conflict-*` files under `$DOTFILES_DIR`.
    - `hub`: the contents of `$DOTFILES_DIR/.hub-status`, failing if `result=fail`.
  - `dot theme-apply` is defined in Task 5.

Steps:
- [ ] **Step 1:** Write failing tests:
  - `track moves file and links it`: afterwards `~/.config/hypr/looknfeel.lua` is a link, `desktop/hypr/looknfeel.lua` exists, and `links.conf` has the new line.
  - `track --layer host uses hostname`.
  - `track refuses gh/hosts.yml`: rc 1, with `secret` in the output.
  - `track twice refuses`.
  - `status flags stock-identical linked file`.
  - `status lists sync-conflict files`.
  - `status reports hub failure`: `.hub-status` contains `result=fail` and `message=gitleaks`, and the output contains `gitleaks` with rc 1.
  - `status clean`: rc 0.
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement `bin/dot`. It sources `"$DOTFILES_DIR/lib/links.sh"`, with `DOTFILES_DIR` resolved from the script's own real path.
- [ ] **Step 4:** Run the tests. Expected: they pass.
- [ ] **Step 5:** Commit: `feat: dot helper (link, track, status)`.

### Task 3: `install.sh`

**Files:**
- Create: `install.sh`, `lib/install.sh`, `tests/install.bats`

**Interfaces:**
- Consumes: Task 1 and 2.
- Produces:
  - `install.sh [--force] [--no-packages]`.
    - Env `DOTFILES_REPO` (default `https://github.com/mackcee/dotfiles.git`) and `DOTFILES_DIR` (default `~/dotfiles`).
    - If `DOTFILES_DIR` is missing, it clones it.
    - It then re-executes `"$DOTFILES_DIR/install.sh"`, so a curl-piped run always uses the cloned copy's libraries.
  - `lib/install.sh` functions:
    - `dot_pkg_manager` echoes `pacman|apt|dnf|zypper|apk|none`, detected with `command -v`.
    - `dot_priv` echoes an empty string when root, `sudo` when sudo exists, and otherwise returns 1.
    - `dot_install_packages <pm>` installs git, curl, unzip, a C compiler, make, ripgrep, fd, tmux and bash-completion.
      - Distro names: `fd-find` on apt (plus a `~/.local/bin/fd` link to `fdfind`), `build-essential` or `gcc` as appropriate.
      - Uses `DEBIAN_FRONTEND=noninteractive` and the non-interactive flags of each package manager.
    - `dot_install_mise` installs mise into `~/.local/bin` (https://mise.run), then runs `mise install` with `MISE_GLOBAL_CONFIG_FILE` pointing at the linked `~/.config/mise/config.toml`.
    - `dot_bash_hook` (Omarchy only) appends exactly one line to `~/.bashrc`, if absent: `[ -r ~/dotfiles/core/bash/personal.bash ] && . ~/dotfiles/core/bash/personal.bash`.
  - Non-Omarchy machines link `vm/bash/bashrc` to `~/.bashrc`. That file sources mise activation and `personal.bash`.
  - Summary output, last line: `dotfiles: <n> linked, <n> backed up, <n> skipped`.

Steps:
- [ ] **Step 1:** Write failing tests:
  - `pkg manager detection` uses stubs on PATH, once for each of the 5 package managers plus none.
  - `priv: root without sudo → empty; non-root without sudo → rc 1` (Review Focus 3).
  - `install with no priv skips packages with one message and still links`.
  - `bash hook appended once`: run twice, and `grep -c` gives 1.
  - `rerun in non-git DOTFILES_DIR does no git ops` (Review Focus 5): a stub `git` on PATH fails if called; the run returns rc 0 with "0 linked" on the second run, stdin `</dev/null`.
  - `omarchy: no mise install; non-omarchy: mise install invoked` (stubbed).
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement. `install.sh` holds only the bootstrap and the `main` wrapper; everything else lives in `lib/install.sh`.
- [ ] **Step 4:** Run the tests. Expected: they pass.
- [ ] **Step 5:** Commit: `feat: install.sh bootstrap for any distro`.

### Task 4: Import config content from Polaris

**Files:**
- Create:
  - `core/nvim/**`, `core/bash/personal.bash`, `core/git/config`, `vm/mise/config.toml`
  - `vm/tmux/tmux.conf`, `vm/lazygit/config.yml`, `vm/starship.toml`, `vm/bash/bashrc`
  - `desktop/hypr/bindings.lua`, `desktop/omarchy/shell.json`, `desktop/omarchy/theme`
  - `hosts/polaris/hypr/input.lua`, `hosts/polaris/hypr/keyboard-remaps.xkb`, `hosts/polaris/hypr/right-command-escape.xkb`
- Modify: `links.conf`, `core/nvim/lua/plugins/{theme.lua,all-themes.lua,omarchy-theme-hotreload.lua}`

**Interfaces:**
- Consumes: the Task 1 `links.conf` format.
- Read-only on Polaris (over Tailscale SSH as `mackc`; host details in the private copy of this plan): copy with `rsync -a` / `scp`. Change nothing there.

Steps:
- [ ] **Step 1:** Copy `~/.config/nvim/` without plugin and state dirs.
- [ ] **Step 2:** Copy the remaining files:
  - `bindings.lua`, `shell.json`, `git/config` and the three host files.
  - The `vm/` files come from Polaris's `/usr/share/omarchy/config/{tmux/tmux.conf,lazygit/config.yml,starship.toml}`.
  - Leave `post-update.d` hooks out; they are Omarchy-generated.
- [ ] **Step 3:** Fill `core/bash/personal.bash`.
  - Take the personal lines of Polaris's `~/.bashrc` (everything after Omarchy's template, e.g. `alias pbc='wl-copy'`).
  - Guard Wayland-only aliases with `command -v wl-copy >/dev/null &&`.
- [ ] **Step 4:** Write the theme and mise files.
  - `desktop/omarchy/theme`: the slug Omarchy uses for Tokyo Night (confirm with `omarchy theme set --help` or the theme dir name on Polaris; expected `tokyo-night`).
  - `vm/mise/config.toml`: pin `neovim`, `lazygit` and `starship` to current stable, `node` to 26.8.1 (matching Polaris), and `usage`.
  - mise must not take over Omarchy tools. On Omarchy, `install.sh` doesn't run `mise install` and this file isn't linked; it is a `vm` entry.
- [ ] **Step 5:** Make the nvim theme plugins fall back cleanly. Omarchy-dependent specs use `cond = vim.uv.fs_stat(vim.fn.expand("~/.local/state/omarchy/current/theme")) ~= nil`. When that's false, colorscheme `tokyonight` (folke/tokyonight.nvim) is used.
- [ ] **Step 6:** Write `links.conf` entries for every file above. Everything under `vm/` uses layer `vm`.
- [ ] **Step 7:** Run the privacy check.
  - Grep the tree for Tailscale addresses, NAS paths, Hermes-VM home paths and LAN addresses (the `content.bats` privacy test). Expected: no matches.
  - `input.lua`'s `/home/mackc/.config/hypr/keyboard-remaps.xkb` is allowed.
- [ ] **Step 8:** Run `tests/run.sh`. Expected: all green.
- [ ] **Step 9:** Commit: `feat: import omarchy config from polaris`.

### Task 5: Same theme everywhere

**Files:**
- Create:
  - `desktop/omarchy/hooks/theme-set.d/dotfiles-record-theme`
  - `desktop/systemd/user/dotfiles-theme.path`, `desktop/systemd/user/dotfiles-theme.service`
  - `tests/theme.bats`
- Modify: `bin/dot` (add `theme-apply`), `links.conf`, `lib/install.sh` (enable the path unit on Omarchy)

**Interfaces:**
- Consumes: Omarchy calls `theme-set.d/*` hooks with the theme slug as `$1`.
- Produces:
  - The hook writes `$1` to `$DOTFILES_DIR/desktop/omarchy/theme` only if the content differs.
  - `dot theme-apply` reads that file. If it differs from the current slug (the basename of `readlink -f ~/.local/state/omarchy/current/theme`, or `omarchy theme current` slugified), it runs `omarchy theme set "<slug>"`.
  - The path unit uses `PathChanged=%h/dotfiles/desktop/omarchy/theme` and triggers the service, which runs `%h/dotfiles/bin/dot theme-apply`.
  - `install.sh` on Omarchy runs `systemctl --user daemon-reload && systemctl --user enable --now dotfiles-theme.path` and `dot theme-apply` once.

Steps:
- [ ] **Step 1:** Write failing tests:
  - `hook writes slug when different`.
  - `hook leaves file untouched when same` (the mtime doesn't change). This is the loop guard.
  - `theme-apply calls omarchy theme set only on difference` (a stub `omarchy` records its args).
  - `slug with spaces from 'theme current' is normalised` (Review Focus 2).
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement the hook, units, subcommand and install step.
- [ ] **Step 4:** Run the tests. Expected: they pass.
- [ ] **Step 5:** Commit: `feat: sync active omarchy theme across machines`.

### Task 6: Public-safety check (`hub/check-public.sh`)

**Files:**
- Create: `hub/check-public.sh`, `hub/local.env.example`, `hub/local.denylist.example`, `tests/check-public.bats`

**Interfaces:**
- Produces: `hub/check-public.sh <repo-dir> [--staged|--history]`.
  - Exit 0 when clean. Exit 1 with `kind<TAB>file<TAB>line` per finding when not.
  - It runs `gitleaks git --staged` (or a full history scan with `--history`).
  - It also greps tracked or staged content for the CGNAT regex above, and for each line of `hub/local.denylist`, if present.
  - The gitleaks binary path comes from `GITLEAKS` (default `gitleaks`). Tests use the `zricethezav/gitleaks` Docker image through a wrapper.

Steps:
- [ ] **Step 1:** Write failing tests:
  - `clean repo passes`.
  - `planted GitHub token fails`, using the fake `ghp_` token from gitleaks' own test fixtures pattern.
  - `tailscale IP fails`.
  - `denylist word fails`.
  - `history mode finds token removed in a later commit`.
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: they pass.
- [ ] **Step 5:** Commit: `feat: secret and privacy check for public repo`.

### Task 7: Daily autocommit (`hub/autocommit.sh`) and units

**Files:**
- Create: `hub/autocommit.sh`, `hub/systemd/dotfiles-autocommit.service`, `hub/systemd/dotfiles-autocommit.timer`, `tests/autocommit.bats`

**Interfaces:**
- Consumes: `hub/check-public.sh`.
- Produces:
  - `hub/autocommit.sh <repo-dir>` implements spec §5.9 steps 1–5.
  - It writes `<repo-dir>/.hub-status` in key=value form: `last_run=<ISO8601>`, `result=ok|fail|noop`, `message=<one line>`, `last_push=<sha or empty>`.
  - Commit message: `auto: <n> files changed`, with a body listing the files one per line.
  - The timer uses `OnCalendar=*-*-* 03:00:00 Europe/Amsterdam` and `Persistent=true`. The service is `Type=oneshot`, running `hub/autocommit.sh /srv/dotfiles`.
- Tests use a local bare repo as `origin`.

Steps:
- [ ] **Step 1:** Write failing tests:
  - `noop when nothing changed`: no new commit and `result=noop`.
  - `commits and pushes local change`: origin main advances by 1 and the message matches `^auto: 1 files changed`.
  - `secret blocks commit`: no commit, `result=fail`, and the message contains `check-public`.
  - `remote ahead, no local change → working tree fast-forwarded`: the file content equals the origin version.
  - `remote ahead plus local change → rebased and pushed`: origin is linear with both commits.
  - `conflict → aborted, working tree byte-identical to before, result=fail`.
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement the script and units.
- [ ] **Step 4:** Run the tests. Expected: they pass.
- [ ] **Step 5:** Commit: `feat: daily hub autocommit with safety checks`.

### Task 8: Hub deployment (LIVE: needs Charlie's go-ahead)

Target: the Proxmox host and the Syncthing hub container (IDs, addresses and keys in the private copy of this plan).

- [ ] **Step 1:** Create a NAS dataset for dotfiles on the Proxmox host.
- [ ] **Step 2:** Add the mount point and restart the CT. This briefly pauses Zettelkasten syncing.
  - Bind-mount it into the hub container at `/srv/dotfiles` (hot-plug, no restart if possible).
  - Verify Syncthing is active again and the existing folders report idle.
- [ ] **Step 3:** In the CT:
  - `apt install git`.
  - Install the gitleaks release binary to `/usr/local/bin`.
  - Run `ssh-keygen -t ed25519 -N '' -f /root/.ssh/dotfiles_deploy`.
  - Set `git config --global user.name 'dotfiles-hub'` and `user.email` to Charlie's email (`mack.cee@gmail.com`).
- [ ] **Step 4:** Add the deploy key: `gh repo deploy-key add <pub> --repo mackcee/dotfiles --allow-write --title dotfiles-hub`. This is an external change.
- [ ] **Step 5:** Clone `omarchy-rebuild`'s content into `/srv/dotfiles`.
  - `origin` is `git@github.com:mackcee/dotfiles.git`, using `core.sshCommand` with the deploy key.
  - Write `hub/local.env` and `hub/local.denylist` (container ID, NAS pool name, Tailscale IPs).
- [ ] **Step 5b:** Install pinned copies of the hub scripts *outside* the synced repo, from reviewed git HEAD (not the working tree): `git -C /srv/dotfiles show HEAD:hub/autocommit.sh` and `HEAD:hub/check-public.sh` into `/usr/local/lib/dotfiles-hub/` (root-owned, 0755). Put hub settings in `/etc/dotfiles-hub/local.env` (see `hub/local.env.example`). Re-pin deliberately after reviewing any later change to `hub/`.
- [ ] **Step 6:** Install the units into `/etc/systemd/system/` and enable the timer. Before enabling, make sure `/srv/dotfiles` HEAD is the published `main` (Task 10), never the `omarchy-rebuild` branch: the push-range check would block it anyway, but don't rely on that. Confirm `systemctl list-timers` shows the next run at 03:00 Amsterdam.
- [ ] **Step 7:** Run `hub/autocommit.sh /srv/dotfiles` once without pushing (`DOTFILES_NO_PUSH=1`). Expected: `.hub-status` shows `result=noop`.

### Task 9: Distro smoke tests

**Files:**
- Create: `tests/smoke.sh`

**Interfaces:**
- Produces: `tests/smoke.sh [image...]`. Defaults: `ubuntu:24.04 debian:13 fedora:44 archlinux:latest alpine:3.24`.
  - Each run mounts the working copy read-only, copies it to `/root/dotfiles` and runs `bash /root/dotfiles/install.sh </dev/null`.
  - It then asserts:
    - `nvim --version` ≥ 0.11.
    - `nvim --headless "+Lazy! sync" +qa` exits 0.
    - `nvim --headless "+lua io.write(vim.g.colors_name)" +qa` prints `tokyonight`.
    - `~/.config/tmux/tmux.conf` is a link.
    - A second `install.sh` run prints `0 linked`.

Steps:
- [ ] **Step 1:** Write `tests/smoke.sh`.
- [ ] **Step 2:** Run it. Expected: PASS on all five images.
  - Alpine may lack prebuilt mise Neovim for musl. If so, fall back to `apk add neovim` when its version is ≥ 0.11, and record the outcome.
- [ ] **Step 3 (optional, needs go-ahead):** Test aarch64.
  - This needs `docker run --privileged tonistiigi/binfmt --install arm64` on the Hermes VM, then `--platform linux/arm64 debian:13`.
- [ ] **Step 4:** Commit: `test: distro smoke tests`.

### Task 10: Repo transition and go public (LIVE: needs go-ahead)

- [ ] **Step 1:** Push the `pre-omarchy` tag.
- [ ] **Step 2:** Create `hub/local.denylist` in the publishing checkout (from `hub/local.denylist.example`; git-ignored). Then run `hub/check-public.sh . --history` on the full history, old commits included. Expected: clean. On any finding, stop and bring it to Charlie (rewrite history vs fresh repo).
- [ ] **Step 3:** Write the sanitised design doc.
  - Write `docs/design.md` from the spec with Tailscale IPs, CT IDs and NAS paths removed.
  - Re-run the check. Expected: clean.
- [ ] **Step 4:** Squash `omarchy-rebuild` into ONE commit on top of `main` (never push the branch or its intermediate commits). Run `hub/check-public.sh . --range origin/main..HEAD` on exactly what will be pushed, then push `main`.
- [ ] **Step 5:** Run `gh repo edit mackcee/dotfiles --visibility public --accept-visibility-change-consequences`.
- [ ] **Step 6:** From a clean container, check the one-liner. Expected: the smoke assertions from Task 9 pass on `ubuntu:24.04`.

  ```bash
  curl -fsSL https://raw.githubusercontent.com/mackcee/dotfiles/main/install.sh | bash
  ```

### Task 11: Polaris rollout (LIVE: needs go-ahead)

- [ ] **Step 1:** On the hub, share Syncthing folder `dotfiles` (`/srv/dotfiles`) with Polaris.
  - Staggered versioning, 30 days.
  - On Polaris, accept it at `~/dotfiles` with simple versioning (10 versions).
  - Wait until both sides report idle and the `install.sh` hashes match.
- [ ] **Step 2:** On Polaris, run `~/dotfiles/install.sh`. Record the backup dir path from the output.
- [ ] **Step 3:** Verify:
  - `hyprctl reload` succeeds and `hyprctl configerrors` is empty.
  - `omarchy restart shell` works and the bar shows Charlie's layout.
  - `nvim --headless +qa` exits 0.
  - `dot status` exits 0.
  - The Super+Shift+Q dictation bind and the keyboard remap still work. Ask Charlie to press them.
- [ ] **Step 4:** Edit-propagation check: append a comment line to `~/.config/hypr/bindings.lua` on Polaris. Expected: the hub file changes within 60 s. Then revert the line.

### Task 12: aurora-2 rollout (LIVE: when online, needs go-ahead)

- [ ] **Step 1:** Probe with `tailscale ping`. If it's offline, ask Charlie to wake it.
- [ ] **Step 2:** Diff aurora-2's real files against the repo, read-only, before linking anything.
  - Files: every `desktop/` target, `~/.config/nvim`, `~/.bashrc` personal lines and `git/config`.
  - Show the differences to Charlie and merge what he keeps, as `host:aurora-2` entries or shared changes.
- [ ] **Step 3:** Share the folder, wait for idle, run `install.sh`, and verify as in Task 11 Step 3.
- [ ] **Step 4:** Check the definition of done between the two machines:
  - A keymap edit on Polaris appears on aurora-2 within 60 s.
  - `omarchy theme set catppuccin` on Polaris switches aurora-2's theme. Then set it back to Tokyo Night.
- [ ] **Step 5:** Planted-secret check on the hub: plant a fake token, run the autocommit by hand, and confirm `dot status` shows the failure on Polaris. Remove the token and re-run. Expected: `result=noop` or `ok`.

### Done when

Every item in spec §7 has been observed, and `dot status` exits 0 on both machines. Borealis follows Task 12's steps whenever it's next online.
