#!/usr/bin/env bash
set -euo pipefail

PACKET_FILE="${1:?Usage: checkout_target.sh <packet.json>}"
TARGET_ROOT="${2:-target-repo}"

PACKET_FILE=$(cd "$(dirname "$PACKET_FILE")" && pwd)/$(basename "$PACKET_FILE")

TARGET_REPO=$(python3 -c "import json; p=json.load(open('$PACKET_FILE')); print(p.get('target_repo', p.get('repo', '')))")
TARGET_BRANCH=$(python3 -c "import json; p=json.load(open('$PACKET_FILE')); print(p.get('target_branch', 'main'))")
WORK_BRANCH=$(python3 -c "import json; p=json.load(open('$PACKET_FILE')); print(p.get('work_branch', p.get('branch', 'agent/auto-unknown')))")

if [ -z "${TARGET_REPO_TOKEN:-}" ]; then
    echo "ERROR: TARGET_REPO_TOKEN must be set" >&2
    exit 1
fi

if [ -n "${ALLOWED_TARGET_REPOS:-}" ]; then
    if ! echo "$ALLOWED_TARGET_REPOS" | grep -qF "$TARGET_REPO"; then
        echo "ERROR: target_repo '$TARGET_REPO' not in ALLOWED_TARGET_REPOS allowlist" >&2
        exit 1
    fi
fi

rm -rf "$TARGET_ROOT"
git clone --quiet "https://x-access-token:${TARGET_REPO_TOKEN}@github.com/${TARGET_REPO}.git" "$TARGET_ROOT" >&2
cd "$TARGET_ROOT"
git checkout --quiet "$TARGET_BRANCH" >&2 || git checkout --quiet -b "$TARGET_BRANCH" >&2
git checkout --quiet -b "$WORK_BRANCH" >&2

echo "$TARGET_ROOT"
