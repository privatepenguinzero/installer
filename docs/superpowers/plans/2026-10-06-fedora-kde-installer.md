# Fedora KDE Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the penguinos bootc image with a plain Fedora KDE install
that one rerunnable script (`install.sh`) and chezmoi rebuild completely. Then
move the T480s onto it through an unattended netboot install that keeps the
`home` btrfs subvolume.

**Architecture:** A Bash entry point `install.sh` sources small,
single-purpose libraries under `lib/`, and reads package names from plain-text
lists under `lists/`. Machine-specific system files live under `system/`. The
OS install is a rendered kickstart (`install/t480s.ks.in`), booted through a
MAC-gated hook in the existing netboot.xyz. That hook is rehearsed on a
throwaway Proxmox VM before the real laptop is touched.

**Tech Stack:** Bash 5, dnf5, Homebrew, Flatpak, chezmoi, pykickstart
(`ksvalidator`), bats-core and shellcheck (both run from containers with
podman), iPXE and dnsmasq (netboot.xyz), Proxmox `qm`.

**Spec:** `docs/superpowers/specs/2026-10-06-fedora-kde-installer-design.md`

## Global Constraints

- Target OS: Fedora KDE Plasma edition, release 44 (`VARIANT_ID=kde`). The
  script refuses anything else.
- `install.sh` runs as the normal user (never root), uses `sudo`, and must be
  idempotent. A second run reports "nothing changed".
- Every network fetch goes through `retry` / `fetch` (curl
  `--retry 5 --retry-all-errors --retry-max-time 180 --connect-timeout 30`).
  A single slow mirror must never abort the script.
- No `--skip-unavailable` on dnf: a missing package stops the script and
  names the package.
- Binary downloads are checksum-verified, with versions pinned at the top of
  `lib/tools.sh`.
- User config lives only in chezmoi (`privatepenguinzero/dotfiles`, private).
  This repo (`privatepenguinzero/installer`) is **public**, so it never
  contains password hashes. The MAC address and LAN IPs appear only in the
  spec and in the rendered kickstart, which is never committed.
- Temporary passwords: `icenoir` for users `icenoir` and `root`, stored as
  SHA-512 hashes. SSH is key-only from the first boot.
- No LUKS.
- Disk: `nvme0n1p1` vfat EFI (UUID `E510-4B13`); `nvme0n1p2` ext4 `/boot`,
  reformatted with label `fedora_boot`; `nvme0n1p3` btrfs, relabelled from
  `bazzite` to `fedora`. On `nvme0n1p3`, subvolume `home` is kept and mounted
  on `/home`, the old `root` is renamed `ostree-old`, and a new `root` is
  created.
- The home path becomes `/home/icenoir`. `/var/home` becomes a symlink to
  `/home`.
- Laptop: ThinkPad T480s, wired NIC `enp0s31f6`, MAC `<laptop-mac>`,
  network boot entry `Boot001C`.
- netboot.xyz: stack `/opt/stacks/netbootxyz` in LXC 107 (<netboot-lxc-ip>) on
  pve-m720q (<pve-host>); proxy-DHCP `dnsmasq.conf`; hook file
  `config/menus/local-vars.ipxe`.
- Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push only when
  the user says so.

## Review Focus

1. **A rerun after a partial failure**, for example the network dropping
   halfway through step 3, must resume and finish, not trip over the half-done
   state. Covered by the bats test `retry gives up after RETRY_MAX attempts`
   and by idempotency check 2 of the rehearsal.
2. **A package renamed or dropped upstream** must stop the run and name the
   package, not install the rest silently. Covered by
   `tests/lists.bats: every dnf.txt entry resolves`.
3. **`migrate-home-paths` run twice, or with both old and new directories
   present**, must refuse and change nothing. Covered by the bats tests in
   Task 5.
4. **Running `install.sh` on a machine that is not the T480s**, such as the
   rehearsal VM, must skip the battery step without failing. Covered by
   `tests/t480s.bats`.
5. **`pass-cli` not logged in** must make step 7 stop with the login
   instruction, not let chezmoi fail midway on the SSH key template. Covered by
   `tests/dotfiles.bats`.

---

## File Structure

```
install.sh                    entry point: preflight, then step_* in order, then the summary
lib/common.sh                 log, warn, die, retry, fetch, verify_sha256, read_list, mark_changed, mark_ok, summary
lib/repos.sh                  enable_rpmfusion, enable_terra, enable_brave, enable_copr, enable_netbird, setup_dnf
lib/packages.sh               missing_rpms, install_dnf_list, install_codecs, install_node24
lib/tools.sh                  pinned versions; install_brew, install_brew_list, install_github_tools, install_cursor, install_claude
lib/flatpak.sh                install_flatpak_list
lib/system.sh                 enable_services, install_system_files, add_cifs_mount, recolor_papirus
lib/dotfiles.sh               require_pass_cli, apply_dotfiles
lib/t480s.sh                  is_t480s, apply_battery_thresholds
bin/migrate-home-paths        one-shot /var/home -> /home rename of Claude state
lists/dnf.txt                 one package per line
lists/flatpak.txt             Flathub app IDs
lists/brew.txt                Homebrew formulae
system/common/...             files copied verbatim under /
system/t480s/...              files copied only on the T480s
install/t480s.ks.in           kickstart template (placeholders @ROOT_HASH@ @USER_HASH@ @DISK@ @PART@)
install/render-ks             renders the template into a kickstart outside the repo
install/netboot-hook          enable|disable the MAC-gated hook on netboot.xyz
install/backup-home           rsync of the home and machine state to pve-m720q
tests/*.bats                  unit tests, run by tests/run
tests/run                     runs shellcheck and bats in containers
README.md                     usage and go-live runbook
```

The old `packages.sh` is deleted in Task 1.

---

### Task 1: Test harness and `lib/common.sh`

**Files:**
- Create: `tests/run`, `tests/common.bats`, `lib/common.sh`
- Delete: `packages.sh`

**Interfaces:**
- Produces:
  - `log MSG`, `warn MSG`, `die MSG`. `die` exits 1.
  - `retry CMD...`. Env `RETRY_MAX` (default 5) and `RETRY_DELAY` (default
    10 s). Returns the last exit code.
  - `fetch URL DEST`. curl with retries; returns non-zero on failure.
  - `verify_sha256 FILE HEX`. Returns 0 on a match.
  - `read_list FILE`. Prints one entry per line, with `#` comments and blank
    lines stripped.
  - `mark_changed MSG` / `mark_ok MSG`. Append to the arrays `CHANGED` and
    `UNCHANGED`.
  - `summary`. Prints both arrays, and prints `nothing changed` when
    `CHANGED` is empty.

- [ ] **Step 1: Write the test runner**

```bash
#!/usr/bin/env bash
# tests/run - shellcheck everything, then the bats suite. Both run in
# containers so the laptop needs only podman. Tests that themselves need
# podman (lists.bats, ks.bats) run in a podman-in-podman container.
set -euo pipefail
cd "$(dirname "$0")/.."
PODMAN_TESTS=(lists.bats ks.bats)
mapfile -t scripts < <(git ls-files 'install.sh' 'lib/*.sh' 'bin/*' 'install/render-ks' 'install/netboot-hook' 'install/backup-home' 'tests/run')
podman run --rm -v "$PWD:/mnt:Z" -w /mnt docker.io/koalaman/shellcheck:stable -x "${scripts[@]}"
mapfile -t plain < <(cd tests && for f in *.bats; do [[ " ${PODMAN_TESTS[*]} " == *" $f "* ]] || echo "/code/tests/$f"; done)
(( ${#plain[@]} )) && podman run --rm -v "$PWD:/code:Z" docker.io/bats/bats:latest "${plain[@]}"
mapfile -t nested < <(cd tests && for f in "${PODMAN_TESTS[@]}"; do [[ -f $f ]] && echo "/code/tests/$f"; done)
if (( ${#nested[@]} )); then
  podman run --rm --privileged -v "$PWD:/code:Z" quay.io/podman/stable:latest \
    bash -c "dnf -yq install bats >/dev/null && bats ${nested[*]}"
fi
```

Run: `chmod +x tests/run`

- [ ] **Step 2: Write the failing tests**

