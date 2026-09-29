<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: Netresearch DTT GmbH -->

# Security assurance case — context7-skill

This document states what a user can expect from this repository in terms of security, and argues why that expectation holds. Every claim names the file that implements it. Reporting a vulnerability: see the [security policy](https://github.com/netresearch/.github/blob/main/SECURITY.md). Components and data flow: [ARCHITECTURE.md](ARCHITECTURE.md).

## What the repository ships

| Part | Files | Runs where |
| --- | --- | --- |
| Skill instructions for an AI agent | `skills/context7/SKILL.md` | Read by the agent as instructions; not executed |
| REST API wrapper | `skills/context7/scripts/context7.sh` | On the user's machine, run by the agent or the user |
| Repository checks | `Build/Scripts/check-plugin-version.sh`, `Build/hooks/pre-push`, `scripts/verify-harness.sh`, `tests/*.sh` | In this repository's CI and on contributors' machines |

The skill has no server component, stores nothing on disk, and handles no user accounts.

## Security requirements

1. `context7.sh` sends requests only to `https://context7.com/api/v2`.
2. The optional `CONTEXT7_API_KEY` is read from the environment and sent only as an `Authorization` header to that host; without the variable no `Authorization` header is sent.
3. Free-text arguments (search query, topic) cannot change the structure of the request URL.
4. `context7.sh` writes no file and executes nothing it receives.
5. Nothing committed to this repository contains a secret.

## Actors and trust boundaries

- **Agent and skill user.** The agent reads `SKILL.md` as instructions and runs `context7.sh` with a library name, a library ID, a topic and a mode. These arguments come from the user's question and are treated as untrusted text (see the countermeasures below).
- **Context7 API.** A third-party service operated by Upstash. `context7.sh` passes its response to the agent: search results are formatted with `jq`, documentation is printed as returned. The response is data for the agent to read; the script does not interpret or execute it.
- **Network.** The base URL is fixed to `https` in `context7.sh` (`BASE_URL`), and `curl` is called without `-L`, so a redirect is not followed to another host or scheme.
- **CI.** Workflows run on GitHub-hosted runners with `permissions: {}` at the top level and the minimum job permissions each called reusable workflow needs (`.github/workflows/*.yml`).

## Threats and countermeasures

| Threat | Countermeasure | Evidence |
| --- | --- | --- |
| A search query or topic injects extra query parameters or path segments into the request | Both are percent-encoded with `jq @uri` before they are placed into the URL | `context7.sh` (`search_library`, `fetch_docs`); `tests/context7.sh` asserts `next.js app router` becomes `next.js%20app%20router` and `app router` becomes `app%20router` |
| An arbitrary mode selects an unintended API path | `mode` must be `code` or `info`; anything else exits 1 before a request is made | `context7.sh` (`fetch_docs`); `tests/context7.sh` asserts exit 1 and no request for mode `html` |
| The API key is sent to another host | The key is only added to requests whose URL starts with the constant `BASE_URL`; there is no option to change the host | `context7.sh`; `tests/context7.sh` asserts the header is present only when `CONTEXT7_API_KEY` is set |
| The response is executed (CWE-94, CWE-78) | The response is only printed or passed to `jq` as data; the script uses no `eval`, `source` or command built from response text | `context7.sh` |
| A failing step continues with partial state | `context7.sh` runs with `set -e`; `Build/Scripts/check-plugin-version.sh` and `scripts/verify-harness.sh` with `set -euo pipefail` | the scripts named |
| A release is tagged with a version that disagrees with `plugin.json` | The pre-push hook runs `check-plugin-version.sh`, which fails when a semver tag at `HEAD` differs from `.claude-plugin/plugin.json` | `Build/hooks/pre-push`, `Build/Scripts/check-plugin-version.sh`; `tests/check-plugin-version.sh` |
| A secret is committed | Betterleaks scans every push and pull request to `main` | `.github/workflows/security.yml` |
| A vulnerable or malicious dependency is added | Dependency review fails on vulnerabilities of severity high or above in a pull request; Composer Audit checks the installed Composer dependencies against known advisories; Renovate proposes updates, including pre-commit hook revisions | `.github/workflows/security.yml`, `renovate.json` |
| Insecure code or workflow patterns | Opengrep fails on findings of severity WARNING or above; zizmor analyses the workflows; ShellCheck runs on every `*.sh` file at severity `error` in Skill Validation | `.github/workflows/security.yml`, `.github/workflows/lint.yml` |
| A regression in the wrapper's request handling | The behavioural tests run on every pull request | `.github/workflows/tests.yml`, `tests/context7.sh` |

Which of these checks must pass before a pull request can merge is set in the branch protection of `main`, not in this repository.

## Secure design principles applied

- **Economy of mechanism:** one Bash script with two commands and no dependencies beyond `curl` and `jq` (`context7.sh`).
- **Fail-safe defaults:** invalid or missing arguments exit 1 before any request is made; without an API key the script works anonymously rather than prompting for one.
- **Allowlist over escaping:** `mode` is checked against the two valid values instead of being encoded.
- **Minimal attack surface:** no network listener, no files written, no state kept between runs.

## What a user cannot expect

- The documentation returned by Context7 is third-party content. The script neither filters nor verifies it; an agent that reads it should treat it as reference material, not as instructions.
- The library ID is placed into the request path as given, after removing one leading slash. It is not percent-encoded, so an ID containing `?`, `#` or `..` changes which path on `context7.com` is requested. The host and scheme cannot change.
- `curl` runs with `-s` and without `-f`: an HTTP error response is printed like a successful one, and the script exits 0. A missing `curl` or `jq`, or a network failure, makes the script exit non-zero.
- The skill does not rate-limit or cache requests; Context7's own limits apply.
