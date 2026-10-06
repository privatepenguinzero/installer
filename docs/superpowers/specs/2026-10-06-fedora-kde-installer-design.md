# Fedora KDE installer: replacing the penguinos image

Date: 2026-10-06
Status: draft, awaiting review

## Why

penguinos is a bootc image that GitHub Actions rebuilds every night. Keeping it
working takes constant effort, because every build depends on dozens of
external sources: Fedora mirrors, RPM Fusion, Terra, COPR, GitHub releases and
quay.io. On 2026-10-05 alone, three failures with three unrelated causes broke
the build or degraded it: an RPM Fusion mirror timed out, no GitHub runner was
available, and the rpm-ostree chunker digest had been garbage-collected from
quay.io. None of them were bugs in penguinos.

The goal is a normal, mutable Fedora install that can be rebuilt from scratch
with one script, plus chezmoi for everything in `$HOME`. It has no CI. When
something breaks, it breaks on one machine while you are watching it, and you
fix it by rerunning the script.

## Decisions

| Topic | Decision |
|---|---|
| Base | Fedora KDE Plasma edition, current stable release |
| Desktop | niri + DankMaterialShell installed on top of Plasma; Plasma stays as a fallback session |
| Login | SDDM, as shipped with Fedora KDE; niri is picked from its session list. No greetd or dms-greeter |
| Structure | One Bash script with plain-text package lists (no Ansible, no Kickstart) |
| User config | All of it lives in chezmoi (`privatepenguinzero/dotfiles`); the script installs no dotfiles itself |
| Distros | Fedora only; the multi-distro scaffolding in the current `packages.sh` goes away |
| Repo | This repository (`privatepenguinzero/installer`) |

## Repository layout

```
install.sh            entry point, idempotent, safe to rerun
lib/common.sh         log, retry, has_pkg and similar helpers
lists/dnf.txt         one package per line, # comments allowed
lists/flatpak.txt     Flathub application IDs
lists/brew.txt        Homebrew formulae
README.md             how to run it on a fresh install
```

To add a program, add a line to the matching list. `install.sh` only skips what
is already installed or configured, so a rerun after editing a list installs
just the new entries.

## What install.sh does, in order

1. **Preflight.** Checks that `/etc/os-release` says Fedora and that
   `VARIANT_ID=kde`. Refuses to run as root, asks for sudo once and keeps the
   ticket alive while it runs.
2. **dnf setup.** Sets `max_parallel_downloads=10` and enables the third-party
   repos: RPM Fusion free and nonfree, Terra, Brave, the COPRs
   `avengemedia/dms` and `chuang/espanso-wayland`, and NetBird's official repo.
   Every download goes through the `retry` helper, which uses curl's
   `--retry 5 --retry-all-errors` and reruns failed dnf installs with a fresh
   `makecache`. It must never fail on the first mirror that times out.
3. **System packages.** Installs `lists/dnf.txt`. That list holds penguinos's
   CORE_PKGS, the Terra tools (starship, lazygit, topgrade), ghostty, niri,
   quickshell, dms, espanso, brave-origin and the Fedora font packages. Then:
   - codecs: swap `ffmpeg-free` for `ffmpeg`, add the GStreamer plugins;
   - Node 24 (`nodejs24*`, `--allowerasing`);
   - virtualization: qemu-kvm, libvirt, virt-manager.
   Unlike penguinos, it no longer uses `--skip-unavailable`. A typo or a
   renamed package stops the script with its name.
4. **Programs not in any dnf repo.**
   - Homebrew, installed if missing, then `lists/brew.txt`: the five formulae
     in use today (direnv, gh, git-filter-repo, git-lfs, kubernetes-cli) plus
     herdr, rtk and superfile, which move out of the image so they update
     themselves.
   - Checksum-verified GitHub release downloads into `/usr/local/bin`:
     pay-respects, pass-cli and the JetBrainsMono Nerd Font. Cursor comes from
     its RPM URL API. Versions are pinned at the top of `install.sh`.
   - Claude Code, through its official native installer, which updates itself.
