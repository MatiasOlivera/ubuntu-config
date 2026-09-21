#!/usr/bin/env bash
#
# gaps.sh — report-only list of host-installed apps (apt/snap/flatpak/AppImage)
# not tracked by this repo. Never installs anything, never exits non-zero.
# Baseline: vendored official Ubuntu desktop manifest (see README
# "Updating to a new Ubuntu version" for the refresh procedure).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP_DIR="$ROOT/setup"
BASELINE="$ROOT/reports/baselines/ubuntu-26.04.1-desktop-manifest.txt"

section() {
	printf '\n%s\n| candidate | version |\n' "$1"
}

# Managed apt packages: tokens after `apt install`/`apt-get install`, package
# names from `dpkg -s` in *_version fns, plus direct-.deb names whose version
# fn uses `command -v` instead (chrome). Keep in sync with setup/*.sh.
managed_apt() {
	grep -rhoE 'apt(-get)? +install +[^#]*' "$SETUP_DIR" 2>/dev/null |
		sed -E 's/.*install +//' |
		tr ' ' '\n' |
		grep -xE '[A-Za-z0-9][A-Za-z0-9+.-]*' |
		grep -vxE 'sudo|apt|apt-get|install' |
		sort -u
	grep -rhoE 'dpkg +-s +[A-Za-z0-9][A-Za-z0-9+.-]*' "$SETUP_DIR" 2>/dev/null |
		sed -E 's/.*dpkg +-s +//' |
		sort -u
	printf 'google-chrome-stable\n'
}

# Snap names after `snap install` in setup/*.sh (e.g. postman).
managed_snap() {
	grep -rhoE 'snap install +[A-Za-z0-9][A-Za-z0-9.-]*' "$SETUP_DIR" 2>/dev/null |
		sed -E 's/.*install +//' |
		sort -u
}

# Flatpak app IDs (contain a dot) after `flatpak install` in setup/*.sh
# (e.g. com.obsproject.Studio and its plugins).
managed_flatpak() {
	grep -rhoE 'flatpak install +[^#]*' "$SETUP_DIR" 2>/dev/null |
		sed -E 's/.*flatpak install +//; s/ +-y//' |
		tr ' ' '\n' |
		grep -E '^[A-Za-z0-9]+\.[A-Za-z0-9.]+$' |
		sort -u
}

# AppImage filenames literally referenced in setup/*.sh (none today).
managed_appimage() {
	grep -rhoIE '[A-Za-z0-9._-]+\.(appimage|AppImage)' "$SETUP_DIR" 2>/dev/null |
		sort -u
}

snap_base='^(bare|core[0-9]*|gnome-[0-9-]+|gtk-common-themes|mesa-[0-9]+|snapd.*|firmware-updater|prompting-client|desktop-security-center|snap-store)$'

apt_candidates() { apt-mark showmanual 2>/dev/null | sort -u; }
snap_candidates() { snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort -u; }
flatpak_candidates() { flatpak list --app --columns=application 2>/dev/null | sort -u; }
appimage_candidates() {
	local d
	for d in "$HOME/Applications" "$HOME/.local/bin" /opt /usr/local/bin; do
		[[ -d $d ]] && find "$d" -maxdepth 2 -type f -iname '*.AppImage' 2>/dev/null
	done
	grep -rhEi '^Exec=.*\.(AppImage|appimage)' \
		"$HOME/.local/share/applications" /usr/share/applications 2>/dev/null |
		sed -E 's/.*Exec=//; s/ .*$//'
}

version_apt() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }
version_snap() { snap list "$1" 2>/dev/null | awk 'NR==2 {print $2}'; }
version_flatpak() { flatpak info "$1" 2>/dev/null | awk -F': ' '/^Version:/ {print $2; exit}'; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

apt_candidates | grep -vFxf <(managed_apt | sort -u) | grep -vFxf "$BASELINE" >"$tmpdir/apt"
snap_candidates | grep -vE "$snap_base" | grep -vFxf <(managed_snap | sort -u) >"$tmpdir/snap"
flatpak_candidates | grep -vFxf <(managed_flatpak | sort -u) >"$tmpdir/flatpak"
appimage_candidates | sort -u | grep -vFxf <(managed_appimage | sort -u) >"$tmpdir/appimage"

section "apt"
if [[ -s $tmpdir/apt ]]; then
	while IFS= read -r p; do
		printf '| %s | %s |\n' "$p" "$(version_apt "$p")"
	done <"$tmpdir/apt"
else
	printf 'none\n'
fi

section "snap"
if [[ -s $tmpdir/snap ]]; then
	while IFS= read -r p; do
		printf '| %s | %s |\n' "$p" "$(version_snap "$p")"
	done <"$tmpdir/snap"
else
	printf 'none\n'
fi

section "flatpak"
if [[ -s $tmpdir/flatpak ]]; then
	while IFS= read -r p; do
		printf '| %s | %s |\n' "$p" "$(version_flatpak "$p")"
	done <"$tmpdir/flatpak"
else
	printf 'none\n'
fi

section "AppImage"
if [[ -s $tmpdir/appimage ]]; then
	while IFS= read -r p; do
		printf '| %s | %s |\n' "$p" "$(basename "$p")"
	done <"$tmpdir/appimage"
else
	printf 'none\n'
fi

exit 0