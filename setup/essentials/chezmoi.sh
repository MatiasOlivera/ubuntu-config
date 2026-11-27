#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_chezmoi() {
	local installed_ver
	if installed_ver="$(chezmoi_version 2>/dev/null)"; then
		printf 'skip: chezmoi already installed (%s)\n' "$installed_ver"
		return 0
	fi
	local tmp rc
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi.XXXXXXXX")" || {
		printf 'error: chezmoi: cannot create temporary directory\n' >&2
		return 1
	}
	(chezmoi_install_verified "$tmp")
	rc=$?
	rm -rf -- "$tmp"
	return "$rc"
}

# Verify the release artifact against its maintainer-published checksum before
# installing it. The subshell keeps install.sh's EXIT trap untouched.
chezmoi_install_verified() {
	local tmp=$1 arch raw_info version asset artifact_url checksums_url
	local digest artifact metadata_script installed_ver
	case "$(uname -m)" in
		x86_64 | amd64) arch=amd64 ;;
		aarch64 | arm64) arch=arm64 ;;
		*)
			printf 'error: chezmoi: unsupported architecture: %s\n' "$(uname -m)" >&2
			return 1
			;;
	esac
	for tool in curl python3 sha256sum tar uname mktemp chmod head grep install; do
		command -v "$tool" >/dev/null 2>&1 || {
			printf 'error: chezmoi: %s required\n' "$tool" >&2
			return 1
		}
	done

	curl -fsSL -H 'Accept: application/vnd.github+json' \
		'https://api.github.com/repos/twpayne/chezmoi/releases/latest' \
		-o "$tmp/release.json" || {
		printf 'error: chezmoi: cannot download release metadata\n' >&2
		return 1
	}
	metadata_script="$(dirname "${BASH_SOURCE[0]}")/chezmoi_metadata.py"
	raw_info="$(python3 "$metadata_script" release "$tmp/release.json" "$arch")" || return 1
	IFS=$'\t' read -r version asset artifact_url checksums_url <<< "$raw_info"

	curl -fsSL "$checksums_url" -o "$tmp/checksums.txt" || {
		printf 'error: chezmoi: cannot download checksums\n' >&2
		return 1
	}
	digest="$(python3 "$metadata_script" checksum "$tmp/checksums.txt" "$asset")" || return 1

	artifact="$tmp/$asset"
	curl -fsSL "$artifact_url" -o "$artifact" || {
		printf 'error: chezmoi: cannot download %s\n' "$asset" >&2
		return 1
	}
	printf '%s  %s\n' "$digest" "$artifact" > "$tmp/checksum"
	sha256sum --check --status "$tmp/checksum" || {
		printf 'error: chezmoi: checksum mismatch for %s\n' "$asset" >&2
		return 1
	}

	tar -xzf "$artifact" -C "$tmp" chezmoi 2>/dev/null || {
		printf 'error: chezmoi: cannot extract chezmoi from %s\n' "$asset" >&2
		return 1
	}
	[[ -f $tmp/chezmoi ]] || {
		printf 'error: chezmoi: %s has no chezmoi binary\n' "$asset" >&2
		return 1
	}
	chmod +x "$tmp/chezmoi" || {
		printf 'error: chezmoi: cannot prepare extracted binary\n' >&2
		return 1
	}
	installed_ver="$("$tmp/chezmoi" --version 2>/dev/null | head -n 1 | grep .)" || {
		printf 'error: chezmoi: extracted binary failed to run\n' >&2
		return 1
	}
	[[ -n $installed_ver ]] || {
		printf 'error: chezmoi: extracted binary returned no version\n' >&2
		return 1
	}

	sudo install -m 0755 "$tmp/chezmoi" /usr/local/bin/chezmoi || {
		printf 'error: chezmoi: cannot install verified binary\n' >&2
		return 1
	}
	printf 'installed: chezmoi %s (release %s) to /usr/local/bin/chezmoi\n' \
		"$installed_ver" "$version"
}

chezmoi_version() {
	chezmoi --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
