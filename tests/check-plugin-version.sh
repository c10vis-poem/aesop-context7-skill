#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Netresearch DTT GmbH
#
# tests/check-plugin-version.sh — behavioural tests for
# Build/Scripts/check-plugin-version.sh, which the pre-push hook runs.
#
# Each case builds a throwaway git repository with a .claude-plugin/plugin.json
# and a tag, runs the check inside it, and compares the exit code.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/Build/Scripts/check-plugin-version.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
count=0

# repo <name> <plugin-version> [tag] — creates a repository with one commit.
repo() {
    local dir="$WORK/$1"
    mkdir -p "$dir/.claude-plugin"
    printf '{"name":"t","version":"%s"}\n' "$2" > "$dir/.claude-plugin/plugin.json"
    git -C "$dir" init -q
    git -C "$dir" add .claude-plugin/plugin.json
    git -C "$dir" -c user.name=test -c user.email=test@example.invalid \
        -c commit.gpgsign=false commit -q -m init
    if [ -n "${3:-}" ]; then
        git -C "$dir" -c tag.gpgsign=false tag "$3"
    fi
}

expect() { # expect <description> <expected-exit> <repo-name>
    local out rc
    count=$((count + 1))
    out=$(cd "$WORK/$3" && bash "$SCRIPT" 2>&1)
    rc=$?
    if [ "$rc" -eq "$2" ]; then
        echo "  ok   $1"
    else
        echo "  FAIL $1 (expected exit $2, got $rc)"
        printf '%s\n' "$out" | sed 's/^/         /'
        fail=1
    fi
}

echo "check-plugin-version.sh"

repo untagged 1.2.3
expect "no tag at HEAD passes" 0 untagged

repo matching 1.2.3 v1.2.3
expect "v-prefixed tag matching plugin.json passes" 0 matching

repo bare 1.2.3 1.2.3
expect "tag without v prefix matching plugin.json passes" 0 bare

repo mismatch 1.2.3 v1.2.4
expect "tag not matching plugin.json fails" 1 mismatch

repo nonsemver 1.2.3 release-candidate
expect "non-semver tag is ignored" 0 nonsemver

echo
if [ "$fail" -ne 0 ]; then
    echo "check-plugin-version.sh: FAILED ($count checks)"
    exit 1
fi
echo "check-plugin-version.sh: all $count checks passed"
