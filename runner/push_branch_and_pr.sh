#!/usr/bin/env bash
set -euo pipefail

PACKET_FILE="${1:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: push_branch_and_pr.sh <packet.json> <target-root>}"

PACKET_FILE=$(cd "$(dirname "$PACKET_FILE")" && pwd)/$(basename "$PACKET_FILE")

TARGET_REPO=$(python3 -c "import json; print(json.load(open('$PACKET_FILE')).get('target_repo', json.load(open('$PACKET_FILE')).get('repo', '')))")
TARGET_BRANCH=$(python3 -c "import json; print(json.load(open('$PACKET_FILE')).get('target_branch', 'main'))")
TASK_SUMMARY=$(python3 -c "import json; p=json.load(open('$PACKET_FILE')); print((p.get('task_summary') or p.get('task', 'Automated implementation'))[:100])")
DRAFT_FLAG=$(python3 -c "import json; print('--draft' if json.load(open('$PACKET_FILE')).get('draft_pr') else '')")
ISSUE_NUMBER=$(python3 -c "import json; print(json.load(open('$PACKET_FILE')).get('issue_number', ''))")

if [ -z "${TARGET_REPO_TOKEN:-}" ]; then
    echo "ERROR: TARGET_REPO_TOKEN must be set" >&2
    exit 1
fi

cd "$TARGET_ROOT"

git config user.name "${GIT_USER_NAME:-public-runner-bot}"
git config user.email "${GIT_USER_EMAIL:-bot@public-runner.local}"

BRANCH_NAME=$(python3 - "$PACKET_FILE" << 'PYBR'
import json, sys, time, uuid, datetime
from pathlib import Path

p = json.loads(Path(sys.argv[1]).read_text())
cycle = p.get("task_id", "")
if not cycle:
    issue = p.get("issue_number", "")
    if issue:
        ts = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        cycle = f"task-{issue}-{ts}"
    else:
        cycle = f"auto-{int(time.time())}-{uuid.uuid4().hex[:6]}"
cycle = cycle[:100].replace(" ", "-")
print(f"agent-runner/{cycle}")
PYBR
)

git checkout -B "$BRANCH_NAME"

CHANGES=$(git diff --stat --cached 2>/dev/null || echo "")
STAGED=$(git diff --stat 2>/dev/null || echo "")
if [ -z "$CHANGES" ] && [ -z "$STAGED" ]; then
    echo "No changes to commit"
    printf ''
    exit 0
fi

git add -A
git commit -m "feat(runner): ${TASK_SUMMARY}" || true
git push --force-with-lease origin "$BRANCH_NAME" >&2 || git push origin "$BRANCH_NAME" >&2

export GH_TOKEN="$TARGET_REPO_TOKEN"

PR_BODY="Automated change from public runner."
if [ -n "$ISSUE_NUMBER" ]; then
    PR_BODY="${PR_BODY}"$'\n\n'"Closes ons96/task-board#${ISSUE_NUMBER}"
fi

PR_URL=$(gh pr create \
    --repo "$TARGET_REPO" \
    --title "$TASK_SUMMARY" \
    --body "$PR_BODY" \
    --base "$TARGET_BRANCH" \
    ${DRAFT_FLAG:+$DRAFT_FLAG} 2>/dev/null || echo "")

printf '%s\n' "$PR_URL"
