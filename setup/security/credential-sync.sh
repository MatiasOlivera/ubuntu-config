#!/usr/bin/env bash
#
# credential-sync.sh — copy secrets from the Bitwarden vault (durable copy)
# into GNOME Keyring (runtime copy). See docs/decisions/0002-credential-storage.md.
#
# Interactive (needs one `bw unlock`); safe to re-run: entries already in the
# keyring are skipped, `secret-tool store` overwrites the rest. Non-interactive
# shells only report what is missing and exit 0, so install.sh stays safe.

# Map: <bitwarden-item> <keyring-service> <keyring-account>
# Item names are not secrets and are safe to commit.
SECRETS_MAP=(
	"github-mcp-pat github-mcp personal-access-token"
)

config_sync_credentials() {
	local missing=() entry item service account
	for entry in "${SECRETS_MAP[@]}"; do
		read -r item service account <<< "$entry"
		if secret-tool lookup service "$service" account "$account" >/dev/null 2>&1; then
			printf 'present: %s\n' "$item"
		else
			missing+=("$entry")
		fi
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		printf 'skip: all %d secret(s) present in keyring\n' "${#SECRETS_MAP[@]}"
		return 0
	fi
	if [[ ! -t 0 ]]; then
		printf 'pending: %d secret(s) missing from keyring; run setup/security/credential-sync.sh in a terminal\n' "${#missing[@]}"
		printf '  %s\n' "${missing[@]}"
		return 0
	fi
	command -v bw >/dev/null || {
		printf 'error: bw not installed\n' >&2
		return 1
	}
	export BW_SESSION
	BW_SESSION="$(bw unlock --raw)" || return 1
	local failed=0
	for entry in "${missing[@]}"; do
		read -r item service account <<< "$entry"
		if bw get password "$item" --session "$BW_SESSION" 2>/dev/null |
			secret-tool store --label "$item" service "$service" account "$account"; then
			printf 'synced: %s\n' "$item"
		else
			printf 'error: could not sync %s (missing item?)\n' "$item" >&2
			failed=1
		fi
	done
	bw lock >/dev/null 2>&1
	return $failed
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	config_sync_credentials
fi
