#!/usr/bin/env bash
set -euo pipefail

PACKET_FILE="${1:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"

python3 - "$PACKET_FILE" > /tmp/push-params.txt << 'PY'
import json, sys
from pathlib import Path
packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
target = packet.get('target_branch', 'main')
task = packet.get('task_summary', packet.get('task', 'Automated implementation'))[:100]
draft = '--draft' if packet.get('draft_pr') else ''
Path('/tmp/push-task.txt').write_text(task)
print(f"{repo}\t{target}\t{draft}")
PY

read -r TARGET_REPO TARGET_BRANCH DRAFT_FLAG < /tmp/push-params.txt
TASK_SUMMARY=$(cat /tmp/push-task.txt)

if [ -z "${TARGET_REPO_TOKEN:-}" ]; then
    echo "ERROR: TARGET_REPO_TOKEN must be set" >&2
    exit 1
fi

cd "$TARGET_ROOT"
git config user.name "${GIT_USER_NAME:-public-runner-bot}"
git config user.email "${GIT_USER_EMAIL:-bot@public-runner.local}"
git add -A
git commit -m "feat(runner): ${TASK_SUMMARY}" || true
git push origin HEAD
export GH_TOKEN="$TARGET_REPO_TOKEN"
PR_URL=$(gh pr create --repo "$TARGET_REPO" --title "$TASK_SUMMARY" --body "Automated change from public runner." --base "$TARGET_BRANCH" ${DRAFT_FLAG:+$DRAFT_FLAG} 2>/dev/null || echo "")
printf '%s\n' "$PR_URL"