5. **Flatpak.** Adds Flathub and installs `lists/flatpak.txt`, which holds the
   10 apps installed today. The KDE apps (Okular, Gwenview, Haruna, KCalc,
   Filelight) are already part of Fedora KDE, so they drop out of the list.
6. **Services and system settings.**
   - Enable `sshd`, `libvirtd`, `podman.socket` and `dnf5-automatic.timer`
     with `apply_updates = yes`.
   - Install the udev rule `91-dms-input-uaccess.rules` and the fontconfig
     defaults, which move over from penguinos `system_files`.
   - Install `/etc/profile.d/brew.sh`.
   - Add the user to the `libvirt` group.
7. **Dotfiles.** `chezmoi init --apply privatepenguinzero/dotfiles`. On a
   rerun, `chezmoi update`. The private SSH key template needs pass-cli, so
   the script stops before this step if `pass-cli info` fails and prints the
   login command (`pass-cli login`, web flow).
8. **Laptop-specific settings.** These run only when the DMI product matches
   the ThinkPad T480s. They are the files that exist on the laptop today, kept
   under `system/t480s/` in this repo:
   - battery thresholds 50/85, as UPower's `CHARGE_LIMIT=50,85` in
     `/etc/udev/hwdb.d/61-battery-local.hwdb` and as the sysfs fallback rule
     `/etc/udev/rules.d/85-battery-thresholds.rules`;
   - UPower `EnableChargeThreshold true`.
9. **Summary.** Lists what changed, what was already in place, and the
   remaining manual steps.

Dropped from penguinos: greetd and dms-greeter, the `/var` and libvirt
tmpfiles workarounds, rechunking, signing, `bootc container lint`, the
`/etc/skel` copies, uupd (dnf5-automatic and topgrade replace it), and the
Silverblue-specific GNOME Terminal and dconf profile.

## What moves into dotfiles

**Shell and desktop.** Files that penguinos wrote into `/etc/skel` but chezmoi
does not manage yet:

- oh-my-zsh and its four custom plugins, as chezmoi `.chezmoiexternal.toml`
  git-repo externals so they stay current;
- LazyVim starter plus `lua/plugins/colorscheme.lua`;
- the Catppuccin themes for btop, bat, mc, delta, zsh-syntax-highlighting and
  superfile (zsh-syntax-highlighting also as an external);
- the herdr `config.toml`;
- the GTK 3 and GTK 4 `settings.ini`;
- the Catppuccin cursors, and the Papirus folder recolour run as a
  `run_onchange_` script.

**Claude Code.** Nothing under `~/.claude` is backed up today. Added to
dotfiles:

- `CLAUDE.md`, `RTK.md`, `settings.json`;
- own skills (every `skills/*` except `gsd-*` and `synced/`);
- own agents (every `agents/*` except `gsd-*`);
- `hooks/` except `gsd-*`, and `scripts/`;
- `plugins/installed_plugins.json` and `plugins/known_marketplaces.json`. On
  first launch Claude Code reinstalls the plugins from the marketplaces;
- `projects/-var-home-icenoir/memory/`;
- `~/.local/bin/claude-sync-work`.

Excluded: credentials, history, `projects/` session logs, caches, telemetry,
the 293 MB plugin cache and the GSD files, which GSD's own installer recreates.
The `dotfiles` repository is private, and the secrets scan of these paths
found nothing.

`.zprofile` already exports `PROTON_PASS_LINUX_KEYRING=dbus` (commit
`4718b7e`). On Plasma, KWallet provides the Secret Service.

**SSH.** Each piece lives in exactly one place:

