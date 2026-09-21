#!/usr/bin/env bash
#
# versions.sh — report-only version table for everything install.sh /
# post-install.sh set up.
# Never installs anything, never exits non-zero.
# shellcheck disable=SC2016,SC2088,SC1090,SC1091
# (single-quoted bash -c strings and "~" label are intentional;
#  SC1090/SC1091: dynamic sources below are all repo-local setup scripts)

chk() {
	local label=$1
	shift
	local out status
	out="$("$@" 2>&1)"
	status=$?
	out="$(printf '%s\n' "$out" | head -n 1)"
	if [ "$status" -eq 0 ] && [ -n "$out" ]; then
		printf '| %s | %s |\n' "$label" "$out"
	else
		printf '| %s | MISSING |\n' "$label"
	fi
}

printf '| Package | Version |\n'
printf '|---|---|\n'

# Version checks live in the package scripts (single source of truth, also
# used by the install guards). Sourcing is side-effect-free: library scripts
# only define functions. `|| true` keeps this report-only on a bad file
# (missing fns degrade to MISSING rows via chk).
VERIFY_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_DIR="$VERIFY_DIR/../setup"
src() { source "$SETUP_DIR/$1" || true; }
src essentials/curl.sh
src essentials/make.sh
src essentials/flatpak.sh
src essentials/pulseaudio-utils.sh
src essentials/fuse.sh
src essentials/synaptic.sh
src essentials/python3/python3-pip.sh
src essentials/python3/python3-pipx.sh
src essentials/chezmoi.sh
src desktop-apps/timeshift.sh
src desktop-apps/fsearch.sh
src desktop-apps/chrome.sh
src desktop-apps/obs/obs.sh
src desktop-apps/obsidian.sh
src desktop-apps/spotify.sh
src desktop-apps/discord.sh
src desktop-apps/handy/handy.sh
src development/git/git.sh
src development/cursor.sh
src development/gitkraken.sh
src development/vscode.sh
src development/fonts.sh
src development/docker.sh
src development/postman.sh
src development/beekeeper-studio.sh
src development/zsh/zsh.sh
src development/zoxide.sh
src development/opencode/opencode.sh
src development/ghostty/ghostty.sh
src development/oh-my-zsh/oh-my-zsh.sh
src development/oh-my-zsh/plugins.sh
src development/oh-my-zsh/theme.sh
src development/antigravity-cli/antigravity-cli.sh
src development/fnm/install-fnm.sh
src development/fnm/fnm-config.sh
src development/ollama.sh
src development/homebrew.sh

chk "curl" curl_version
chk "make" make_version
chk "flatpak" flatpak_version
chk "pulseaudio-utils" pulseaudio_utils_version
chk "fuse" fuse_version
chk "synaptic" synaptic_version
chk "pip" pip_version
chk "pipx" pipx_version
chk "timeshift" timeshift_version
chk "fsearch" fsearch_version
chk "chrome" chrome_version
chk "obs" obs_version
chk "obs-plugins" obs_plugins_version
chk "obsidian" obsidian_version
chk "spotify" spotify_version
chk "discord" discord_version
chk "handy" handy_version
chk "git" git_version
chk "chezmoi" chezmoi_version
chk "cursor" cursor_cli_version
chk "cursor-ide" cursor_version
chk "gitkraken" gitkraken_version
chk "vscode" vscode_version
chk "fonts" fonts_version
chk "docker" docker_version
chk "docker-compose" docker_compose_version
chk "postman" postman_version
chk "beekeeper" beekeeper_studio_version
chk "zsh" zsh_version
chk "zoxide" zoxide_version
chk "opencode" opencode_version
chk "ghostty" ghostty_version
chk "oh-my-zsh" oh_my_zsh_version
chk "zsh-plugins" oh_my_zsh_plugins_version
chk "p10k-theme" oh_my_zsh_theme_version
chk "antigravity" antigravity_cli_version
chk "fnm" fnm_version
chk "node" node_version
chk "ollama" ollama_version
chk "homebrew" brew_version

printf '\n| Config | Status |\n'
printf '|---|---|\n'
chk "git-config" bash -c 'git config --global --get user.name >/dev/null && git config --global --get user.email'
chk "zsh-default" bash -c '[[ "$SHELL" == *zsh* ]] && echo "$SHELL"'
chk "ghostty-default" gsettings get org.gnome.desktop.default-applications.terminal exec
chk "antigravity-path" bash -c 'grep -qF ".local/bin" "$HOME/.zshrc" && echo present'

exit 0
