#!/usr/bin/env bash
# lib/tools.sh - programs that are not in any dnf repo. Versions pinned here.

PASS_CLI_VERSION="2.2.3"
PASS_CLI_SHA256="7188f02a7c1e79a860f7166ad2c34f7a2e6c961265b70677e2704f216dd176d9"
PAY_RESPECTS_VERSION="0.8.8"
PAY_RESPECTS_SHA256="6ec7663d78427a6994d2139e7d8a17fd7bef5f807e9fd4a0d54534937bf63d59"
NERDFONT_VERSION="v3.4.0"
NERDFONT_SHA256="76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c"
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
