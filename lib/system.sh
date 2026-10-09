#!/usr/bin/env bash
# lib/system.sh - services and files under /.

CIFS_OPTS='credentials=/home/icenoir/.smbcredentials-ha,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,vers=3.0,x-systemd.automount,_netdev'

# install_system_files DIR - mirror DIR's tree under ${ROOT:-}/, recording each changed file.
# Files executable in the repo are installed 0755, the rest 0644.
install_system_files() {
  local src dst mode
  while IFS= read -r -d '' src; do
    dst="${ROOT:-}${src#"$1"}"
    if [[ -x "$src" ]]; then mode=0755; else mode=0644; fi
    if ! cmp -s "$src" "$dst" 2>/dev/null || [[ "$(stat -c %a "$dst")" != "${mode#0}" ]]; then
      sudo install -D -m "$mode" "$src" "$dst"
      sudo restorecon "$dst" 2>/dev/null || true
      mark_changed "wrote $dst"
    fi
  done < <(find "$1" -type f -print0)
}

enable_services() {
  local u
  for u in sshd libvirtd podman.socket dnf5-automatic.timer; do
    if systemctl is-enabled -q "$u" 2>/dev/null; then mark_ok "$u enabled"; else
      sudo systemctl enable --now "$u" || die "could not enable $u"; mark_changed "enabled $u"
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
    sudo systemctl enable --now netbird || die "could not enable netbird"; mark_changed "enabled netbird"
  fi
}

# A text-mode kickstart install leaves multi-user.target as the default, so the
# login screen never starts.
ensure_graphical_boot() {
  if [[ "$(systemctl get-default)" == graphical.target ]]; then mark_ok "graphical boot"; return; fi
  sudo systemctl set-default graphical.target >/dev/null
  mark_changed "boot target set to graphical"
}

# The kickstart user gets bash; ~/.zprofile (PROTON_PASS_LINUX_KEYRING etc.) needs a zsh login.
ensure_zsh_login() {
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == /bin/zsh ]]; then mark_ok "zsh login shell"; return; fi
  sudo usermod -s /bin/zsh "$USER"
  mark_changed "login shell set to zsh"
}

# Lynis FILE-7524: cron config readable by root only.
tighten_cron_perms() {
  local f mode changed=0
  for f in crontab cron.deny at.deny cron.hourly cron.daily cron.weekly cron.monthly cron.d; do
    f="${ROOT:-}/etc/$f"; [[ -e "$f" ]] || continue
    if [[ -d "$f" ]]; then mode=700; else mode=600; fi
    [[ "$(stat -c %a "$f")" == "$mode" ]] && continue
    sudo chmod "$mode" "$f"; changed=1
  done
  if (( changed )); then mark_changed "restricted cron permissions"; else mark_ok "cron permissions"; fi
}

# Load the hardening files that install_system_files put in place.
apply_hardening() {
  sudo sysctl -q --system
  sudo sshd -t && sudo systemctl reload sshd
}

