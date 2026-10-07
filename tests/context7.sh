#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Netresearch DTT GmbH
#
# tests/context7.sh — behavioural tests for skills/context7/scripts/context7.sh.
#
# The script talks to the Context7 REST API through curl. These tests put a
# fake curl first on PATH, so no request leaves the machine: the fake records
# every argument it receives and prints a canned response body. Each case then
# checks the exit code, the output, and the request the script would have sent.
# Requires bash and jq (the script itself needs jq).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/skills/context7/scripts/context7.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Fake curl: one argument per line into $STUB_LOG, standard input into
# $STUB_STDIN when an argument tells curl to read headers from it (`@-`),
# then the canned body.
printf '%s\n' "$@" >> "$STUB_LOG"
for a in "$@"; do
    [ "$a" = "@-" ] && cat >> "$STUB_STDIN"
done
[ -n "${STUB_BODY:-}" ] && printf '%s' "$STUB_BODY"
exit 0
STUB
chmod +x "$WORK/bin/curl"

export STUB_LOG="$WORK/curl.args"
export STUB_STDIN="$WORK/curl.stdin"
fail=0
count=0

# run <args...> — runs the script with the fake curl; sets OUT and RC.
run() {
    : > "$STUB_LOG"
    : > "$STUB_STDIN"
    OUT=$(PATH="$WORK/bin:$PATH" bash "$SCRIPT" "$@" 2>&1)
    RC=$?
}

check() { # check <description> <command...>
    local desc="$1"
    shift
    count=$((count + 1))
    if "$@"; then
        echo "  ok   $desc"
    else
        echo "  FAIL $desc"
        echo "       exit=$RC output:"
        printf '%s\n' "$OUT" | sed 's/^/         /'
        echo "       curl arguments:"
        sed 's/^/         /' "$STUB_LOG"
        fail=1
    fi
}

out_has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
arg_has() { grep -qxF -- "$1" "$STUB_LOG"; }
arg_lacks() { ! grep -qF -- "$1" "$STUB_LOG"; }
stdin_has() { grep -qxF -- "$1" "$STUB_STDIN"; }
no_request() { [ ! -s "$STUB_LOG" ]; }
rc_is() { [ "$RC" -eq "$1" ]; }

echo "context7.sh"

# --- usage and argument validation -------------------------------------------
unset CONTEXT7_API_KEY
export STUB_BODY=""

run
check "no command exits 1" rc_is 1
check "no command prints usage" out_has "Usage: context7.sh <command>"
check "no command sends no request" no_request

run --help
check "--help exits 0" rc_is 0
check "--help lists both commands" out_has "docs <library-id> [topic] [mode]"

run search
check "search without query exits 1" rc_is 1
check "search without query sends no request" no_request

run docs
check "docs without library id exits 1" rc_is 1
check "docs without library id sends no request" no_request

run docs /facebook/react hooks html
check "docs with an unknown mode exits 1" rc_is 1
check "docs with an unknown mode names the allowed modes" out_has "mode must be 'code' or 'info'"
check "docs with an unknown mode sends no request" no_request

# --- docs: request construction ----------------------------------------------
export STUB_BODY="REACT HOOKS DOCS"

run docs /facebook/react hooks
check "docs exits 0" rc_is 0
check "docs defaults to code mode and strips the leading slash" \
    arg_has "https://context7.com/api/v2/docs/code/facebook/react?type=txt&topic=hooks"
check "docs sends the source header" arg_has "X-Context7-Source: claude-skill"
check "docs sends no Authorization header without a key" arg_lacks "Authorization"
check "docs prints the response body" out_has "REACT HOOKS DOCS"

run docs /vercel/next.js "app router" info
check "docs uses info mode and percent-encodes the topic" \
    arg_has "https://context7.com/api/v2/docs/info/vercel/next.js?type=txt&topic=app%20router"

run docs /prisma/prisma
check "docs without topic omits the topic parameter" \
    arg_has "https://context7.com/api/v2/docs/code/prisma/prisma?type=txt"

CONTEXT7_API_KEY="test-key" run docs /facebook/react hooks
check "docs sends the API key as a bearer token on standard input" stdin_has "Authorization: Bearer test-key"
check "docs reads the header from standard input" arg_has "@-"
check "docs keeps the API key off curl's command line" arg_lacks "test-key"
check "docs still sends the source header with a key" arg_has "X-Context7-Source: claude-skill"

# --- search: request construction and output formatting ----------------------
export STUB_BODY='{"results":[{"id":"/vercel/next.js","title":"Next.js","totalSnippets":42,"benchmarkScore":9.5,"description":"The React framework"}]}'

run search "next.js app router"
check "search exits 0" rc_is 0
check "search percent-encodes the query" \
    arg_has "https://context7.com/api/v2/search?query=next.js%20app%20router"
check "search sends no Authorization header without a key" arg_lacks "Authorization"
check "search prints the library id" out_has "ID: /vercel/next.js"
check "search prints the title" out_has "Name: Next.js"
check "search prints snippets and score" out_has "Snippets: 42 | Score: 9.5"

CONTEXT7_API_KEY="test-key" run search react
check "search sends the API key as a bearer token on standard input" stdin_has "Authorization: Bearer test-key"
check "search keeps the API key off curl's command line" arg_lacks "test-key"

export STUB_BODY='{"error":"rate limited"}'
run search react
check "search reports an API error field" out_has "Error: rate limited"

export STUB_BODY='not json at all'
run search react
check "search prints a non-JSON body unchanged" out_has "not json at all"

echo
if [ "$fail" -ne 0 ]; then
    echo "context7.sh: FAILED ($count checks)"
    exit 1
fi
echo "context7.sh: all $count checks passed"
