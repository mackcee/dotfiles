# Dotfiles: one config, every machine — design

Date: 2026-11-07
Status: approved 2026-11-07 (public copy; homelab specifics removed)
Owner: Charlie Mack (GitHub `mackcee`)

## 1. Intent

Charlie works across an Omarchy laptop (Polaris) and an Omarchy PC (aurora-2), at home one day and in the office another. He wants to open whichever machine he is on and find the same shell, Neovim, keybindings and look, without doing anything. A change made on one machine (a new keymap, say) should appear on the other within seconds.

Separately, he wants a source-of-truth repository so that any new Linux machine or VM, of any distribution, gets a working Neovim and shell with one command.

The existing `mackcee/dotfiles` repo is a January 2026 snapshot from before Omarchy (NvChad, kitty, zsh) and no longer reflects what he uses.

## 2. Goals, non-goals, anti-goals

Goals
- Live, two-way sync of personal config between Omarchy machines (seconds, not commits).
- A public GitHub repo that is the durable source of truth, updated automatically once a day when something changed.
- One-line, no-login bootstrap of the core layer on any Linux distro, x86_64 or aarch64.
- The same active Omarchy theme on all Omarchy machines.
- Per-machine files where hardware genuinely differs.

Non-goals
- Syncing projects or work folders. That is a separate design, to follow.
- macOS, Windows, or non-Omarchy desktop environments.
- Live sync from VMs. VMs are clone-and-use. If Charlie deliberately pushes a change from a VM to GitHub, it reaches the Omarchy machines at the next daily hub run (§5.9), not live.
- Managing secrets. Credentials never enter the repo.

Anti-goals (would be a failure even if it technically worked)
- A secret pushed to the public repo.
- An Omarchy update or stock file on one machine silently overwriting the other's working setup.
- Charlie having to remember a sync or commit step in normal use.
- A bootstrap that only works on Arch.

## 3. Environment

| Machine | What |
|---|---|
| Polaris | Apple M2 Pro MacBook, Arch Linux ARM, Omarchy 4.x, bash. Already runs Syncthing. |
| aurora-2 | x86_64 PC, Omarchy. |
| borealis | Omarchy; joins later as another desktop machine. |
| Homelab hub | Always-on Debian container running Syncthing, data on the NAS. |

What Charlie has customised relative to Omarchy's stock files (Polaris): `hypr/bindings.lua` (4 lines), `hypr/input.lua` (3 lines), `omarchy/shell.json` (13 lines), `git/config`, the keyboard remap files `hypr/keyboard-remaps.xkb` and `hypr/right-command-escape.xkb`, and possibly the non-sample hooks in `omarchy/hooks/post-update.d/`. Everything else under hypr, ghostty, alacritty, starship, tmux and lazygit is byte-identical to stock. Neovim (`~/.config/nvim`) is a LazyVim config and entirely his. `~/.bashrc` is Omarchy's template plus a few personal aliases.

The active theme is stored per machine in `~/.local/state/omarchy/current/`, not under `~/.config`.

## 4. Approaches considered

| Approach | Verdict |
|---|---|
| A. Own small script + an explicit list of links (`links.conf`) | Chosen. Folder links (nvim) and single-file links (Omarchy files) side by side, per-host entries, nothing to install beyond bash and git. Cost: ~150–300 lines of bash we own and test. Charlie chose to maintain this himself (with AI help) rather than adopt a tool. |
| A2. Dotbot (YAML list of links, as a git submodule) | Same shape as A, already built. Not chosen: Charlie prefers owning it; it also needs Python on the target. |
| B. GNU Stow | Traditional. Not chosen: folder-vs-file linking ("folding") is implicit, so a new nvim file can silently land outside the repo; still needs a wrapper script. |
| C. chezmoi | Ruled out: copies files instead of linking, so edits don't reach Syncthing until a command is run. Breaks "instant". |
| D. Bare git repo over `$HOME` | Ruled out: cannot coexist with Syncthing. |

## 5. Design

### 5.1 Data flow