```bash
# tests/common.bats
setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  RETRY_DELAY=0
}

@test "read_list strips comments and blank lines" {
  f="$BATS_TEST_TMPDIR/l.txt"
  printf 'git\n\n# a comment\n  curl   # trailing\n' > "$f"
  run read_list "$f"
  [ "$status" -eq 0 ]
  [ "$output" = $'git\ncurl' ]
}

@test "retry succeeds once the command does" {
  n="$BATS_TEST_TMPDIR/n"; echo 0 > "$n"
  flaky() { c=$(( $(cat "$n") + 1 )); echo "$c" > "$n"; [ "$c" -ge 3 ]; }
  run retry flaky
  [ "$status" -eq 0 ]
  [ "$(cat "$n")" -eq 3 ]
}

@test "retry gives up after RETRY_MAX attempts" {
  RETRY_MAX=2
  run retry false
  [ "$status" -ne 0 ]
}

@test "verify_sha256 accepts the right hash and rejects a wrong one" {
  f="$BATS_TEST_TMPDIR/x"; printf 'abc' > "$f"
  run verify_sha256 "$f" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  [ "$status" -eq 0 ]
  run verify_sha256 "$f" 0000000000000000000000000000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
}

@test "summary says nothing changed when CHANGED is empty" {
  CHANGED=(); UNCHANGED=("dnf packages")
  run summary
  [[ "$output" == *"nothing changed"* ]]
}

@test "summary lists changes" {
  CHANGED=("installed niri"); UNCHANGED=()
  run summary
  [[ "$output" == *"installed niri"* ]]
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `tests/run`
Expected: bats fails with `lib/common.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/common.sh`**

```bash
#!/usr/bin/env bash
# lib/common.sh - helpers shared by every step of install.sh.

CHANGED=()
UNCHANGED=()

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# retry CMD... - rerun CMD until it succeeds, up to RETRY_MAX times.
# Exists because a single slow Fedora or RPM Fusion mirror used to kill the
# whole penguinos build (run 37360965896).
retry() {
  local max=${RETRY_MAX:-5} delay=${RETRY_DELAY:-10} n=1 rc
  while true; do
    "$@" && return 0
    rc=$?
    (( n >= max )) && return "$rc"
    warn "attempt $n/$max failed: $*; retrying in ${delay}s"
    sleep "$delay"
    n=$(( n + 1 ))
  done
}

CURL_RETRY=(--retry 5 --retry-all-errors --retry-max-time 180 --connect-timeout 30)

# fetch URL DEST
fetch() { curl -fsSL "${CURL_RETRY[@]}" -o "$2" "$1"; }

# verify_sha256 FILE HEX
verify_sha256() { printf '%s  %s\n' "$2" "$1" | sha256sum -c --quiet - >/dev/null 2>&1; }

