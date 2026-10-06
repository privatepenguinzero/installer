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
  sudo tee /etc/yum.repos.d/netbird.repo >/dev/null <<'REPO'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=0
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
REPO
  mark_changed "enabled NetBird repo"
}