1. Each Omarchy machine has `~/dotfiles`, kept identical by Syncthing.
2. Real config paths (`~/.config/nvim`, `~/.config/hypr/bindings.lua`, ...) are symlinks into `~/dotfiles`. Editing the real path edits the synced file.
3. The hub's copy (`/srv/dotfiles` in the hub container, on the NAS) is the only copy that is a git repository. `.git` is never synced.
4. Once a day, the hub commits any changes and pushes to `github.com/mackcee/dotfiles` (public).
5. A new VM runs a one-line installer that clones from GitHub over HTTPS and links the core layer.

### 5.2 Repository layout

```
dotfiles/
  install.sh            bootstrap entry point (curl | bash safe)
  links.conf            what is linked where, by layer
  bin/dot               day-to-day helper (track, status, link)
  core/                 any Linux
    nvim/               whole LazyVim folder
    bash/personal.bash  aliases, exports, functions
    git/config
  vm/                   non-Omarchy only
    tmux/  lazygit/  starship.toml   copies of Omarchy's stock
    mise/config.toml    pinned tool versions
    bash/bashrc         minimal ~/.bashrc that sources personal.bash
  desktop/              Omarchy only
    hypr/bindings.lua
    omarchy/shell.json
    omarchy/hooks/...
    omarchy/theme       one line: the active theme name
  hosts/
    polaris/hypr/input.lua, keyboard-remaps.xkb, right-command-escape.xkb
    aurora-2/...        added when needed
  hub/                  the hub's auto-commit script, systemd units, gitleaks config
  docs/
  .gitignore  .stignore
```

### 5.3 `links.conf`

One link per line: `layer  repo-path  target-path`. Layer is `core`, `vm`, `desktop`, or `host:<hostname>`.

- `core`: files that are Charlie's own and identical everywhere: nvim, `personal.bash`, git config. Linked on every machine.
- `vm`: non-Omarchy machines only. Copies of Omarchy's stock tmux, lazygit and starship configs (Omarchy is MIT-licensed), so a VM looks and behaves like his desktops. Never linked on Omarchy, where Omarchy owns those files. That keeps §6's rule that only Charlie's changed files are linked there. If he later customises one of these, it moves from `vm` to `core`.
- `desktop`: Omarchy only, his changed Omarchy files.
- `host:<hostname>`: per-machine overrides.

A repo path ending in `/` is linked as a whole folder; otherwise a single file. Lines are processed in order, and a host entry may replace a desktop entry for the same target.

```
core          core/nvim/                  ~/.config/nvim
core          core/git/config             ~/.config/git/config
vm            vm/tmux/tmux.conf           ~/.config/tmux/tmux.conf
desktop       desktop/hypr/bindings.lua   ~/.config/hypr/bindings.lua
host:polaris  hosts/polaris/hypr/input.lua ~/.config/hypr/input.lua
```

Linking rules
- Idempotent: re-running is a no-op when everything is already correct.
- An existing real file at a target is moved to `~/.local/state/dotfiles/backup/<timestamp>/` before linking. Never deleted.
- Parent folders are created as needed.
- A link pointing somewhere unexpected is reported, not overwritten, unless `--force`.

### 5.4 `install.sh`

Two entry points, one script:
- Fresh machine: `curl -fsSL https://raw.githubusercontent.com/mackcee/dotfiles/main/install.sh | bash`. Clones to `~/dotfiles` over HTTPS (no login) if it's not there.
- Syncthing machine: `~/dotfiles/install.sh`. Works without `.git`, because synced copies have none.

Steps
1. Detect distro package manager (pacman, apt, dnf, zypper, apk) and install base packages: git, curl, unzip, a C compiler, make, ripgrep, fd, tmux, bash-completion. Uses sudo; skips anything already present.
2. Detect Omarchy (presence of the `omarchy` command and `/usr/share/omarchy`).
3. Tools:
   - Not Omarchy: install mise into `~/.local/bin`, then `mise install` from `vm/mise/config.toml` (neovim ≥ 0.11, lazygit, starship, node for LSPs).
   - Omarchy: use Omarchy's own packages; do not install a second Neovim. (Our call; see §8.)