add_cifs_mount() {
  local fstab=${FSTAB:-/etc/fstab}
  if [[ -z "${HA_SMB_HOST:-}" ]]; then
    warn "Home Assistant CIFS mount skipped: set HA_SMB_HOST in $LOCAL_ENV (dotfiles bring it; rerun)"
    return
  fi
  if grep -qF "//$HA_SMB_HOST/config" "$fstab"; then mark_ok "Home Assistant CIFS mount"; return; fi
  sudo mkdir -p "${CIFS_MOUNTPOINT:-/mnt/homeassistant}"
  printf '//%s/config /mnt/homeassistant cifs %s 0 0\n' "$HA_SMB_HOST" "$CIFS_OPTS" | sudo tee -a "$fstab" >/dev/null
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

# VNC in niri (wayvnc) and RDP in Plasma (KRDP), both logging in with the user's
# password. Neither port is open in the public zone, so they answer only on
# NetBird (wt0, trusted zone).
setup_remote_desktop() {
  local u
  for u in wayvnc.service app-org.kde.krdpserver.service; do
    if systemctl --global is-enabled -q "$u" 2>/dev/null; then mark_ok "$u enabled for all users"; else
      sudo systemctl --global enable "$u" || die "could not enable $u"; mark_changed "enabled user service $u"
    fi
  done
  if [[ "$(kreadconfig6 --file krdpserverrc --group General --key SystemUserEnabled)" == true ]]; then
    mark_ok "KRDP uses the system password"
  else
    kwriteconfig6 --file krdpserverrc --group General --key SystemUserEnabled true
    mark_changed "KRDP uses the system password"
  fi
  # Without this portal grant KRDP accepts the login but streams a black screen;
  # the System Settings page is what normally sets it.
  local ps=org.freedesktop.impl.portal.PermissionStore
  local store=(--session --dest "$ps" --object-path /org/freedesktop/impl/portal/PermissionStore)
  if gdbus call "${store[@]}" --method "$ps.Lookup" kde-authorized remote-desktop 2>/dev/null | grep -q "'org.kde.krdpserver': \['yes'\]"; then
    mark_ok "KRDP screen-capture permission"
  else
    gdbus call "${store[@]}" --method "$ps.SetPermission" kde-authorized true remote-desktop org.kde.krdpserver "['yes']" >/dev/null \
      || die "could not grant KRDP the remote-desktop permission"
    mark_changed "KRDP screen-capture permission"
  fi
  # krdpserver exits without a certificate; only the System Settings page makes one.
  local cert="${XDG_DATA_HOME:-$HOME/.local/share}/krdpserver/krdp.crt" key
  key="${cert%.crt}.key"
  if [[ -s "$cert" && -s "$key" && "$(kreadconfig6 --file krdpserverrc --group General --key Certificate)" == "$cert" ]]; then
    mark_ok "KRDP certificate"; return
  fi
  mkdir -p "${cert%/*}"
  (umask 077; openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$key" -out "$cert" -subj "/CN=$(hostname)" 2>/dev/null) || die "could not create the KRDP certificate"
  kwriteconfig6 --file krdpserverrc --group General --key Certificate "$cert"
  kwriteconfig6 --file krdpserverrc --group General --key CertificateKey "$key"
  mark_changed "KRDP certificate"
}

# Autologin straight into the desktop. The session (niri or Plasma) lives in its
# own file because switch-session rewrites it; niri is only the first default.
setup_autologin() {
  local dir="${ROOT:-}/etc/plasmalogin.conf.d" want
  want=$(printf '[Autologin]\nUser=%s\n' "$USER")
  if [[ "$(cat "$dir/10-autologin.conf" 2>/dev/null)" == "$want" ]]; then mark_ok "autologin for $USER"; else
    printf '%s\n' "$want" | sudo install -D -m 0644 /dev/stdin "$dir/10-autologin.conf"
    mark_changed "autologin for $USER"
  fi
  if [[ ! -f "$dir/20-autologin-session.conf" ]]; then
    printf '[Autologin]\nSession=niri.desktop\n' | sudo install -D -m 0644 /dev/stdin "$dir/20-autologin-session.conf"
    mark_changed "autologin session set to niri"
  fi
  # switch-session may run this one command as root without a password.
  local sudoers="${ROOT:-}/etc/sudoers.d/switch-session" tmp
  want="$USER ALL=(root) NOPASSWD: /usr/local/libexec/switch-session-apply niri, /usr/local/libexec/switch-session-apply plasma"
  if [[ "$(sudo cat "$sudoers" 2>/dev/null)" == "$want" ]]; then mark_ok "switch-session sudo rule"; return; fi
  tmp=$(mktemp); printf '%s\n' "$want" > "$tmp"
  sudo visudo -cqf "$tmp" || { rm -f "$tmp"; die "switch-session sudo rule did not validate"; }
  sudo install -D -m 0440 "$tmp" "$sudoers"; rm -f "$tmp"
  mark_changed "switch-session sudo rule"
}
