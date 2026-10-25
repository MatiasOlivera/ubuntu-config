#!/usr/bin/env bash
#
# credential-sync.sh — copy secrets from the Bitwarden vault (durable copy)
# into GNOME Keyring (runtime copy). See docs/decisions/0002-credential-storage.md.
#
# Interactive (needs one `bw unlock`); safe to re-run: entries already in the
# keyring are skipped, `secret-tool store` overwrites the rest. Non-interactive
# shells only report what is missing and exit 0, so install.sh stays safe.
# `--force` (`-f`) re-syncs from the vault even when the keyring already has the
# entry (rotation after a GitHub-side revoke); `--force <item>...` limits the
# re-sync to the named Bitwarden items, otherwise every mapped secret.

# Map: <bitwarden-item> <keyring-service> <keyring-account>
# Item names are not secrets and are safe to commit.
SECRETS_MAP=(
	"github-mcp-pat github-mcp personal-access-token"
	"KILO_API_KEY kilo api-key"
)

config_sync_credentials() {
	local force=0
	if [[ ${1:-} == --force || ${1:-} == -f ]]; then
		force=1
		shift
	elif [[ $# -gt 0 ]]; then
		printf 'usage: config_sync_credentials [--force|-f [item ...]]\n' >&2
		return 2
	fi
	# Fail fast on unknown item names before unlocking the vault.
	local name entry item service account known
	for name in "$@"; do
		known=0
		for entry in "${SECRETS_MAP[@]}"; do
			read -r item _ _ <<< "$entry"
			if [[ $name == "$item" ]]; then
				known=1
				break
			fi
		done
		if [[ $known -eq 0 ]]; then
			printf 'error: unknown secret: %s\n' "$name" >&2
			return 1
		fi
	done
	local missing=() selected
	for entry in "${SECRETS_MAP[@]}"; do
		read -r item service account <<< "$entry"
		if [[ $force -eq 0 ]]; then
			if secret-tool lookup service "$service" account "$account" >/dev/null 2>&1; then
				printf 'present: %s\n' "$item"
				continue
			fi
		elif [[ $# -gt 0 ]]; then
			selected=0
			for name in "$@"; do
				if [[ $name == "$item" ]]; then
					selected=1
					break
				fi
			done
			[[ $selected -eq 0 ]] && continue
		fi
		missing+=("$entry")
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
	# Fresh machines have bw installed but never logged in; unlock alone
	# cannot fix that, so check first and log in interactively (a tty is
	# guaranteed here — non-interactive shells returned early above).
	local bw_state
	bw_state="$(bw status 2>/dev/null | grep -o '"status":"[a-z]*"' | cut -d'"' -f4)"
	if [[ $bw_state == unauthenticated ]]; then
		printf 'vault: not logged in; starting interactive login\n' >&2
		bw login || return 1
	elif [[ $bw_state != unlocked && $bw_state != locked ]]; then
		printf 'error: cannot read vault status; run bw login first\n' >&2
		return 1
	fi
	export BW_SESSION
	BW_SESSION="$(bw unlock --raw)" || return 1
	# Pull extension/web edits into the CLI cache; otherwise get serves
	# a stale vault. Fail-closed: never store on a failed sync. The
	# exported session is picked up automatically; passing it per command
	# would expose the session key in process arguments.
	if ! bw sync >/dev/null 2>&1; then
		printf 'error: could not sync vault; keyring left untouched\n' >&2
		bw lock >/dev/null 2>&1
		unset BW_SESSION
		return 1
	fi
	local failed=0 secret
	for entry in "${missing[@]}"; do
		read -r item service account <<< "$entry"
		# Read first, store second: a failed read must never reach the
		# keyring (empty stdin stores an empty value and reports success).
		secret="$(bw get password "$item" 2>/dev/null)"
		if [[ -n $secret ]] &&
			printf '%s' "$secret" |
			secret-tool store --label "$item" service "$service" account "$account"; then
			printf 'synced: %s\n' "$item"
		else
			printf 'error: could not sync %s (missing item?)\n' "$item" >&2
			failed=1
		fi
	done
	bw lock >/dev/null 2>&1
	unset BW_SESSION
	return $failed
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	config_sync_credentials "$@"
fi
