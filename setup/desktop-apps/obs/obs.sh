#!/usr/bin/env bash

install_obs() {
	local installed_ver
	if installed_ver="$(obs_version 2>/dev/null)" && obs_plugins_version >/dev/null 2>&1; then
		printf 'skip: obs already installed (%s)\n' "$installed_ver"
		return 0
	fi
	flatpak install flathub -y com.obsproject.Studio \
		com.obsproject.Studio.Plugin.SceneSwitcher \
		com.obsproject.Studio.Plugin.AdvancedMasks \
		com.obsproject.Studio.Plugin.MoveTransition \
		com.obsproject.Studio.Plugin.PipeWireAudioCapture \
		com.obsproject.Studio.Plugin.SourceClone \
		com.obsproject.Studio.Plugin.StrokeGlowShadow \
		com.obsproject.Studio.Plugin.SourceCopy
}

obs_version() {
	flatpak info com.obsproject.Studio 2>/dev/null | grep -i "Version:" | head -n 1 | grep .
}

obs_plugins_version() {
	flatpak list 2>/dev/null | grep -i "com.obsproject.Studio.Plugin" | head -n 1 | grep .
}