4. Link `core`; on Omarchy also `desktop`; then `host:<hostname>` entries.
5. Bash: on Omarchy, leave `~/.bashrc` (Omarchy's template) in place and add one idempotent line sourcing `~/dotfiles/core/bash/personal.bash`. Elsewhere, install a minimal `~/.bashrc` that sources the same file. `personal.bash` must not assume Omarchy.
6. On Omarchy: apply the theme named in `desktop/omarchy/theme` if it differs from the current one.
7. Print a short summary: what was linked, backed up, skipped.

### 5.5 `dot` helper

- `dot track <path> [--host]`: moves a real config file into the repo (desktop layer, or this host's folder with `--host`), adds the `links.conf` line, links it.
- `dot status`: broken or missing links, untracked edits to Omarchy files that are linked elsewhere, Syncthing conflict files, the hub's last commit/push result.
- `dot link`: re-run linking only.

### 5.6 Neovim on non-Omarchy machines

The LazyVim config includes Omarchy theme plugins (`omarchy-theme-hotreload.lua`, `all-themes.lua`, `theme.lua`) that read Omarchy's theme files. They must fall back cleanly, to Tokyo Night, when `~/.local/state/omarchy/current/theme` is absent. `lazy-lock.json` stays committed so plugin versions match across machines.

### 5.7 Same theme everywhere

- An Omarchy `theme-set` hook writes the new theme name to `desktop/omarchy/theme`, only if it differs. That prevents loops.
- On each Omarchy machine, a systemd user path unit watches that file and runs `omarchy theme set <name>` when it changes and differs from the current theme.
- Backgrounds follow the theme. Custom themes, if any, live in `desktop/omarchy/themes/`.

### 5.8 Syncthing

- New folder `dotfiles` shared between Polaris, aurora-2 (and later borealis) and the hub. Hub-and-spoke, same as the Zettelkasten folder.
- Machines: `~/dotfiles`. Hub: new NAS dataset/folder a NAS dataset, bind-mounted into the hub container at `/srv/dotfiles`.
- `.stignore`: `.git`, `*.bak.*`, nvim swap/undo/state, anything listed as secret-bearing.
- Versioning: staggered, 30 days, on the hub. Simple (10 versions) on the machines, matching the existing Zettelkasten setup.

### 5.9 Daily commit on the hub

- A systemd timer in the hub container, once a day (default 03:00 local), runs `hub/autocommit.sh`:
  1. `git fetch` every run, whether or not anything changed locally.
  2. If there are local changes: run gitleaks on them. On a finding, do not commit; record the failure and stop. Otherwise commit as `auto: <n> files changed`, with the file list in the body.
  3. If GitHub is ahead (a manual push from a VM), rebase the local commit (if any) onto it. This writes the VM's change into `/srv/dotfiles`, and Syncthing carries it to the desktops. On conflict, abort the rebase, leave the working tree as it was, record the failure and stop.
  4. Push if there is anything to push.
  5. If nothing changed on either side, do nothing.
- Push credential: a GitHub deploy key with write access to `mackcee/dotfiles` only, stored in the hub container. No personal token.
- Failures are recorded in a status file the hub serves into the synced folder (e.g. `.hub-status`, excluded from git), which `dot status` reads. No push notifications by default.

### 5.10 Secrets

- Never linked or synced: `gh/hosts.yml`, gcloud, 1Password, Syncthing's own config/keys, SSH keys, `.netrc`, browser profiles, anything with tokens.
- `.gitignore` and `.stignore` both carry that list.
- gitleaks runs on every daily commit (5.9) and once over the full history before the repo goes public.

Personal, non-secret details (decision 8)
- Public: Charlie's name and email (already in every commit's metadata) and short hostnames used as `host:` keys (polaris, aurora-2).
- Never committed: Tailscale IPs, the Proxmox container ID, NAS paths and other homelab specifics. Hub scripts read these from a local, git-ignored settings file (e.g. `hub/local.env`, with a committed `hub/local.env.example`).
- This design document goes into the repo's `docs/` only in a sanitised form, without those details. The full version stays at `~/projects/dotfiles-design/`.
- Before going public, and in the daily run, a small check alongside gitleaks fails on tracked files matching `100.\d+.\d+.\d+` Tailscale addresses or a configurable deny-list (e.g. `<NAS dataset>`, the CT ID).

### 5.11 Repo transition

1. Tag the current `main` as `pre-omarchy` and push the tag.
2. Scan the full history with gitleaks. If anything is found, stop and decide with Charlie (rewrite history or start a fresh public repo) before making it public.
3. Replace the contents with the new layout in one commit. History is kept.
4. Make the repo public.

### 5.12 Rollout order

1. Hub: NAS folder, bind mount, git, gitleaks, deploy key, timer.
2. Import from Polaris into the new layout; review; secret scan; first push.
3. Link Polaris (backups taken); verify the desktop still works (`hyprctl reload`, `hyprctl configerrors`, shell restarts cleanly).
4. Add the Syncthing folder between Polaris and the hub.
5. When aurora-2 is online: diff its customised files against the repo *before* linking, merge anything unique with Charlie, then link and share the folder.
6. Verify on a fresh VM: Ubuntu x86_64 and one other distro (e.g. Fedora or Debian aarch64).
7. borealis whenever it is next online.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Editing the same file on both machines while both are online creates a Syncthing conflict copy | Rare given one-machine-a-day use. `dot status` lists conflict files; versioning keeps both. |
| `omarchy refresh` or an Omarchy migration writes through a symlink into the repo, propagating stock content to the other machine | Only Charlie's few changed files are linked. Syncthing versioning and daily git history allow recovery. `dot status` flags a linked file that now equals stock. Machines should run the same Omarchy version. |
| Omarchy version skew between machines (e.g. aurora-2 behind Polaris) | Update both. Per-host override available for a file that has to differ. |
| Hub offline | Machines still sync directly when both online (Syncthing peers). Daily push resumes when it returns. |
| A secret gets into a tracked file | gitleaks blocks the commit; the file never reaches GitHub. |
| Hub has 512 MB RAM | Git and gitleaks on a small text repo are light. Revisit if the timer fails. |

## 7. Definition of done

- A keymap edit on Polaris appears on aurora-2 within a minute when both are online.
- Changing the theme on one Omarchy machine changes it on the other.
- Exactly one commit appears on GitHub per day with changes, none on a day without.
- A planted fake token in a tracked file blocks that day's commit and shows up in `dot status`.
- On fresh Ubuntu (x86_64) and a second distro/architecture, the one-liner gives a working LazyVim (plugins install, no startup errors), tmux, git and bash config.
- Re-running `install.sh` on any machine changes nothing.
- The repo is public and its full history passes gitleaks.

## 8. Calls made by the designer (please check)

- Stock tmux, lazygit and starship configs are linked only on VMs (the `vm` layer), never on Omarchy (§5.3). Follows from "only what you changed" (decision 6) and "same look everywhere".
- A change Charlie pushes from a VM flows to the desktops at the next daily run, via the hub's fetch and rebase (§5.9). This replaces "VM changes never come back", which a reviewer found ambiguous.
- On Omarchy machines, tools come from Omarchy's packages, not mise, to avoid two Neovims on PATH. VMs therefore run a pinned Neovim that may differ slightly from Omarchy's; plugin versions still match via `lazy-lock.json`.
- monitors.lua stays unmanaged until it is customised; at that point it goes under `hosts/<name>/`.
- Hub-side failures surface through `dot status`, not a push notification.
- Default branch stays `main` (the repo's existing branch), even though Charlie's git default is `master`.
- Daily commit at 03:00 Amsterdam time.

## 9. Left to the builder

Script internals and structure, test approach (e.g. bats plus VM/container smoke tests), per-distro package names, gitleaks version, exact `.stignore` patterns beyond those listed, and the format of `dot status` output.

## 10. Follows this design

Project and work-folder sync across machines is a separate design, brainstormed next.
