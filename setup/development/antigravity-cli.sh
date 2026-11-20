#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../helpers/dispatcher.sh"

install_antigravity_cli() {
	local installed_ver
	if installed_ver="$(antigravity_cli_version 2>/dev/null)"; then
		printf 'skip: antigravity already installed (%s)\n' "$installed_ver"
	else
		local tmp rc
		tmp="$(mktemp -d)" || {
			printf 'error: antigravity-cli: cannot create temporary directory\n' >&2
			return 1
		}
		(antigravity_cli_install_verified "$tmp")
		rc=$?
		rm -rf -- "$tmp"
		((rc == 0)) || return "$rc"
	fi
	# ~/.local/bin is rc-file-only; symlink so agy works in non-interactive shells.
	sudo ln -sf "$HOME/.local/bin/agy" /usr/local/bin/agy
}

antigravity_cli_install_verified() {
	local tmp=$1 arch manifest_url version artifact_url digest asset
	local bin_dir staged installed_ver checksum_tool github_api metadata_script
	case "$(uname -m)" in
		x86_64 | amd64) arch=amd64 ;;
		aarch64 | arm64) arch=arm64 ;;
		*)
			printf 'error: antigravity-cli: unsupported architecture: %s\n' \
				"$(uname -m)" >&2
			return 1
			;;
	esac
	command -v curl >/dev/null 2>&1 || {
		printf 'error: antigravity-cli: curl required\n' >&2
		return 1
	}
	command -v python3 >/dev/null 2>&1 || {
		printf 'error: antigravity-cli: python3 required\n' >&2
		return 1
	}
	command -v sha512sum >/dev/null 2>&1 || {
		printf 'error: antigravity-cli: sha512sum required\n' >&2
		return 1
	}
	metadata_script="$(dirname "${BASH_SOURCE[0]}")/antigravity_cli_metadata.py"
	manifest_url="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_${arch}.json"
	curl -fsSL "$manifest_url" -o "$tmp/manifest.json" || {
		printf 'error: antigravity-cli: cannot download publisher manifest\n' >&2
		return 1
	}
	if ! python3 "$metadata_script" manifest "$tmp/manifest.json" > "$tmp/metadata"; then
		printf 'error: antigravity-cli: malformed publisher manifest\n' >&2
		return 1
	fi
	IFS=$'\t' read -r version artifact_url digest < "$tmp/metadata"
	asset="${artifact_url##*/}"
	[[ -n $asset && $asset == *.tar.gz ]] || {
		printf 'error: antigravity-cli: unsupported publisher artifact\n' >&2
		return 1
	}
	if [[ -n $digest ]]; then
		checksum_tool=sha512sum
	else
		command -v sha256sum >/dev/null 2>&1 || {
			printf 'error: antigravity-cli: sha256sum required for GitHub fallback\n' >&2
			return 1
		}
		case $arch in
			amd64) asset=agy_cli_linux_x64.tar.gz ;;
			arm64) asset=agy_cli_linux_arm64.tar.gz ;;
		esac
		github_api="https://api.github.com/repos/google-antigravity/antigravity-cli/releases/tags/$version"
		curl -fsSL -H 'Accept: application/vnd.github+json' \
			"$github_api" -o "$tmp/github-release.json" || {
			printf 'error: antigravity-cli: cannot download GitHub release metadata for %s\n' "$version" >&2
			return 1
		}
		if ! python3 "$metadata_script" github-release "$tmp/github-release.json" "$version" "$asset" > "$tmp/github-metadata"; then
			printf 'error: antigravity-cli: no published GitHub sha256 for %s at %s\n' "$asset" "$version" >&2
			return 1
		fi
		IFS=$'\t' read -r artifact_url digest < "$tmp/github-metadata"
		checksum_tool=sha256sum
	fi
	curl -fsSL "$artifact_url" -o "$tmp/$asset" || {
		printf 'error: antigravity-cli: cannot download %s\n' "$asset" >&2
		return 1
	}
	printf '%s  %s\n' "$digest" "$tmp/$asset" > "$tmp/checksum"
	"$checksum_tool" --check --status "$tmp/checksum" || {
		printf 'error: antigravity-cli: %s mismatch for %s\n' "${checksum_tool%sum}" "$asset" >&2
		return 1
	}
	tar -xzf "$tmp/$asset" -C "$tmp" antigravity 2>/dev/null || {
		printf 'error: antigravity-cli: cannot extract antigravity from %s\n' "$asset" >&2
		return 1
	}
	[[ -f $tmp/antigravity ]] || {
		printf 'error: antigravity-cli: %s has no antigravity binary\n' "$asset" >&2
		return 1
	}
	bin_dir="$HOME/.local/bin"
	mkdir -p "$bin_dir" || {
		printf 'error: antigravity-cli: cannot create %s\n' "$bin_dir" >&2
		return 1
	}
	staged="$bin_dir/.agy.part.$$"
	install -m 0755 "$tmp/antigravity" "$staged" || {
		printf 'error: antigravity-cli: cannot stage agy in %s\n' "$bin_dir" >&2
		return 1
	}
	installed_ver="$("$staged" --version 2>/dev/null | head -n 1 | grep .)" || {
		rm -f -- "$staged"
		printf 'error: antigravity-cli: staged binary failed to run\n' >&2
		return 1
	}
	mv -f -- "$staged" "$bin_dir/agy" || {
		rm -f -- "$staged"
		printf 'error: antigravity-cli: cannot install agy in %s\n' "$bin_dir" >&2
		return 1
	}
	printf 'installed: antigravity-cli %s to %s/agy\n' "$installed_ver" "$bin_dir"
}

antigravity_cli_version() {
	agy --version 2>/dev/null | head -n 1 | grep .
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dispatch_command "$@"
fi
