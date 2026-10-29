#!/usr/bin/env bash
# run_agent.sh - Execute agentic coding task using opencode + autopilot
# Autopilot provides: 8-phase pipeline, session recovery, model fallback, doom-loop detection
set -euo pipefail

PACKET_FILE="${1:?Usage: run_agent.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: run_agent.sh <packet.json> <target-root>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACKET_FILE=$(cd "$(dirname "$PACKET_FILE")" && pwd)/$(basename "$PACKET_FILE")

python3 - "$PACKET_FILE" > /tmp/runner-vars.txt << 'PY'
import json, sys
from pathlib import Path

packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
task = packet.get('task_summary') or packet.get('task') or packet.get('task_prompt', 'implement the project')
mode = packet.get('mode', 'implement')
issue_number = packet.get('issue_number', '')

Path("/tmp/runner-task.txt").write_text(task)
print(repo)
print(mode)
print(issue_number)
PY

TARGET_REPO=$(sed -n '1p' /tmp/runner-vars.txt)
MODE=$(sed -n '2p' /tmp/runner-vars.txt)
ISSUE_NUMBER=$(sed -n '3p' /tmp/runner-vars.txt)
TASK_TEXT=$(cat /tmp/runner-task.txt)

echo "=== Runner Agent (opencode + autopilot) ==="
echo "Repo: $TARGET_REPO"
echo "Task: ${TASK_TEXT:0:100}..."
echo "Mode: $MODE"
echo "Issue: ${ISSUE_NUMBER:-none}"

cd "$TARGET_ROOT"

python3 - "$TARGET_REPO" "$MODE" /tmp/runner-task.txt << 'PYTASK' > .runner-task.md
import sys
repo, mode, task_file = sys.argv[1], sys.argv[2], sys.argv[3]
task = open(task_file).read()
print(f"""# Agentic Coding Task

**Repository:** {repo}
**Mode:** {mode}

## Task Description

{task}

## Instructions

1. Implement this task completely and correctly
2. Use simple, maintainable code
3. Add appropriate error handling
4. Include basic tests if applicable
5. Commit all changes when done
6. Do NOT commit secrets, API keys, or credentials
""")
PYTASK

# =====================================================================
# Setup: opencode + autopilot
# =====================================================================

if ! command -v opencode &>/dev/null; then
  echo ">>> Installing opencode..."
  curl -fsSL https://opencode.ai/install | bash
  export PATH="$HOME/.opencode/bin:$PATH"
fi

echo ">>> opencode version: $(opencode --version 2>/dev/null || echo 'unknown')"

if ! command -v bun &>/dev/null; then
  echo ">>> Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

if ! bun pm ls -g 2>/dev/null | grep -q "opencode-autopilot"; then
  echo ">>> Installing autopilot plugin..."
  bun add -g @kodrunhq/opencode-autopilot
  bunx @kodrunhq/opencode-autopilot install --yes 2>/dev/null || true
fi

mkdir -p "$HOME/.config/opencode"
if [ -f "$SCRIPT_DIR/opencode-autopilot.json" ]; then
  cp "$SCRIPT_DIR/opencode-autopilot.json" "$HOME/.config/opencode/opencode-autopilot.json"
  echo ">>> Copied autopilot config"
fi

mkdir -p "$HOME/.config/opencode"
cp "$SCRIPT_DIR/opencode-runner.json" "$HOME/.config/opencode/opencode.json"

# Write API key files for {file:...} reference (opencode doesn't expand $ENV in JSON)
# These are placed in ~/.config/opencode/ which is where {file:...} resolves
if [ -n "${PROXY_API_KEY:-}" ]; then
  printf '%s' "$PROXY_API_KEY" > "$HOME/.config/opencode/vps-gateway.key"
  chmod 600 "$HOME/.config/opencode/vps-gateway.key"
fi
if [ -n "${NVIDIA_API_KEY:-}" ]; then
  printf '%s' "$NVIDIA_API_KEY" > "$HOME/.config/opencode/nvidia.key"
  chmod 600 "$HOME/.config/opencode/nvidia.key"
fi
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  printf '%s' "$OPENROUTER_API_KEY" > "$HOME/.config/opencode/openrouter.key"
  chmod 600 "$HOME/.config/opencode/openrouter.key"
fi

# Write minimal project config (just plugin) so {file:...} in user config resolves correctly
cat > "$TARGET_ROOT/.opencode.json" <<'EOF'
{
  "plugin": ["@kodrunhq/opencode-autopilot"]
}
EOF
echo ">>> Wrote user config + key files in ~/.config/opencode + minimal project config"

# =====================================================================
# Run opencode with autopilot
# =====================================================================
echo ">>> Running opencode with autopilot pipeline..."

AGENT_EXIT_CODE=0
opencode run --prompt-file .runner-task.md 2>&1 || AGENT_EXIT_CODE=$?

if [ $AGENT_EXIT_CODE -ne 0 ]; then
  echo ">>> opencode exited with code $AGENT_EXIT_CODE"
fi

# Run secret guard on all files before any commit
if [ -f "$SCRIPT_DIR/secret_guard.py" ]; then
  echo ">>> Scanning for leaked secrets..."
  python3 "$SCRIPT_DIR/secret_guard.py" . 2>/dev/null || {
    echo ">>> WARNING: Secret guard detected potential leaks!"
  }
fi

echo "true" > /tmp/agent-success.txt
echo "=== Agent run complete ==="
ls -la
