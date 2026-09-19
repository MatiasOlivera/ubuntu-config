#!/usr/bin/env bash
#
# verify.sh — report-only version table for everything install.sh /
# post-install.sh set up. Manually installed apps (e.g. Handy) are
# intentionally excluded. Never installs anything, never exits non-zero.
# shellcheck disable=SC2016,SC2088
# (single-quoted bash -c strings and "~" label are intentional)

chk() {
	local label=$1 desc=$2
	shift 2
	local out status
	out="$("$@" 2>&1)"
	status=$?
	out="$(printf '%s\n' "$out" | head -n 1)"
	if [ "$status" -eq 0 ] && [ -n "$out" ]; then
		printf '| %s | `%s` | %s |\n' "$label" "$desc" "$out"
	else
		printf '| %s | `%s` | MISSING |\n' "$label" "$desc"
	fi
}

printf '| Component | Check | Result |\n'
printf '|---|---|---|\n'

chk "curl" "curl --version" curl --version
chk "make" "make --version" make --version
chk "flatpak" "flatpak --version" flatpak --version
chk "pulseaudio-utils" "pactl --version" pactl --version
chk "fuse" "dpkg -s libfuse2t64" bash -c 'dpkg -s libfuse2t64 2>/dev/null | grep "^Version:"'
chk "synaptic" "dpkg -s synaptic" bash -c 'dpkg -s synaptic 2>/dev/null | grep "^Version:"'
chk "pip" "pip3 --version" pip3 --version
chk "pipx" "pipx --version" pipx --version
chk "timeshift" "timeshift --version" timeshift --version
chk "fsearch" "dpkg -s fsearch" bash -c 'dpkg -s fsearch 2>/dev/null | grep "^Version:"'
chk "chrome" "google-chrome --version" bash -c 'google-chrome --version 2>/dev/null || google-chrome-stable --version 2>/dev/null'
chk "obs" "flatpak info com.obsproject.Studio" bash -c 'flatpak info com.obsproject.Studio 2>/dev/null | grep -i "Version:" | head -n 1'
chk "obs-plugins" "flatpak list (obs plugins)" bash -c 'flatpak list 2>/dev/null | grep -i "com.obsproject.Studio.Plugin" | head -n 1'
chk "obsidian" "dpkg -s obsidian" bash -c 'dpkg -s obsidian 2>/dev/null | grep "^Version:"'
chk "spotify" "dpkg -s spotify-client" bash -c 'dpkg -s spotify-client 2>/dev/null | grep "^Version:"'
chk "discord" "dpkg -s discord" bash -c 'dpkg -s discord 2>/dev/null | grep "^Version:"'
chk "handy" "dpkg -s handy" bash -c 'dpkg -s handy 2>/dev/null | grep "^Version:"'
chk "git" "git --version" git --version
chk "git-config" "git user.name/email" bash -c 'git config --global --get user.name >/dev/null && git config --global --get user.email'
chk "chezmoi" "chezmoi --version" chezmoi --version
chk "cursor" "cursor --version" bash -c 'cursor --version 2>/dev/null || cursor-agent --version 2>/dev/null'
chk "cursor-ide" "dpkg -s cursor" bash -c 'dpkg -s cursor 2>/dev/null | grep "^Version:"'
chk "gitkraken" "dpkg -s gitkraken" bash -c 'dpkg -s gitkraken 2>/dev/null | grep "^Version:"'
chk "vscode" "code --version" bash -c 'code --version 2>/dev/null | head -n 1'
chk "docker" "docker --version" docker --version
chk "docker-compose" "docker compose version" docker compose version
chk "postman" "snap list postman" bash -c 'snap list postman 2>/dev/null | tail -n 1'
chk "beekeeper" "dpkg -s beekeeper-studio" bash -c 'dpkg -s beekeeper-studio 2>/dev/null | grep "^Version:"'
chk "zsh" "zsh --version" zsh --version
chk "zsh-default" "SHELL is zsh" bash -c '[[ "$SHELL" == *zsh* ]] && echo "$SHELL"'
chk "zoxide" "zoxide --version" zoxide --version
chk "opencode" "opencode --version" opencode --version
chk "ghostty" "ghostty --version" ghostty --version
chk "ghostty-default" "gsettings terminal exec" gsettings get org.gnome.desktop.default-applications.terminal exec
chk "oh-my-zsh" "~/.oh-my-zsh present" bash -c '[ -d "$HOME/.oh-my-zsh" ] && echo present'
chk "zsh-plugins" "autosuggestions/syntax-highlighting" bash -c '[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ] && [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ] && echo present'
chk "p10k-theme" "powerlevel10k present" bash -c '[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ] && echo present'
chk "antigravity" "agy --version" agy --version
chk "antigravity-path" ".local/bin in .zshrc" bash -c 'grep -qF ".local/bin" "$HOME/.zshrc" && echo present'
chk "fnm" "fnm --version" fnm --version
chk "node" "node --version" node --version

exit 0