# read_list FILE - entries one per line, comments and blank lines dropped.
read_list() { sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

mark_changed() { CHANGED+=("$*"); }
mark_ok()      { UNCHANGED+=("$*"); }

summary() {
  log "Summary"
  if (( ${#CHANGED[@]} == 0 )); then
    echo "  nothing changed"
  else
    printf '  changed: %s\n' "${CHANGED[@]}"
  fi
  if (( ${#UNCHANGED[@]} )); then printf '  already in place: %s\n' "${UNCHANGED[@]}"; fi
  return 0
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `git rm -q packages.sh && tests/run`
Expected: shellcheck is clean, and the 6 bats tests pass.

- [ ] **Step 6: Commit**

```bash
git add tests/run tests/common.bats lib/common.sh
git commit -m "Add the shared helpers and a containerised test runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Repositories, package lists and the dnf step

**Files:**
- Create: `lib/repos.sh`, `lib/packages.sh`, `lists/dnf.txt`,
  `tests/lists.bats`

**Interfaces:**
- Consumes: `retry`, `fetch`, `log`, `die`, `mark_changed`, `mark_ok`,
  `read_list` (Task 1).
- Produces:
  - `setup_dnf`, which calls `enable_rpmfusion`, `enable_terra`,
    `enable_brave`, `enable_copr avengemedia/dms`,
    `enable_copr chuang/espanso-wayland` and `enable_netbird`. All are
    idempotent and run under sudo.
  - `missing_rpms NAME...`, which prints the names `rpm -q` does not find.
  - `install_dnf_list FILE`.
  - `install_codecs`.
  - `install_node24`.

- [ ] **Step 1: Write the list file**

`lists/dnf.txt`, taken from penguinos `build_files/build.sh` CORE_PKGS, with
the Terra, Brave, COPR and font packages added. greetd is gone, and
`cifs-utils` is new:

```
# desktop apps used inside niri
nautilus
mpv
gnome-terminal
gnome-system-monitor
gnome-calculator
loupe
seahorse
qt6-qtwayland
papirus-icon-theme
# CLI
mc
btop
rsync
fastfetch
unzip
git
wget
curl
bat
eza
duf
jq
tealdeer
iperf3
just
yq
bind-utils
rpm-build
chezmoi
gh
zsh
zoxide
fzf
neovim
ripgrep
fd-find
git-delta
gitleaks
xclip
wl-clipboard
gcc
gcc-c++
make
cargo
cifs-utils
dnf5-plugin-automatic
openssh-server
# virtualization and containers
qemu-kvm
libvirt
virt-install
virt-manager
gnome-boxes
distrobox
podman-compose
# Terra
starship
golang-github-jesseduffield-lazygit
topgrade
ghostty
# desktop: niri + DankMaterialShell (Terra / COPR avengemedia/dms)
niri
niri-settings
quickshell
dms
# COPR chuang/espanso-wayland
espanso
# Brave
brave-origin
# NetBird
netbird
# fonts
rsms-inter-vf-fonts
google-roboto-fonts
google-roboto-mono-fonts
open-sans-fonts
lato-fonts
julietaula-montserrat-fonts
adobe-source-code-pro-fonts
vernnobile-nunito-fonts
weiweihuanghuang-work-sans-fonts
fira-code-fonts
ibm-plex-sans-fonts
ibm-plex-mono-fonts
```

- [ ] **Step 2: Write the failing test**

```bash
# tests/lists.bats
# Resolves every dnf.txt entry against the real repos inside fedora:44.
# Slow (~3 min) but it is the test that catches a renamed package.
@test "every dnf.txt entry resolves" {
  run podman run --rm -v "$BATS_TEST_DIRNAME/..:/src:Z" registry.fedoraproject.org/fedora:44 bash -c '
    set -e
    dnf -yq install dnf5-plugins >/dev/null
    sudo() { "$@"; }
    source /src/lib/common.sh; source /src/lib/repos.sh
    RETRY_DELAY=5 setup_dnf >/dev/null
    want=$(read_list /src/lists/dnf.txt | sort -u)
    have=$(dnf5 -q repoquery --qf "%{name}\n" $want | sort -u)
    missing=$(comm -23 <(echo "$want") <(echo "$have"))
    [ -z "$missing" ] || { echo "unresolved: $missing"; exit 1; }'
  echo "$output"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `tests/run`
Expected: `lists.bats` fails, because `lib/repos.sh` is missing.

- [ ] **Step 4: Implement `lib/repos.sh`**

```bash
#!/usr/bin/env bash
# lib/repos.sh - third-party repositories. Every function is idempotent.

setup_dnf() {
  if ! grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf; then
    sudo sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf
    mark_changed "dnf: max_parallel_downloads=10"
  fi
  enable_rpmfusion
  enable_terra
  enable_brave
  enable_copr avengemedia/dms
  enable_copr chuang/espanso-wayland
  enable_netbird
  retry sudo dnf5 -y makecache >/dev/null
}

enable_rpmfusion() {
  if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    mark_ok "RPM Fusion"; return
  fi
  local d rel r; d=$(mktemp -d); rel=$(rpm -E %fedora)
  for r in free nonfree; do
    retry fetch "https://mirrors.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$rel.noarch.rpm" "$d/$r.rpm" \
      || die "could not download the RPM Fusion $r release package"
  done
  retry sudo dnf5 -y install "$d"/free.rpm "$d"/nonfree.rpm || die "could not add RPM Fusion"
  rm -rf "$d"
  mark_changed "enabled RPM Fusion"
}

enable_terra() {
  if ! rpm -q terra-release >/dev/null 2>&1; then
    retry sudo dnf5 -y install --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" terra-release \
      || die "could not add Terra"
    mark_changed "enabled Terra"
  else
    mark_ok "Terra"
  fi
  # Origin baseurl instead of the metalink: see penguinos build.sh for why the
  # metalink's repomd.xml hash routinely disagrees with every mirror.
  sudo dnf5 config-manager setopt terra.baseurl="https://repos.fyralabs.com/terra\$releasever" terra.metalink="" >/dev/null
}

enable_brave() {
  if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then mark_ok "Brave repo"; return; fi
  local t; t=$(mktemp)
  retry fetch https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo "$t" || die "could not download the Brave repo file"
  sudo install -m 0644 "$t" /etc/yum.repos.d/brave-browser.repo && rm -f "$t"
  mark_changed "enabled Brave repo"
}

# enable_copr OWNER/PROJECT
enable_copr() {
  local f="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${1/\//:}.repo"
  if [[ -f "$f" ]]; then mark_ok "COPR $1"; return; fi
  retry sudo dnf5 -y copr enable "$1" || die "could not enable COPR $1"
  mark_changed "enabled COPR $1"
}

enable_netbird() {
  if [[ -f /etc/yum.repos.d/netbird.repo ]]; then mark_ok "NetBird repo"; return; fi
  sudo tee /etc/yum.repos.d/netbird.repo >/dev/null <<'EOF'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=0
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
EOF
  mark_changed "enabled NetBird repo"
}
```

- [ ] **Step 5: Implement `lib/packages.sh`**

```bash
#!/usr/bin/env bash
# lib/packages.sh - dnf installs. No --skip-unavailable: a missing package must stop the run.

# missing_rpms NAME... - prints each name that is not installed.
missing_rpms() { local p; for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || echo "$p"; done; }

install_dnf_list() {
  local -a want missing
  mapfile -t want < <(read_list "$1")
  mapfile -t missing < <(missing_rpms "${want[@]}")
  if (( ${#missing[@]} == 0 )); then mark_ok "dnf packages (${#want[@]})"; return; fi
  log "Installing ${#missing[@]} packages: ${missing[*]}"
  retry sudo dnf5 -y install "${missing[@]}" || die "dnf could not install: ${missing[*]}"
  mark_changed "installed ${#missing[@]} dnf packages"
}

install_codecs() {
  if rpm -q ffmpeg gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-libav >/dev/null 2>&1; then
    mark_ok "codecs"; return
  fi
  if rpm -q ffmpeg-free >/dev/null 2>&1; then
    retry sudo dnf5 -y swap ffmpeg-free ffmpeg --allowerasing || die "could not swap ffmpeg-free for ffmpeg"
  else
    retry sudo dnf5 -y install ffmpeg --allowerasing || die "could not install ffmpeg"
  fi
  retry sudo dnf5 -y install --allowerasing --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin \
    gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-libav x264-libs \
    || die "could not install the GStreamer plugins"
  mark_changed "installed codecs"
}

install_node24() {
  if [[ "$(node --version 2>/dev/null)" == v24.* ]]; then mark_ok "Node 24"; return; fi
  retry sudo dnf5 -y install --allowerasing nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin || die "could not install Node 24"
  [[ "$(node --version)" == v24.* ]] || die "expected Node 24, got $(node --version)"
  mark_changed "installed Node 24"
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `tests/run`
Expected: shellcheck is clean and `every dnf.txt entry resolves` passes. If
it prints `unresolved: <name>`, find the current name with
`dnf5 repoquery '*<name>*'` in a `fedora:44` container with the same repos,
fix the list, and rerun.

- [ ] **Step 7: Commit**

```bash
git add lib/repos.sh lib/packages.sh lists/dnf.txt tests/lists.bats
git commit -m "Add the repositories, the dnf list and a test that resolves every entry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Tools outside dnf (Homebrew, GitHub releases, Cursor, Claude Code) and Flatpak

**Files:**
- Create: `lib/tools.sh`, `lib/flatpak.sh`, `lists/brew.txt`,
  `lists/flatpak.txt`, `tests/tools.bats`

**Interfaces:**
- Consumes: Task 1 helpers.
- Produces:
  - `install_brew` and `install_brew_list FILE`;
  - `install_github_tools`, which installs `pass-cli`, `pay-respects` and
    the JetBrainsMono Nerd Font;
  - `install_cursor` and `install_claude`;
  - `install_flatpak_list FILE`;
  - `want_version BIN EXPECTED`, which returns 0 if `BIN --version` contains
    EXPECTED.

- [ ] **Step 1: Write the lists**

`lists/brew.txt`:
```
direnv
gh
git-filter-repo
git-lfs
kubernetes-cli
herdr
rtk
superfile
```

`lists/flatpak.txt` (Okular, Gwenview, KCalc and Filelight ship with Fedora
KDE):
```
com.github.tchx84.Flatseal
io.github.DenysMb.Kontainer
io.github.flattool.Warehouse
io.github.kolunmi.Bazaar
org.kde.haruna
org.localsend.localsend_app
```

- [ ] **Step 2: Write the failing test**

```bash
# tests/tools.bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/tools.sh"
}

@test "want_version matches a binary's reported version" {
  bin="$BATS_TEST_TMPDIR/fake"; printf '#!/bin/sh\necho "fake 1.2.3"\n' > "$bin"; chmod +x "$bin"
  run want_version "$bin" 1.2.3
  [ "$status" -eq 0 ]
  run want_version "$bin" 9.9.9
  [ "$status" -ne 0 ]
}

@test "want_version fails for a missing binary" {
  run want_version /nonexistent 1.0
  [ "$status" -ne 0 ]
}

@test "every pinned version has a checksum" {
  [ -n "$PASS_CLI_VERSION" ] && [ ${#PASS_CLI_SHA256} -eq 64 ]
  [ -n "$PAY_RESPECTS_VERSION" ] && [ ${#PAY_RESPECTS_SHA256} -eq 64 ]
  [ -n "$NERDFONT_VERSION" ] && [ ${#NERDFONT_SHA256} -eq 64 ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `tests/run`
Expected: FAIL, because `lib/tools.sh` is missing.

- [ ] **Step 4: Get the checksums**

Run these. Each prints a 64-character hash for Step 5:

```bash
curl -fsSL https://github.com/protonpass/pass-cli/releases/download/2.2.3/pass-cli-linux-x86_64.sha256 | cut -d' ' -f1
curl -fsSL -o /tmp/pr.rpm https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.x86_64.rpm && sha256sum /tmp/pr.rpm | cut -d' ' -f1
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/SHA-256.txt | grep ' JetBrainsMono.zip$' | cut -d' ' -f1
```

- [ ] **Step 5: Implement `lib/tools.sh`**

Paste the three hashes printed by Step 4 into the `*_SHA256` variables.
The test in Step 2 fails until all three are 64 characters long.

```bash
#!/usr/bin/env bash
# lib/tools.sh - programs that are not in any dnf repo. Versions pinned here.

PASS_CLI_VERSION="2.2.3"
PASS_CLI_SHA256=""        # Step 4, first command
PAY_RESPECTS_VERSION="0.8.8"
PAY_RESPECTS_SHA256=""    # Step 4, second command
NERDFONT_VERSION="v3.4.0"
NERDFONT_SHA256=""        # Step 4, third command
BREW=/home/linuxbrew/.linuxbrew/bin/brew

# want_version BIN EXPECTED
want_version() { command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | grep -qF "$2"; }

install_brew() {
  if [[ -x "$BREW" ]]; then mark_ok "Homebrew"; return; fi
  local t; t=$(mktemp)
  retry fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh "$t" || die "could not download the Homebrew installer"
  NONINTERACTIVE=1 bash "$t" || die "Homebrew install failed"
  rm -f "$t"
  mark_changed "installed Homebrew"
}

install_brew_list() {
  local -a want missing
  mapfile -t want < <(read_list "$1")
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${want[@]}" | sort) <("$BREW" list --formula -1 | sort))
  if (( ${#missing[@]} == 0 )); then mark_ok "brew formulae (${#want[@]})"; return; fi
  retry "$BREW" install "${missing[@]}" || die "brew could not install: ${missing[*]}"
  mark_changed "brew installed: ${missing[*]}"
}

install_github_tools() {
  local d; d=$(mktemp -d)
  if want_version /usr/local/bin/pass-cli "$PASS_CLI_VERSION"; then mark_ok "pass-cli"; else
    retry fetch "https://github.com/protonpass/pass-cli/releases/download/$PASS_CLI_VERSION/pass-cli-linux-x86_64" "$d/pass-cli" || die "pass-cli download failed"
    verify_sha256 "$d/pass-cli" "$PASS_CLI_SHA256" || die "pass-cli checksum mismatch"
    sudo install -m 0755 "$d/pass-cli" /usr/local/bin/pass-cli
    mark_changed "installed pass-cli $PASS_CLI_VERSION"
  fi
  if want_version pay-respects "$PAY_RESPECTS_VERSION"; then mark_ok "pay-respects"; else
    retry fetch "https://github.com/iffse/pay-respects/releases/download/v$PAY_RESPECTS_VERSION/pay-respects-$PAY_RESPECTS_VERSION-1.x86_64.rpm" "$d/pr.rpm" || die "pay-respects download failed"
    verify_sha256 "$d/pr.rpm" "$PAY_RESPECTS_SHA256" || die "pay-respects checksum mismatch"
    retry sudo dnf5 -y install --nogpgcheck "$d/pr.rpm" || die "pay-respects install failed"
    mark_changed "installed pay-respects $PAY_RESPECTS_VERSION"
  fi
  if [[ -f /usr/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf ]]; then mark_ok "JetBrainsMono Nerd Font"; else
    retry fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERDFONT_VERSION/JetBrainsMono.zip" "$d/jb.zip" || die "Nerd Font download failed"
    verify_sha256 "$d/jb.zip" "$NERDFONT_SHA256" || die "Nerd Font checksum mismatch"
    sudo mkdir -p /usr/share/fonts/JetBrainsMonoNerdFont
    sudo unzip -q -j -o "$d/jb.zip" JetBrainsMonoNerdFont-{Regular,Italic,Bold,BoldItalic}.ttf -d /usr/share/fonts/JetBrainsMonoNerdFont
    sudo fc-cache -f >/dev/null
    mark_changed "installed JetBrainsMono Nerd Font $NERDFONT_VERSION"
  fi
  rm -rf "$d"
}

install_cursor() {
  if rpm -q cursor >/dev/null 2>&1; then mark_ok "Cursor"; return; fi
  local url t; t=$(mktemp --suffix=.rpm)
  url=$(curl -fsS "${CURL_RETRY[@]}" "https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable" | jq -r .rpmUrl)
  [[ -n "$url" && "$url" != null ]] || die "could not resolve the Cursor RPM URL"
  retry fetch "$url" "$t" || die "Cursor download failed"
  retry sudo dnf5 -y install "$t" || die "Cursor install failed"
  rm -f "$t"
  mark_changed "installed Cursor"
}

install_claude() {
  if [[ -x "$HOME/.local/bin/claude" ]]; then mark_ok "Claude Code"; return; fi
  local t; t=$(mktemp)
  retry fetch https://claude.ai/install.sh "$t" || die "could not download the Claude Code installer"
  bash "$t" || die "Claude Code install failed"
  rm -f "$t"
  mark_changed "installed Claude Code"
}
```

`lib/flatpak.sh`:

```bash
#!/usr/bin/env bash
# lib/flatpak.sh
install_flatpak_list() {
  flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  local -a want missing
  mapfile -t want < <(read_list "$1")
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${want[@]}" | sort) <(flatpak list --app --columns=application | sort))
  if (( ${#missing[@]} == 0 )); then mark_ok "flatpaks (${#want[@]})"; return; fi
  retry flatpak install -y --user --noninteractive flathub "${missing[@]}" || die "flatpak could not install: ${missing[*]}"
  mark_changed "flatpak installed: ${missing[*]}"
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `tests/run`
Expected: shellcheck is clean, and the 3 `tools.bats` tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/tools.sh lib/flatpak.sh lists/brew.txt lists/flatpak.txt tests/tools.bats
git commit -m "Install Homebrew, pinned GitHub tools, Cursor, Claude Code and Flatpaks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: System files, services, CIFS mount, T480s battery and dotfiles

**Files:**
- Create: `lib/system.sh`, `lib/t480s.sh`, `lib/dotfiles.sh`
- Create: `system/common/usr/lib/udev/rules.d/91-dms-input-uaccess.rules`
  and `system/common/etc/profile.d/brew.sh`, copied verbatim from the
  penguinos repo's `system_files/`.
- Create: `system/common/etc/fonts/conf.d/90-penguinos-font-defaults.conf`,
  copied verbatim from the heredoc in penguinos `build_files/build.sh`.
- Create:
  `system/t480s/etc/udev/hwdb.d/61-battery-local.hwdb` and
  `system/t480s/etc/udev/rules.d/85-battery-thresholds.rules`, copied from
  the laptop's `/etc`.
- Test: `tests/t480s.bats`, `tests/dotfiles.bats`, `tests/system.bats`

**Interfaces:**
- Consumes: Task 1 helpers, and `$REPO` (repo root, exported by
  `install.sh`).
- Produces:
  - `enable_services`;
  - `install_system_files DIR`, which mirrors DIR's tree under
    `${ROOT:-}/` and records a change only when a file differs;
  - `add_cifs_mount`;
  - `recolor_papirus`;
  - `is_t480s` and `apply_battery_thresholds`;
  - `require_pass_cli` and `apply_dotfiles`.
  - Test overrides: `DMI_PRODUCT_FILE`, `FSTAB` and `CIFS_MOUNTPOINT`.

- [ ] **Step 1: Write the failing tests**

```bash
# tests/t480s.bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  source "$BATS_TEST_DIRNAME/../lib/t480s.sh"
}

@test "is_t480s is true on the T480s" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "ThinkPad T480s" > "$DMI_PRODUCT_FILE"
  run is_t480s; [ "$status" -eq 0 ]
}

@test "on a VM, is_t480s is false and the battery step is skipped without failing" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "pc-q35-9.0" > "$DMI_PRODUCT_FILE"
  run is_t480s; [ "$status" -ne 0 ]
  run apply_battery_thresholds; [ "$status" -eq 0 ]; [[ "$output" == *"not a T480s"* ]]
}
```

```bash
# tests/dotfiles.bats
setup() { source "$BATS_TEST_DIRNAME/../lib/common.sh"; source "$BATS_TEST_DIRNAME/../lib/dotfiles.sh"; }

@test "require_pass_cli stops with the login command when pass-cli is logged out" {
  pass-cli() { return 1; }
  run require_pass_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"pass-cli login"* ]]
}

@test "require_pass_cli passes when pass-cli info works" {
  pass-cli() { return 0; }
  run require_pass_cli
  [ "$status" -eq 0 ]
}
```

```bash
# tests/system.bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  sudo() { "$@"; }
  restorecon() { :; }
}

@test "add_cifs_mount appends the line once" {
  FSTAB="$BATS_TEST_TMPDIR/fstab"; : > "$FSTAB"; CIFS_MOUNTPOINT="$BATS_TEST_TMPDIR/mnt"
  add_cifs_mount; add_cifs_mount
  [ "$(grep -c '//<ha-host>/config' "$FSTAB")" -eq 1 ]
}

@test "install_system_files copies once and then reports nothing" {
  src="$BATS_TEST_TMPDIR/src"; ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$src/etc/x"; echo a > "$src/etc/x/f.conf"
  install_system_files "$src"
  [ "$(cat "$ROOT/etc/x/f.conf")" = a ]
  [ "${#CHANGED[@]}" -eq 1 ]
  CHANGED=(); install_system_files "$src"
  [ "${#CHANGED[@]}" -eq 0 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run`
Expected: FAIL, because the libraries are missing.

- [ ] **Step 3: Implement `lib/system.sh`**

```bash
#!/usr/bin/env bash
# lib/system.sh - services and files under /.

CIFS_LINE='//<ha-host>/config /mnt/homeassistant cifs credentials=/home/icenoir/.smbcredentials-ha,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,vers=3.0,x-systemd.automount,_netdev 0 0'

# install_system_files DIR - mirror DIR's tree under ${ROOT:-}/, recording each changed file.
install_system_files() {
  local src dst
  while IFS= read -r -d '' src; do
    dst="${ROOT:-}${src#"$1"}"
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
      sudo install -D -m 0644 "$src" "$dst"
      sudo restorecon "$dst" 2>/dev/null || true
      mark_changed "wrote $dst"
    fi
  done < <(find "$1" -type f -print0)
}

enable_services() {
  local u
  for u in sshd libvirtd podman.socket dnf5-automatic.timer; do
    if systemctl is-enabled -q "$u" 2>/dev/null; then mark_ok "$u enabled"; else
      sudo systemctl enable --now "$u" && mark_changed "enabled $u"
    fi
  done
  if [[ ! -f /etc/dnf/automatic.conf ]] || ! grep -q '^apply_updates = yes' /etc/dnf/automatic.conf; then
    sudo cp -n /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
    sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
    mark_changed "dnf5-automatic applies updates"
  fi
  if ! id -nG "$USER" | grep -qw libvirt; then sudo usermod -aG libvirt "$USER"; mark_changed "added $USER to libvirt"; fi
  if ! systemctl is-enabled -q netbird 2>/dev/null; then
    sudo netbird service install 2>/dev/null || true
    sudo systemctl enable --now netbird && mark_changed "enabled netbird"
  fi
}

add_cifs_mount() {
  local fstab=${FSTAB:-/etc/fstab}
  if grep -qF '//<ha-host>/config' "$fstab"; then mark_ok "Home Assistant CIFS mount"; return; fi
  sudo mkdir -p "${CIFS_MOUNTPOINT:-/mnt/homeassistant}"
  printf '%s\n' "$CIFS_LINE" | sudo tee -a "$fstab" >/dev/null
  if [[ "$fstab" == /etc/fstab ]]; then sudo systemctl daemon-reload; fi
  mark_changed "added Home Assistant CIFS mount"
}

# Lives here rather than in dotfiles: it rewrites /usr/share/icons, so it needs root.
recolor_papirus() {
  if [[ -f /usr/share/icons/Papirus/.cat-mocha-peach ]]; then mark_ok "Papirus recolour"; return; fi
  local d; d=$(mktemp -d)
  retry git clone -q --depth 1 https://github.com/catppuccin/papirus-folders.git "$d/src" || die "could not clone catppuccin/papirus-folders"
  sudo cp -rf "$d"/src/src/* /usr/share/icons/Papirus/
  retry fetch https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v1.14.0/papirus-folders "$d/pf" || die "papirus-folders download failed"
  sudo install -m 0755 "$d/pf" /usr/local/bin/papirus-folders
  sudo /usr/local/bin/papirus-folders -C cat-mocha-peach --theme Papirus-Dark
  sudo touch /usr/share/icons/Papirus/.cat-mocha-peach
  rm -rf "$d"
  mark_changed "recoloured Papirus folders"
}
```

- [ ] **Step 4: Implement `lib/t480s.sh`**

```bash
#!/usr/bin/env bash
# lib/t480s.sh - settings that only make sense on the ThinkPad T480s.
is_t480s() { [[ "$(cat "${DMI_PRODUCT_FILE:-/sys/class/dmi/id/product_version}" 2>/dev/null)" == "ThinkPad T480s" ]]; }

apply_battery_thresholds() {
  if ! is_t480s; then log "not a T480s: skipping battery thresholds"; return 0; fi
  install_system_files "$REPO/system/t480s"
  sudo systemd-hwdb update
  sudo udevadm trigger --subsystem-match=power_supply
  sudo busctl call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT0 \
    org.freedesktop.UPower.Device EnableChargeThreshold b true >/dev/null || warn "UPower EnableChargeThreshold failed"
  [[ "$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)" == 85 ]] || warn "battery end threshold is not 85"
}
```

- [ ] **Step 5: Implement `lib/dotfiles.sh`**

```bash
#!/usr/bin/env bash
# lib/dotfiles.sh
export PROTON_PASS_LINUX_KEYRING=dbus

require_pass_cli() {
  pass-cli info >/dev/null 2>&1 && return 0
  warn "pass-cli is not logged in, and chezmoi needs it for ~/.ssh/id_ed25519."
  warn "Run:  PROTON_PASS_LINUX_KEYRING=dbus pass-cli login   then rerun ./install.sh"
  return 1
}

apply_dotfiles() {
  require_pass_cli || exit 2
  if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
    retry chezmoi update --apply && mark_ok "dotfiles (updated)"
  else
    retry chezmoi init --apply privatepenguinzero/dotfiles && mark_changed "applied dotfiles"
  fi
}
```

- [ ] **Step 6: Copy the system files**

```bash
P=~/personale/penguinos
install -D -m 0644 $P/system_files/usr/lib/udev/rules.d/91-dms-input-uaccess.rules system/common/usr/lib/udev/rules.d/91-dms-input-uaccess.rules
install -D -m 0644 $P/system_files/etc/profile.d/brew.sh system/common/etc/profile.d/brew.sh
install -D -m 0644 /etc/fonts/conf.d/90-penguinos-font-defaults.conf system/common/etc/fonts/conf.d/90-penguinos-font-defaults.conf
install -D -m 0644 /etc/udev/hwdb.d/61-battery-local.hwdb system/t480s/etc/udev/hwdb.d/61-battery-local.hwdb
install -D -m 0644 /etc/udev/rules.d/85-battery-thresholds.rules system/t480s/etc/udev/rules.d/85-battery-thresholds.rules
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `tests/run`
Expected: shellcheck is clean, and all `t480s`, `dotfiles` and `system`
tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/system.sh lib/t480s.sh lib/dotfiles.sh system tests/t480s.bats tests/dotfiles.bats tests/system.bats
git commit -m "Add services, system files, the CIFS mount, T480s battery and dotfiles steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `migrate-home-paths`

**Files:**
- Create: `bin/migrate-home-paths`, `tests/migrate.bats`

**Interfaces:**
- Produces: `bin/migrate-home-paths [OLD NEW]`, with defaults
  `/var/home/icenoir` and `/home/icenoir`. It works under `CLAUDE_DIR`
  (default `$HOME/.claude`) and `CLAUDE_JSON` (default `$HOME/.claude.json`).
  Exit codes: 0 when migrated or when there is nothing to do, 3 when it
  refuses.

- [ ] **Step 1: Write the failing tests**

```bash
# tests/migrate.bats
M="$BATS_TEST_DIRNAME/../bin/migrate-home-paths"
setup() {
  export CLAUDE_DIR="$BATS_TEST_TMPDIR/claude" CLAUDE_JSON="$BATS_TEST_TMPDIR/claude.json"
  mkdir -p "$CLAUDE_DIR/projects/-var-home-icenoir/memory" "$CLAUDE_DIR/projects/-var-home-icenoir-personale-x"
  echo note > "$CLAUDE_DIR/projects/-var-home-icenoir/memory/a.md"
  echo '{"projects":{"/var/home/icenoir":{},"/var/home/icenoir/personale/x":{}}}' > "$CLAUDE_JSON"
  echo '{"note":"/var/home/icenoir/coding"}' > "$CLAUDE_DIR/settings.json"
}

@test "renames project dirs and rewrites json paths" {
  run "$M"; [ "$status" -eq 0 ]
  [ -f "$CLAUDE_DIR/projects/-home-icenoir/memory/a.md" ]
  [ -d "$CLAUDE_DIR/projects/-home-icenoir-personale-x" ]
  [ ! -e "$CLAUDE_DIR/projects/-var-home-icenoir" ]
  grep -q '"/home/icenoir/personale/x"' "$CLAUDE_JSON"
  ! grep -q /var/home "$CLAUDE_JSON" "$CLAUDE_DIR/settings.json"
  [ -f "$CLAUDE_JSON.pre-migration" ]
}

@test "second run is a no-op" {
  "$M"; run "$M"; [ "$status" -eq 0 ]; [[ "$output" == *"nothing to migrate"* ]]
}

@test "refuses when a target dir already exists, and changes nothing" {
  mkdir -p "$CLAUDE_DIR/projects/-home-icenoir"
  run "$M"; [ "$status" -eq 3 ]
  [ -d "$CLAUDE_DIR/projects/-var-home-icenoir" ]
  grep -q /var/home "$CLAUDE_JSON"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run`
Expected: FAIL, because `bin/migrate-home-paths` does not exist.

- [ ] **Step 3: Implement**

```bash
#!/usr/bin/env bash
# bin/migrate-home-paths - one-shot rename of Claude Code state after the home
# moves from /var/home/icenoir to /home/icenoir. Claude keys per-project state
# by path, so without this the conversations and the memory disappear.
set -euo pipefail
old=${1:-/var/home/icenoir} new=${2:-/home/icenoir}
cdir=${CLAUDE_DIR:-$HOME/.claude} cjson=${CLAUDE_JSON:-$HOME/.claude.json}
okey=${old//\//-} nkey=${new//\//-}

shopt -s nullglob
existing=()
for d in "$cdir/projects/$okey" "$cdir/projects/$okey"-*; do [[ -e "$d" ]] && existing+=("$d"); done
files=()
for f in "$cjson" "$cdir/settings.json"; do [[ -f "$f" ]] && grep -qF "$old" "$f" && files+=("$f"); done

if (( ${#existing[@]} == 0 && ${#files[@]} == 0 )); then echo "nothing to migrate"; exit 0; fi

for d in "${existing[@]}"; do
  t="$cdir/projects/$nkey${d#"$cdir/projects/$okey"}"
  if [[ -e "$t" ]]; then echo "refusing: $t already exists" >&2; exit 3; fi
done

for d in "${existing[@]}"; do mv "$d" "$cdir/projects/$nkey${d#"$cdir/projects/$okey"}"; done
for f in "${files[@]}"; do cp -p "$f" "$f.pre-migration"; sed -i "s#$old#$new#g" "$f"; done
echo "migrated ${#existing[@]} project dirs and ${#files[@]} files"
```

Run: `chmod +x bin/migrate-home-paths`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `tests/run`
Expected: all 3 `migrate` tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/migrate-home-paths tests/migrate.bats
git commit -m "Add the one-shot migration of Claude state from /var/home to /home

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `install.sh` and README

**Files:**
- Create: `install.sh`, `tests/preflight.bats`
- Modify: `README.md` (full rewrite)

**Interfaces:**
- Consumes: every function from Tasks 1 to 5.
- Produces: `./install.sh`. Exit codes: 0 on success, 1 on error, 2 when
  waiting for `pass-cli login`. Env `OS_RELEASE` (default `/etc/os-release`),
  for tests.

- [ ] **Step 1: Write the failing test**

```bash
# tests/preflight.bats
@test "refuses a non-KDE Fedora" {
  f="$BATS_TEST_TMPDIR/os"; printf 'ID=fedora\nVARIANT_ID=workstation\n' > "$f"
  OS_RELEASE="$f" run "$BATS_TEST_DIRNAME/../install.sh" --preflight-only
  [ "$status" -eq 1 ]; [[ "$output" == *"Fedora KDE"* ]]
}

@test "accepts Fedora KDE" {
  f="$BATS_TEST_TMPDIR/os"; printf 'ID=fedora\nVARIANT_ID=kde\n' > "$f"
  OS_RELEASE="$f" run "$BATS_TEST_DIRNAME/../install.sh" --preflight-only
  [ "$status" -eq 0 ]
}
```

The bats container runs as root, so `--preflight-only` skips the not-root
check. That check is covered by the rehearsal instead.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/run`
Expected: FAIL, because `install.sh` does not exist.

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
# install.sh - turn a fresh Fedora KDE install into the full desktop. Safe to rerun.
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
export REPO
for lib in common repos packages tools flatpak system dotfiles t480s; do
  # shellcheck source=/dev/null
  source "$REPO/lib/$lib.sh"
done

check_os() {
  # shellcheck source=/dev/null
  . "${OS_RELEASE:-/etc/os-release}"
  [[ "${ID:-}" == fedora && "${VARIANT_ID:-}" == kde ]] || die "this script targets Fedora KDE (found ${ID:-?}/${VARIANT_ID:-?})"
}

if [[ "${1:-}" == --preflight-only ]]; then check_os; exit 0; fi
check_os
[[ $EUID -ne 0 ]] || die "run as your user, not root"
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

log "1/8 dnf and repositories"; setup_dnf
log "2/8 system packages";      install_dnf_list "$REPO/lists/dnf.txt"; install_codecs; install_node24
log "3/8 tools outside dnf";    install_brew; install_brew_list "$REPO/lists/brew.txt"; install_github_tools; install_cursor; install_claude
log "4/8 flatpaks";             install_flatpak_list "$REPO/lists/flatpak.txt"
log "5/8 services and system";  install_system_files "$REPO/system/common"; enable_services; add_cifs_mount; recolor_papirus
log "6/8 home path migration"
if out=$("$REPO/bin/migrate-home-paths"); then
  [[ "$out" == "nothing to migrate" ]] && mark_ok "Claude paths" || mark_changed "$out"
else
  die "migrate-home-paths refused; see the message above"
fi
if [[ ! -e /var/home ]]; then sudo ln -s /home /var/home; mark_changed "linked /var/home -> /home"; fi
log "7/8 dotfiles";             apply_dotfiles
log "8/8 machine-specific";     apply_battery_thresholds
summary
```

Run: `chmod +x install.sh`

- [ ] **Step 4: Rewrite `README.md`**

Write it in plain language. It needs four sections:

1. **What this is.** One paragraph.
2. **Fresh install.** Install Fedora KDE, then:
   `git clone https://github.com/privatepenguinzero/installer && cd installer && ./install.sh`.
   When it stops with exit code 2, run
   `PROTON_PASS_LINUX_KEYRING=dbus pass-cli login` and then `./install.sh`
   again.
3. **Adding a program.** Add a line to the matching `lists/*.txt` file and
   rerun the script.
4. **Laptop migration runbook.** Tasks 8 to 10 of this plan, condensed into
   a numbered checklist.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `tests/run`
Expected: everything passes, and shellcheck is clean on `install.sh`.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/preflight.bats README.md
git commit -m "Add install.sh and the README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Dotfiles additions (repo `privatepenguinzero/dotfiles`)

**Files** (in `~/.local/share/chezmoi`):
- Create: `.chezmoiexternal.toml`
- Add with `chezmoi add`: `~/.config/{nvim,btop,bat,mc/ini,superfile}`,
  `~/.config/git/catppuccin.gitconfig`, `~/.local/share/mc/skins`, `~/.zsh`,
  `~/.config/herdr/config.toml`, `~/.config/gtk-{3,4}.0/settings.ini`,
  `~/.ssh/config`, `~/.ssh/authorized_keys`, and the Claude files from
  Step 3.
- Modify: `.chezmoiignore`

**Interfaces:** none. The deliverable is
`chezmoi diff --exclude=templates` being empty on the current laptop.

- [ ] **Step 1: Add the user-level files penguinos put in `/etc/skel`**

```bash
cd ~ && for p in ~/.config/nvim ~/.config/btop ~/.config/bat ~/.config/git/catppuccin.gitconfig \
  ~/.local/share/mc/skins ~/.config/mc/ini ~/.zsh ~/.config/superfile ~/.config/herdr/config.toml \
  ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini ~/.ssh/config ~/.ssh/authorized_keys; do
  [[ -e $p ]] && chezmoi add "$p" || echo "MISSING $p"
done
```

Expected: no `MISSING` lines. If one appears, recreate that file from the
matching penguinos `build.sh` section (heredoc or download URL), then add it.

- [ ] **Step 2: oh-my-zsh, its plugins and the cursors as externals**

`.chezmoiexternal.toml`:
```toml
[".oh-my-zsh"]
    type = "git-repo"
    url = "https://github.com/ohmyzsh/ohmyzsh.git"
    refreshPeriod = "168h"
[".oh-my-zsh/custom/plugins/zsh-autosuggestions"]
    type = "git-repo"
    url = "https://github.com/zsh-users/zsh-autosuggestions.git"
    refreshPeriod = "168h"
[".oh-my-zsh/custom/plugins/zsh-autocomplete"]
    type = "git-repo"
    url = "https://github.com/marlonrichert/zsh-autocomplete.git"
    refreshPeriod = "168h"
[".oh-my-zsh/custom/plugins/zsh-history-substring-search"]
    type = "git-repo"
    url = "https://github.com/zsh-users/zsh-history-substring-search.git"
    refreshPeriod = "168h"
[".oh-my-zsh/custom/plugins/zsh-syntax-highlighting"]
    type = "git-repo"
    url = "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    refreshPeriod = "168h"
[".local/share/icons/catppuccin-mocha-peach-cursors"]
    type = "archive"
    url = "https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-peach-cursors.zip"
    stripComponents = 1
```

The existing `~/.oh-my-zsh` came from `/etc/skel`. If it is not a git
checkout (`git -C ~/.oh-my-zsh status` fails), move it aside before applying:
`mv ~/.oh-my-zsh ~/.oh-my-zsh.pre-chezmoi && chezmoi apply ~/.oh-my-zsh`.
Then open a new shell and confirm the prompt and the plugins work.

- [ ] **Step 3: Claude Code config**

```bash
cd ~ && chezmoi add ~/.claude/CLAUDE.md ~/.claude/RTK.md ~/.claude/settings.json ~/.claude/scripts \
  ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json \
  ~/.claude/projects/-var-home-icenoir/memory ~/.local/bin/claude-sync-work
for d in ~/.claude/skills/* ~/.claude/agents/* ~/.claude/hooks/*; do
  case "$(basename "$d")" in gsd-*|synced) ;; *) chezmoi add "$d" ;; esac
done
```

Add to `.chezmoiignore`, so later GSD and plugin installs do not show up as
drift:
```
.claude/skills/gsd-*
.claude/skills/synced
.claude/agents/gsd-*
.claude/hooks/gsd-*
```

The memory is added under `-var-home-icenoir/`. Task 10 Step 6 moves it to
`-home-icenoir/` in the source state after the migration.

- [ ] **Step 4: Scan for secrets, then verify**

```bash
cd ~/.local/share/chezmoi && git add -A && git diff --cached | grep -nEi '(sk-ant-|ghp_|github_pat_|-----BEGIN [A-Z ]*PRIVATE KEY|"(api[_-]?key|token|secret|password)"\s*:\s*"[^"]{8,})' || echo "no secrets"
chezmoi diff --exclude=templates
```

Expected: `no secrets`, then an empty diff. If the scan matches, unstage
that file (`git restore --staged <file>`), `chezmoi forget` it, and tell the
user.

- [ ] **Step 5: Commit (no push until the user says so)**

```bash
git commit -m "Track the shell, theme, SSH and Claude Code config that penguinos used to seed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Kickstart template and renderer

**Files:**
- Create: `install/t480s.ks.in`, `install/render-ks`, `tests/ks.bats`
- Modify: `.gitignore` (add `*.ks`)

**Interfaces:**
- Produces: `install/render-ks OUT`, which writes the rendered kickstart to
  OUT with mode 600. Env: `KS_PASSWORD` (default `icenoir`), and `KS_DISK`
  (default `nvme0n1`; the rehearsal VM uses `sda`).

- [ ] **Step 1: Write the failing test**

```bash
# tests/ks.bats
@test "rendered kickstart validates and contains no placeholders or plaintext password" {
  out="$BATS_TEST_TMPDIR/t.ks"
  "$BATS_TEST_DIRNAME/../install/render-ks" "$out"
  ! grep -q '@[A-Z_]*@' "$out"
  ! grep -E '^(rootpw|user)' "$out" | grep -qE '(password=|rootpw --iscrypted )icenoir( |$)'
  run podman run --rm -v "$out:/t.ks:ro,Z" registry.fedoraproject.org/fedora:44 \
    bash -c 'dnf -yq install pykickstart >/dev/null && ksvalidator -v F44 /t.ks'
  echo "$output"; [ "$status" -eq 0 ]
}
```

This file is listed in `PODMAN_TESTS` in `tests/run` (Task 1), so it runs
in the podman-in-podman container.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/run`
Expected: FAIL, because `render-ks` is missing.

- [ ] **Step 3: Write `install/t480s.ks.in`**

```
# Fedora 44 KDE, unattended, keeps the btrfs "home" subvolume. Rendered by install/render-ks.
text
lang en_US.UTF-8
keyboard --vckeymap=it --xlayouts=it
timezone Europe/Rome --utc
network --bootproto=dhcp --device=link --activate --hostname=thinkpad
url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64"
repo --name=updates --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f44&arch=x86_64"
rootpw --iscrypted @ROOT_HASH@
user --name=icenoir --uid=1000 --gid=1000 --groups=wheel --homedir=/home/icenoir --iscrypted --password=@USER_HASH@
firstboot --disable
selinux --enforcing
services --enabled=sshd
ignoredisk --only-use=@DISK@
bootloader --boot-drive=@DISK@
part /boot/efi --onpart=@PART@1 --fstype=efi
part /boot --onpart=@PART@2 --fstype=ext4 --label=fedora_boot
part btrfs.01 --onpart=@PART@3 --noformat
btrfs none --noformat --label=fedora btrfs.01
btrfs / --subvol --name=root LABEL=fedora
btrfs /home --subvol --name=home --noformat LABEL=fedora
reboot

%pre --log=/tmp/ks-pre.log
set -e
mkdir -p /mnt/p3
mount /dev/@PART@3 /mnt/p3
if [ -d /mnt/p3/root ] && [ ! -e /mnt/p3/ostree-old ]; then mv /mnt/p3/root /mnt/p3/ostree-old; fi
umount /mnt/p3
btrfs filesystem label /dev/@PART@3 fedora
%end

%packages
@^kde-desktop-environment
git
%end

%post --log=/root/ks-post.log
set -e
install -d -m 0755 /etc/ssh/sshd_config.d
printf 'PermitRootLogin no\nPasswordAuthentication no\n' > /etc/ssh/sshd_config.d/10-key-only.conf
restorecon -R /home
[ -e /var/home ] || ln -s /home /var/home
if [ ! -d /home/icenoir/installer ]; then
  runuser -u icenoir -- git clone -q https://github.com/privatepenguinzero/installer /home/icenoir/installer
fi
%end
```

`@PART@` becomes `nvme0n1p` for an NVMe disk, or `sda` for a SCSI/virtio
disk. `render-ks` derives it from `KS_DISK`.

- [ ] **Step 4: Write `install/render-ks`**

```bash
#!/usr/bin/env bash
# install/render-ks OUT - fill the kickstart template. Output holds password
# hashes: never commit it (this repo is public).
set -euo pipefail
out=${1:?usage: render-ks OUT}
disk=${KS_DISK:-nvme0n1}
if [[ $disk == nvme* ]]; then part="${disk}p"; else part="$disk"; fi
hash=$(openssl passwd -6 "${KS_PASSWORD:-icenoir}")
umask 077
sed -e "s|@ROOT_HASH@|$hash|" -e "s|@USER_HASH@|$hash|" -e "s|@DISK@|$disk|g" -e "s|@PART@|$part|g" \
  "$(dirname "$0")/t480s.ks.in" > "$out"
echo "wrote $out"
```

Run: `chmod +x install/render-ks && echo '*.ks' >> .gitignore`

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/run`
Expected: `ks.bats` passes, with no ksvalidator errors. If ksvalidator
rejects a btrfs line, compare it against the pykickstart btrfs command
reference (`ksvalidator` prints the accepted options), adjust, and rerun.
The rehearsal in Task 9 is the final judge of the disk layout.

- [ ] **Step 6: Commit**

```bash
git add install/t480s.ks.in install/render-ks tests/ks.bats .gitignore
git commit -m "Add the kickstart template that keeps the home subvolume

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Netboot hook and rehearsal on a Proxmox VM

**Files:**
- Create: `install/netboot-hook`

**Interfaces:**
- Produces: `install/netboot-hook enable MAC KS_URL` and
  `install/netboot-hook disable`. The script runs on the driving machine and
  reaches LXC 107 through `ssh root@<pve-host> pct exec 107`. It edits
  `config/menus/local-vars.ipxe`, adding a block between the markers
  `# BEGIN t480s-install` and `# END t480s-install`, and backs up the
  original file to `local-vars.ipxe.orig` the first time.

- [ ] **Step 1: Write `install/netboot-hook`**

```bash
#!/usr/bin/env bash
# install/netboot-hook enable MAC KS_URL | disable
# MAC-gated chain on the homelab netboot.xyz: only that NIC boots straight into
# the Fedora installer; every other machine still gets the normal menu.
set -euo pipefail
PVE=root@<pve-host> CT=107 F=/opt/stacks/netbootxyz/config/menus/local-vars.ipxe
FED=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os
remote() { ssh -o BatchMode=yes "$PVE" "pct exec $CT -- sh -c $(printf '%q' "$1")"; }

case "${1:-}" in
  enable)
    mac=${2:?MAC} ks=${3:?KS_URL}
    block="# BEGIN t480s-install
iseq \${netX/mac} $mac && goto t480s_install || goto t480s_end
:t480s_install
kernel $FED/images/pxeboot/vmlinuz inst.repo=$FED inst.ks=$ks inst.sshd inst.text ip=dhcp initrd=initrd.img
initrd $FED/images/pxeboot/initrd.img
boot
:t480s_end
# END t480s-install"
    remote "touch $F; [ -f $F.orig ] || cp -a $F $F.orig; sed -i '/# BEGIN t480s-install/,/# END t480s-install/d' $F"
    printf '%s\n' "$block" | ssh -o BatchMode=yes "$PVE" "pct exec $CT -- sh -c 'cat >> $F'"
    remote "grep -c 't480s-install' $F" ;;
  disable)
    remote "sed -i '/# BEGIN t480s-install/,/# END t480s-install/d' $F; ! grep -q t480s-install $F && echo hook removed" ;;
  *) echo "usage: $0 enable MAC KS_URL | disable" >&2; exit 1 ;;
esac
```

Run: `chmod +x install/netboot-hook && tests/run`
Expected: shellcheck is clean.

- [ ] **Step 2: Create the driving LXC and serve a rehearsal kickstart**

On pve-m720q, create a temporary Debian 13 LXC, CT 199, on `vmbr0` with
DHCP. Install `git openssh-client python3 openssl` in it, clone this repo,
and install Claude Code. The user logs in to Claude Code with the personal
account. Then, from CT 199:

```bash
mkdir -p /srv/ks && KS_DISK=sda install/render-ks /srv/ks/vm.ks
(cd /srv/ks && nohup python3 -m http.server 8088 >/dev/null 2>&1 &)
```

Give CT 199 SSH access to the laptop by appending its public key to the
laptop's `~/.ssh/authorized_keys` by hand. The laptop is not in the hourly
key sync.

- [ ] **Step 3: Create a rehearsal VM whose disk looks like the laptop's**

```bash
ssh root@<pve-host> 'qm create 990 --name ks-rehearsal --memory 4096 --cores 2 --machine q35 --bios ovmf \
  --efidisk0 local-lvm:1 --scsi0 local-lvm:40 --net0 virtio,bridge=vmbr0 \
  --ide2 local:iso/Fedora-KDE-Desktop-Live-44.iso,media=cdrom --boot order=ide2 && qm start 990'
```

If the ISO is not in `local:iso`, download it there first. Then, in the
live session over the Proxmox console, as root:

```bash
sgdisk -Z /dev/sda && sgdisk -n1:0:+600M -t1:ef00 -n2:0:+2G -t2:8300 -n3:0:0 -t3:8300 /dev/sda
mkfs.vfat /dev/sda1 && mkfs.ext4 -L bazzite_xboot /dev/sda2 && mkfs.btrfs -L bazzite /dev/sda3
mount /dev/sda3 /mnt && btrfs subvolume create /mnt/root && btrfs subvolume create /mnt/home
mkdir -p /mnt/home/icenoir/.ssh && echo keep-me > /mnt/home/icenoir/MARKER
cp /path/to/thinkpad.pub /mnt/home/icenoir/.ssh/authorized_keys   # the laptop's id_ed25519.pub
chown -R 1000:1000 /mnt/home/icenoir && chmod 700 /mnt/home/icenoir/.ssh && umount /mnt && poweroff
```

- [ ] **Step 4: Run the rehearsal**

```bash
mac=$(ssh root@<pve-host> qm config 990 | sed -n 's/^net0: virtio=\([^,]*\).*/\1/p' | tr 'A-Z' 'a-z')
install/netboot-hook enable "$mac" "http://$(hostname -I | cut -d' ' -f1):8088/vm.ks"
ssh root@<pve-host> 'qm set 990 --boot order="net0;scsi0" && qm start 990'
```

Find the VM's IP from the router or `qm guest cmd`, then follow the install
with `ssh root@<vm-ip>` (the installer's sshd) and `tmux attach`.
Expected: the VM boots straight into the Fedora installer with no menu,
installs, and reboots.

- [ ] **Step 5: Check the result**

```bash
ssh icenoir@<vm-ip> 'cat ~/MARKER; ls -Z ~/MARKER; sudo btrfs subvolume list /; sudo btrfs filesystem label /; ls -ld /var/home; ls -d ~/installer'
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password icenoir@<vm-ip> true; echo "password ssh rc=$?"
```

Expected:
- `keep-me`;
- an SELinux context containing `user_home_t`;
- the subvolumes `ostree-old`, `home` and `root`;
- the label `fedora`;
- `/var/home -> /home`;
- the repo present;
- `password ssh rc=255` (refused).

On the Proxmox console, `icenoir`/`icenoir` logs in.

- [ ] **Step 6: Run `install.sh` in the VM, twice**

```bash
ssh -t icenoir@<vm-ip> 'cd ~/installer && ./install.sh; echo rc=$?'
```

Expected: `rc=2` (pass-cli). The user then runs
`ssh -t icenoir@<vm-ip> 'PROTON_PASS_LINUX_KEYRING=dbus pass-cli login'`
(web flow). Then:

```bash
ssh -t icenoir@<vm-ip> 'cd ~/installer && ./install.sh && ./install.sh | tail -4 && chezmoi verify && echo verify-ok'
ssh icenoir@<vm-ip> 'for c in ghostty brave-browser claude herdr rtk netbird; do command -v $c >/dev/null && echo ok $c || echo MISSING $c; done; ffmpeg -codecs 2>/dev/null | grep -q h264 && echo ok h264'
```

Expected:
- both runs exit 0, the second prints `nothing changed`, and `verify-ok`
  appears;
- every smoke line says `ok`;
- on the Proxmox console, SDDM lists a niri session, and DMS starts in it.

- [ ] **Step 7: Clean up the rehearsal**

```bash
install/netboot-hook disable
ssh root@<pve-host> 'qm stop 990; qm destroy 990 --purge'
```

Do the pass-cli logout on the VM before destroying it:
`ssh icenoir@<vm-ip> pass-cli logout`.

- [ ] **Step 8: Commit**

```bash
git add install/netboot-hook
git commit -m "Add the MAC-gated netboot.xyz hook, rehearsed on a throwaway VM

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Backup and go-live on the T480s

**Files:**
- Create: `install/backup-home`

**Interfaces:**
- Produces: `install/backup-home DEST`. DEST is an rsync target such as
  `root@<pve-host>:/mnt/sabrent/t480s-2026-10`. The script exits non-zero
  unless the checksum dry-run finds zero differing files.

- [ ] **Step 1: Write `install/backup-home`**

```bash
#!/usr/bin/env bash
# install/backup-home DEST - full copy of the home plus machine state, then a
# checksum verification pass. Run on the laptop; sudo for the root-only bits.
set -euo pipefail
dest=${1:?usage: backup-home user@host:/path}
rsync -aHAX --info=progress2 --exclude='.cache/' /var/home/icenoir/ "$dest/home/"
sudo rsync -aHAX -e "ssh -i $HOME/.ssh/id_ed25519" /etc/NetworkManager/system-connections/ "$dest/nm/"
sudo rsync -aHAX -e "ssh -i $HOME/.ssh/id_ed25519" /var/lib/netbird/ "$dest/netbird/"
changes=$(rsync -aHAXn --checksum --exclude='.cache/' --out-format='%n' /var/home/icenoir/ "$dest/home/" | grep -vc '/$' || true)
if (( changes != 0 )); then echo "backup verification found $changes differing files" >&2; exit 1; fi
echo "backup verified"
```

Run:

```bash
chmod +x install/backup-home && tests/run && git add install/backup-home && git commit -m "Add the verified home backup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Check space on pve-m720q**

Run: `ssh root@<pve-host> 'df -h /mnt/sabrent 2>/dev/null || lsblk -f'`
Expected: at least 120 GB free on the Sabrent disk. If it has no mounted
filesystem with that much space, stop and ask the user where the backup
should go.

- [ ] **Step 3: Back up**

This step needs a terminal with a TTY for sudo, so the user runs it on the
laptop:

```bash
~/personale/installer/install/backup-home root@<pve-host>:/mnt/sabrent/t480s-2026-10
```

Expected: `backup verified`. **Stop if it is anything else.**

- [ ] **Step 4: Go**

The user is at the laptop with the cable plugged in and a Fedora KDE USB
stick at hand. From CT 199:

```bash
install/render-ks /srv/ks/t480s.ks
install/netboot-hook enable <laptop-mac> "http://$(hostname -I | cut -d' ' -f1):8088/t480s.ks"
ssh -t icenoir@<laptop-ip> 'sudo efibootmgr --bootnext 001C && sudo systemctl reboot'
```

Then `ssh root@<laptop-ip>` once the installer's sshd is up, and
`tmux attach` to watch.
Expected: the laptop boots straight into the installer, installs, and
reboots into Fedora KDE.

- [ ] **Step 5: First boot**

```bash
install/netboot-hook disable
ssh icenoir@<laptop-ip> 'grep VARIANT_ID /etc/os-release; ls ~/personale | head -3; sudo btrfs subvolume list /'
ssh -t icenoir@<laptop-ip> 'cd ~/installer && ./install.sh; echo rc=$?'
```

Expected: `rc=2`. The user runs
`PROTON_PASS_LINUX_KEYRING=dbus pass-cli login` on the laptop, then:

```bash
ssh -t icenoir@<laptop-ip> 'cd ~/installer && ./install.sh && ./install.sh | tail -4'
ssh icenoir@<laptop-ip> 'cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold'
```

Expected: `nothing changed`, then `50` and `85`.

- [ ] **Step 6: Restore machine state and fix the dotfiles memory path**

Run on the laptop, by the user, since sudo needs a TTY:

```bash
B=root@<pve-host>:/mnt/sabrent/t480s-2026-10
sudo rsync -aHAX -e "ssh -i $HOME/.ssh/id_ed25519" $B/nm/ /etc/NetworkManager/system-connections/ && sudo nmcli connection reload
sudo systemctl stop netbird && sudo rsync -aHAX -e "ssh -i $HOME/.ssh/id_ed25519" $B/netbird/ /var/lib/netbird/ && sudo systemctl start netbird && netbird status | head -3
```

Then, from CT 199 over SSH:

```bash
ssh icenoir@<laptop-ip> 'cd ~/.local/share/chezmoi && chezmoi forget --force ~/.claude/projects/-var-home-icenoir/memory; chezmoi add ~/.claude/projects/-home-icenoir/memory && git add -A && git commit -qm "Follow the home move to /home/icenoir

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && chezmoi diff --exclude=templates | wc -l'
```

Expected: Wi-Fi networks listed, NetBird `Connected`, and the diff line count
is `0`.

- [ ] **Step 7: Wrap up**

- Rerun the smoke check from Task 9 Step 6 on the laptop.
- Ask the user before each of these:
  - push `installer` and `dotfiles`;
  - in penguinos, disable the scheduled workflows (`gh workflow list`, then
    `gh workflow disable <id>` for the build and prune workflows) and
    archive the repo (`gh repo archive privatepenguinzero/penguinos`);
  - destroy CT 199.
- Remind the user to:
  - change both temporary passwords (`passwd`, `sudo passwd root`);
  - delete `ostree-old` after two weeks:
    `sudo mount /dev/nvme0n1p3 /mnt && sudo btrfs subvolume delete /mnt/ostree-old && sudo umount /mnt`.