| Piece | Where it lives |
|---|---|
| `id_ed25519` (private, comment `thinkpad`) | Proton Pass; chezmoi template, as today |
| `id_ed25519.pub` | chezmoi, as today |
| `~/.ssh/config` (zimaboard, m720q, armcloud, armcloud-pub, op5t, claude-work) | added to chezmoi |
| `~/.ssh/authorized_keys` (10 keys) | added to chezmoi; the fleet list `chiavi.txt` on armcloud stays the source of truth for the servers |
| `~/.ssh/known_hosts` | restored from the backup; it changes too often to track |

Because the private key is the same one, every server keeps accepting the
laptop without any change.

## Secrets and machine state that are not in git

Restored from the backup during migration, never committed:

- Wi-Fi profiles (`/etc/NetworkManager/system-connections/*.nmconnection`,
  4 today), which contain the passwords;
- NetBird's client state (`/var/lib/netbird/`). On Fedora, NetBird comes from
  its RPM repo and ships its own unit. The hand-made
  `/etc/systemd/system/netbird.service` is not copied. If the restored state
  is rejected, run `sudo netbird up` to log in again.

## Audit of local /etc changes (2026-10-06)

The audit compared `/etc` with the image's pristine `/usr/etc`. It found 98
entries after filtering out accounts, machine identity and generated caches.
The only ones worth carrying over are already covered above:

- the battery hwdb and udev rule;
- the Wi-Fi profiles and the NetBird state;
- `~/.ssh` (outside `/etc`).

Set in the Fedora installer, not by the script:

- keyboard layout `it` (pc105);
- `LANG=en_US.UTF-8`.

Deliberately dropped:

- **Bazzite leftovers from an earlier rebase:** `bazzite/`, `hhd/`, the
  `steamos` and autologin `sddm.conf.d` files, and the tuned profile
  `balanced-battery-bazzite`. Fedora's own power profiles replace that
  profile.
- **greetd config and its backups.**
- **The hand-made `netbird.service`.** The RPM ships its own unit, and
  `99-netbird.conf` comes with it.
- **authselect `with-fingerprint`.** No fingerprint device is detected.
- **systemd `system.control` resource drop-ins, `default.target`,
  `vconsole.conf`, `sysconfig/*` and `fstab`.** The new install generates
  these itself.

The disk is not encrypted today (`/etc/crypttab` is empty). Whether to enable
LUKS on the new install is a choice in the install checklist.

## Testing

Everything is tested in a libvirt VM on the current laptop before the real
machine is touched. The VM is Fedora KDE stable, installed from the same ISO
that will be used for real. A run counts as passing when:

1. a fresh run of `install.sh` exits 0;
2. a second run exits 0 and reports nothing changed;
3. SDDM offers a niri session, and DMS starts in it;
4. `chezmoi verify` exits 0 after `pass-cli login`;
5. a smoke check passes: `ghostty`, `brave-browser`, `claude`, `herdr`, `rtk`,
   `netbird` and `ffmpeg -codecs | grep -q h264` all run;
6. `shellcheck install.sh lib/*.sh` is clean.

The battery step only runs on real hardware. It is checked once on the laptop
by reading `/sys/class/power_supply/BAT0/charge_control_*_threshold`.

## Migration

1. **Backup.** Copy all of `/var/home/icenoir` to the m720q or to an external
   disk with `rsync -aHAX`, verify the copy, and keep it until the new system
   has been in use for two weeks. List the Flatpak data dirs and libvirt
   images separately, because they can be large.
2. **Install.** Install Fedora KDE from USB and erase the disk. This step is
   done by the user, following a checklist in the README.
3. **Run.** Run `install.sh`, then `pass-cli login` when asked, then the
   script again.
4. **Restore data.** Restore from the backup: `~/personale`,
   `~/.claude/projects` (session history), `~/.ssh/known_hosts`, browser
   profiles, Flatpak app data and VM images.
5. **Retire penguinos.** Disable its scheduled workflows and archive the
   repository. Images already on GHCR are left alone.

## Out of scope

- Multi-distro support.
- Running the script unattended at install time (Kickstart).
- Changes to the work LXC (CT 108). `claude-sync-work` keeps working
  unchanged.
