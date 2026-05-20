#!/usr/bin/env bash
# run_agent.sh - Execute agentic coding task on target repo
# Priority: Stock OpenCode (efficient) -> OMO (autonomous) -> Direct LLM API
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

echo "=== Runner Agent ==="
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

Implement this project following these principles:
1. Use simple, maintainable code
2. Add appropriate error handling
3. Include basic tests if applicable
4. Update README.md with usage instructions
""")
PYTASK

AGENT_SUCCESS=false

# =====================================================================
# OPTION 1: Stock OpenCode (most token-efficient)
# =====================================================================
if command -v opencode &>/dev/null; then
    echo ">>> Trying stock OpenCode (efficient mode)..."

    if [ -f "$SCRIPT_DIR/opencode-runner.json" ] && [ -s "$SCRIPT_DIR/opencode-runner.json" ]; then
        cp "$SCRIPT_DIR/opencode-runner.json" .opencode.json
        echo ">>> Copied opencode-runner.json to .opencode.json"
    else
        echo ">>> WARNING: opencode-runner.json is empty or missing"
    fi

    export OPENCODE_PROVIDER_VPS_GATEWAY_API_KEY="${PROXY_API_KEY:-}"
    export OPENCODE_PROVIDER_GROQ_API_KEY="${GROQ_API_KEY:-}"

    set +e
    timeout 3600 opencode run "$TASK_TEXT" --format json 2>&1 | tee .runner-log.txt
    PIPE_EXIT=${PIPESTATUS[0]}
    set -e

    if [ "$PIPE_EXIT" -eq 0 ]; then
        # Check for real errors (not null errors)
        python3 -c "
import json, sys
errors = []
for line in open('.runner-log.txt'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    err = obj.get('error')
    if err is not None:
        errors.append(err)
if errors and any(e != 'null' for e in errors):
    sys.exit(1)
" 2>/dev/null && {
            echo ">>> OpenCode completed successfully"
            AGENT_SUCCESS=true
        } || {
            echo ">>> OpenCode returned API error in output, trying fallback..."
        }
    else
        echo ">>> OpenCode exited with code $PIPE_EXIT, trying fallback..."
    fi
fi

# =====================================================================
# OPTION 2: oh-my-opencode (autonomous mode)
# =====================================================================
if [ "$AGENT_SUCCESS" = false ]; then
    if command -v omo &>/dev/null || command -v bunx &>/dev/null; then
        echo ">>> Trying oh-my-opencode (autonomous mode)..."
        if ! command -v omo &>/dev/null; then
            bunx oh-my-opencode install --no-tui --claude=no --openai=no --gemini=no --opencode-go=no 2>/dev/null || true
        fi
        if command -v omo &>/dev/null; then
            set +e
            timeout 3600 omo --task "$TASK_TEXT" --auto-approve 2>&1 | tee -a .runner-log.txt
            OMO_EXIT=$?
            set -e
            if [ "$OMO_EXIT" -eq 0 ]; then
                echo ">>> OMO completed successfully"
                AGENT_SUCCESS=true
            else
                echo ">>> OMO exited with code $OMO_EXIT"
            fi
        fi
    fi
fi

# =====================================================================
# OPTION 3: Direct LLM API (fallback for simple code generation)
# =====================================================================
if [ "$AGENT_SUCCESS" = false ]; then
    if [ ! -f "src/main.py" ] && [ ! -f "index.js" ] && [ ! -f "main.go" ] && [ ! -f "main.rs" ]; then
        echo ">>> Generating initial project structure via direct LLM API..."
        python3 - "$TARGET_ROOT" << 'PYGEN'
import json, os, sys, re, urllib.request

root = sys.argv[1]
task = open("/tmp/runner-task.txt").read()

prompt = f"""Create a simple implementation for this project idea: {task}

Respond with ONLY a JSON object containing files to create:
{{"files": [{{"path": "src/main.py", "content": "..."}}]}}

Keep it simple and functional. Include a README.md with usage instructions."""

endpoints = [
    ("https://api.groq.com/openai/v1/chat/completions", os.environ.get("GROQ_API_KEY", ""), "llama-3.3-70b-versatile"),
    ("https://openrouter.ai/api/v1/chat/completions", os.environ.get("OPENROUTER_API_KEY", ""), "deepseek/deepseek-v4-flash:free"),
    ("https://integrate.api.nvidia.com/v1/chat/completions", os.environ.get("NVIDIA_API_KEY", ""), "meta/llama-3.3-70b-instruct"),
]

result = None
for url, api_key, model in endpoints:
    if not api_key:
        continue
    try:
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        data = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 4000,
            "temperature": 0.3
        }).encode()
        req = urllib.request.Request(url, data, headers)
        resp = urllib.request.urlopen(req, timeout=120)
        result = json.loads(resp.read())
        print(f"Using: {url} ({model})")
        break
    except Exception as e:
        print(f"Endpoint {url} ({model}) failed: {e}")
        continue

if result:
    content = result["choices"][0]["message"]["content"]
    match = re.search(r'\{[\s\S]*"files"[\s\S]*\}', content)
    if match:
        files_data = json.loads(match.group())
        for f in files_data.get("files", []):
            path = os.path.join(root, f["path"])
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fp:
                fp.write(f["content"])
            print(f"Created: {f['path']}")
    else:
        print("LLM response did not contain valid files JSON")
else:
    print("All LLM endpoints failed - creating minimal scaffolding")
    main_path = os.path.join(root, "src", "main.py")
    os.makedirs(os.path.dirname(main_path), exist_ok=True)
    with open(main_path, "w") as fp:
        fp.write('"""Auto-generated scaffold"""\n\ndef main():\n    print("Hello from agent")\n\nif __name__ == "__main__":\n    main()\n')
    print("Created: src/main.py")
PYGEN
    fi
fi

# Run secret guard on all files before any commit
if [ -f "$SCRIPT_DIR/secret_guard.py" ]; then
    echo ">>> Scanning for leaked secrets..."
    python3 "$SCRIPT_DIR/secret_guard.py" . 2>/dev/null || {
        echo ">>> WARNING: Secret guard detected potential leaks!"
    }
fi

if [ ! -f README.md ]; then
    cat > README.md << EOF
# $(basename "$TARGET_REPO")

$TASK_TEXT

## Setup

\`\`\`bash
pip install -r requirements.txt
\`\`\`

---
*Generated by autonomous coding agent*
EOF
fi

# Write agent status for report_result.py
if [ "$AGENT_SUCCESS" = true ]; then
    echo "true" > /tmp/agent-success.txt
else
    echo "false" > /tmp/agent-success.txt
fi

echo "=== Agent run complete ==="
ls -la
