# Fedora KDE installer: replacing the penguinos image

Date: 2026-10-06
Status: approved 2026-10-06

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
| Disk encryption | None (no LUKS), so Dropbear is not needed |
| Initial passwords | Temporary: `icenoir` for both `icenoir` and `root`. The user changes them after the install |

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
  `vconsole.conf` and `sysconfig/*`.** The new install generates these
  itself.

Carried over by `install.sh`: the CIFS mount in `/etc/fstab`,
`//<ha-host>/config` on `/mnt/homeassistant`, with options
`credentials=/home/icenoir/.smbcredentials-ha,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,vers=3.0,x-systemd.automount,_netdev`.
The credentials file lives in the kept home. The script installs
`cifs-utils`, creates the mount point and appends the fstab line if it is
missing. Every other fstab entry is generated by the installer.

The disk is not encrypted today (`/etc/crypttab` is empty). Whether to enable
LUKS on the new install is decided before the kickstart is written.

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

## Migration: unattended network install that keeps /home

### Facts it relies on (checked 2026-10-06)

- **Disk.** `nvme0n1p3` is one btrfs volume (475 GB, 98 GB used) with
  label `bazzite` (left over from an earlier Bazzite install) and subvolumes
  `root` (the ostree sysroot) and `home` (mounted on `/var/home`).
  The other partitions are `p1` EFI (vfat, 600 MB) and `p2` `/boot` (ext4,
  2 GB, label `bazzite_xboot`, reformatted with label `fedora_boot`).
- **Firmware.** Secure Boot is off, and the firmware has `PCI LAN` network boot
  entries (`Boot001C`, `Boot0023`).
- **Network.** The wired NIC `enp0s31f6` (MAC `<laptop-mac>`) is
  connected. PXE cannot work over Wi-Fi.
- **netboot.xyz.** Runs as Docker stack `/opt/stacks/netbootxyz` in LXC 107
  (<netboot-lxc-ip>) on pve-m720q, with `network_mode: host`. Its `dnsmasq.conf`
  runs in proxy-DHCP mode (`dhcp-range=<lan-network>,proxy`), so the router
  keeps serving addresses and dnsmasq only adds the PXE boot offer.

### Who drives it

Claude runs from a temporary LXC on pve-m720q, logged in with the personal
account, because the laptop session disappears at the first reboot. It works
over SSH to the laptop, then to the installer, then to the new system.
Dropbear is not needed: the Fedora installer brings its own sshd
(`inst.sshd`). Dropbear becomes relevant only if LUKS is chosen, to unlock the
disk remotely on later boots.

### Steps

1. **Backup.** `rsync -aHAX` of `/var/home/icenoir` to pve-m720q's Sabrent
   disk, checked with a second `rsync --checksum --dry-run`. The Wi-Fi
   profiles and `/var/lib/netbird` are copied too. Nothing proceeds until the
   copy is verified.
2. **Kickstart.** `install/t480s.ks` in this repo answers every installer
   question:
   - keyboard `it`, `LANG=en_US.UTF-8`, user `icenoir` with UID 1000;
   - reformat `p1` and `p2`;
   - `%pre` mounts `p3` and changes two names: it relabels the btrfs volume
     from `bazzite` to `fedora`, and renames the old ostree subvolume `root`
     to `ostree-old`. That subvolume stays as an untouched copy of the
     penguinos system and is deleted by hand after two weeks, which frees its
     space;
   - on `p3`, create a new `root` subvolume for `/`, and mount the existing
     `home` subvolume on `/home` without formatting. The home becomes
     `/home/icenoir`, as on any Fedora install, with no `/var/home`;
   - package set `@kde-desktop-environment`;
   - `%post` runs `restorecon -R /home` and clones this repo into the user's
     home.

   **Path migration.** Moving the home from `/var/home/icenoir` to
   `/home/icenoir` breaks Claude Code's per-directory state. Two kinds of
   state depend on the path:
   - `~/.claude/projects/-var-home-icenoir*`: 10 directories holding the
     conversations and the memory;
   - `~/.claude.json`: 15 project keys plus the paths in `settings.json`.
   `install.sh` runs `migrate-home-paths` once. It renames those directories
   and rewrites the keys and paths from `/var/home/icenoir` to
   `/home/icenoir`, after backing each file up with a `.pre-migration`
   suffix. It refuses to run if a `-home-icenoir*` target already exists. The
   dotfiles repo contains no `/var/home` paths. A compatibility symlink
   `/var/home -> /home` is created so stray absolute paths keep resolving.
   The script itself runs after the first login, because chezmoi needs
   `pass-cli login`.

   The temporary passwords are stored as SHA-512 hashes (`--iscrypted`).
   This repository is public, so only a template `install/t480s.ks.in` is
   committed. The rendered kickstart, with the hashes, the MAC and the LAN
   addresses, is generated locally and served from netboot.xyz's web root for
   the duration of the install.

   The new system has key-only SSH from the first boot:
   `/home/icenoir/.ssh/authorized_keys` survives in the kept `home` subvolume,
   and `%post` sets `PermitRootLogin no` and `PasswordAuthentication no`. The
   weak temporary passwords are therefore usable only at the local console,
   never over the LAN.
3. **Netboot hook, only for the laptop.**
   - Add a tag for MAC `<laptop-mac>` to netboot.xyz's `dnsmasq.conf`, so
     that MAC is served an iPXE script.
   - The script boots the Fedora KDE release's `images/pxeboot` kernel and
     initrd with `inst.ks=… inst.sshd inst.text`.
   - Every other device keeps getting the normal netboot.xyz menu.
   - The hook is removed right after the install.
4. **Rehearsal.** The whole chain runs end to end on a throwaway Proxmox VM on
   pve-m720q, bridged on `vmbr0` so it sees the proxy DHCP. The VM's disk is
   laid out like the laptop's: a btrfs volume with `root` and `home`
   subvolumes and a marker file in `home`. It passes when the marker file
   survives and the user can log in to Plasma and niri.
5. **Go.** With the user nearby and a Fedora KDE USB stick ready as fallback:
   - `efibootmgr --bootnext 001C` on the laptop, then reboot;
   - follow the install over `ssh install@<laptop>`;
   - after the reboot, SSH into the new system and run `install.sh`;
   - the user does `pass-cli login`, then `install.sh` runs again.
6. **Verify and clean up.**
   - Run the testing checklist on the real machine.
   - Remove the dnsmasq hook.
   - Restore the Wi-Fi profiles and NetBird state.
   - Destroy the temporary LXC.
7. **Retire penguinos.** Disable its scheduled workflows and archive the
   repository. Images already on GHCR are left alone.

If anything fails before the disk is touched, the laptop simply boots
penguinos again. If it fails after, the USB stick and the verified backup are
the way back.

## Out of scope

- Multi-distro support.
- Running the script unattended at install time (Kickstart).
- Changes to the work LXC (CT 108). `claude-sync-work` keeps working
  unchanged.
