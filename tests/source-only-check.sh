#!/usr/bin/env bash
#
# source-only-check.sh — validate a library script's declarations as text.
# The file is read, never sourced or executed. Exit 0 when it declares at
# least one top-level install_*/config_* function and has no top-level
# commands; exit 1 otherwise. Fail-closed.
# shellcheck disable=SC2016 # single-quoted shell snippets are literal text

set -u

f=${1:?usage: source-only-check.sh <script>}

fn_re='^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)([[:space:]]*\(\))?[[:space:]]*([{(])'
assign_re='^[A-Za-z_][A-Za-z0-9_]*='
heredoc_re="<<-?['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?"

depth=0    # >0 while inside a top-level function body
closer=    # '}' or ')' that closes that body
heredoc=   # active heredoc delimiter
array=0    # inside a top-level array assignment
guard=0    # inside the BASH_SOURCE standalone guard
found=0
status=0
lineno=0

while IFS= read -r line || [[ -n $line ]]; do
	lineno=$((lineno + 1))

	# Heredoc bodies are data, not commands. Skip through the delimiter so a
	# column-0 '}' inside data cannot end the enclosing function early.
	if [[ -n $heredoc ]]; then
		[[ $line == "$heredoc" ]] && heredoc=
		continue
	fi
	if [[ $line =~ $heredoc_re ]]; then
		heredoc=${BASH_REMATCH[1]}
	fi

	# Function bodies are skipped wholesale up to their column-0 closer.
	if (( depth > 0 )); then
		[[ $line == "$closer" ]] && depth=0
		continue
	fi

	# A multiline array assignment declares data; skip its elements.
	if (( array )); then
		[[ $line == ')' ]] && array=0
		continue
	fi

	# The standalone guard only fires when the file is run, never on source,
	# so whatever it calls is inert for this check.
	if (( guard )); then
		[[ ${line#"${line%%[![:space:]]*}"} == 'fi' ]] && guard=0
		continue
	fi

	[[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue

	# Sourcing a helper only defines functions; helpers are source-only by design.
	if [[ $line == source*helpers/* || $line == .\ *helpers/* ]]; then
		continue
	fi

	trimmed=${line#"${line%%[![:space:]]*}"}
	if [[ $trimmed == 'if [[ ${BASH_SOURCE[0]} == "$0" ]]; then' ]]; then
		guard=1
		continue
	fi

	# Literal/variable assignments declare state without running commands.
	# Command substitutions would run on source, so they are not allowed.
	if [[ $line =~ $assign_re ]] && [[ $line != *'$('* && $line != *'`'* ]]; then
		[[ $line == *'=(' ]] && array=1
		continue
	fi

	# A function definition at top level: record it and skip its body.
	if [[ $line =~ $fn_re ]]; then
		case ${BASH_REMATCH[2]} in
		install_* | config_*) found=1 ;;
		esac
		if [[ ${BASH_REMATCH[4]} == '{' ]]; then
			closer='}'
		else
			closer=')'
		fi
		depth=1
		continue
	fi

	printf 'line %d: top-level command: %s\n' "$lineno" "$line" >&2
	status=1
done < "$f"

if (( found == 0 )) && (( status == 0 )); then
	printf 'no install_*/config_* function found\n' >&2
	status=1
fi

exit "$status"
