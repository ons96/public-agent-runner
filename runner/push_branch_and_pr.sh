#!/usr/bin/env bash
set -euo pipefail

PACKET_FILE="${1:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"

read -r TARGET_REPO TARGET_BRANCH TASK_SUMMARY DRAFT_FLAG < <(python3 - <<'PY' "$PACKET_FILE"
import json, sys
from pathlib import Path
packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
target = packet.get('target_branch', 'main')
task = packet.get('task_summary', packet.get('task', 'Automated implementation'))[:100]
draft = '--draft' if packet.get('draft_pr') else ''
print(f"{repo}\t{target}\t{task}\t{draft}")
PY
)

if [ -z "${TARGET_REPO_TOKEN:-}" ]; then
    echo "ERROR: TARGET_REPO_TOKEN must be set" >&2
    exit 1
fi

PACKET_FILE=$(cd "$(dirname "$PACKET_FILE")" && pwd)/$(basename "$PACKET_FILE")
cd "$TARGET_ROOT"
git config user.name "${GIT_USER_NAME:-public-runner-bot}"
git config user.email "${GIT_USER_EMAIL:-bot@public-runner.local}"

# Use cycle-specific branch name from packet
BRANCH_NAME=$(python3 - "$PACKET_FILE" << 'PYBR'
import json, sys
from pathlib import Path
p = json.loads(Path(sys.argv[1]).read_text())
cycle = p.get("task_id", p.get("task_summary", "cycle-unknown"))[:60].replace(" ", "-")
print(f"agent-runner/{cycle}")
PYBR
)

git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
git add -A
git commit -m "feat(runner): ${TASK_SUMMARY}" || true
git push --force-with-lease origin "$BRANCH_NAME" 2>/dev/null || git push origin "$BRANCH_NAME" 
export GH_TOKEN="$TARGET_REPO_TOKEN"
PR_URL=$(gh pr create --repo "$TARGET_REPO" --title "$TASK_SUMMARY" --body "Automated change from public runner." --base "$TARGET_BRANCH" ${DRAFT_FLAG:+$DRAFT_FLAG} 2>/dev/null || echo "")
printf '%s\n' "$PR_URL"
