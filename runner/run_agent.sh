#!/usr/bin/env bash
# run_agent.sh - Execute agentic coding task on target repo
# Priority: Stock OpenCode → Direct LLM API (free providers only)
set -euo pipefail

PACKET_FILE="${1:?Usage: run_agent.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: run_agent.sh <packet.json> <target-root>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$PACKET_FILE" > /tmp/runner-params.txt << 'PY'
import json, sys
from pathlib import Path
packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
task = packet.get('task', packet.get('task_summary', 'implement the project'))
mode = packet.get('mode', 'implement')
print(f"{repo}\t{mode}")
Path("/tmp/runner-task.txt").write_text(task)
PY

read -r TARGET_REPO MODE < /tmp/runner-params.txt
TASK_TEXT=$(cat /tmp/runner-task.txt)

echo "=== Runner Agent ==="
echo "Repo: $TARGET_REPO"
echo "Task: ${TASK_TEXT:0:100}..."
echo "Mode: $MODE"

cd "$TARGET_ROOT"

cat > .runner-task.md << EOF
# Agentic Coding Task

**Repository:** $TARGET_REPO
**Mode:** $MODE

## Task Description

$TASK_TEXT

## Instructions

Implement this project following these principles:
1. Use simple, maintainable code
2. Add appropriate error handling
3. Include basic tests if applicable
4. Update README.md with usage instructions
EOF

AGENT_SUCCESS=false

# =============================================================================
# OPTION 1: Stock OpenCode (most token-efficient)
# =============================================================================
if command -v opencode &>/dev/null; then
    echo ">>> Trying stock OpenCode (efficient mode)..."
    
    if [ -f "$SCRIPT_DIR/opencode-runner.json" ]; then
        cp "$SCRIPT_DIR/opencode-runner.json" .opencode.json
    fi
    
    export GROQ_API_KEY="${GROQ_API_KEY:-}"
    export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
    
    if timeout 3600 bash -c 'cat /tmp/runner-task.txt | opencode --dangerously-skip-permissions 2>&1' | tee .runner-log.txt; then
        echo ">>> OpenCode completed successfully"
        AGENT_SUCCESS=true
    else
        echo ">>> OpenCode failed or timed out, trying fallback..."
    fi
fi

# =============================================================================
# OPTION 2: Direct LLM API (fallback using free providers)
# =============================================================================
if [ "$AGENT_SUCCESS" = false ]; then
    echo ">>> Generating implementation via direct LLM API..."
    
    python3 << 'PYGEN'
import json, os, sys
import urllib.request

task = open("/tmp/runner-task.txt").read()
root = os.environ.get("TARGET_ROOT", ".")

prompt = f"""Create a simple implementation for this project idea:

{task}

Respond with ONLY a JSON object containing files to create:
{{"files": [{{"path": "src/main.py", "content": "..."}}]}}

Keep it simple and functional. Include a README.md with usage instructions."""

endpoints = []
groq_key = os.environ.get("GROQ_API_KEY", "")
openrouter_key = os.environ.get("OPENROUTER_API_KEY", "")

if groq_key:
    endpoints.append(("https://api.groq.com/openai/v1/chat/completions", groq_key, "llama-3.3-70b-versatile"))
if openrouter_key:
    endpoints.append(("https://openrouter.ai/api/v1/chat/completions", openrouter_key, "deepseek/deepseek-v4-flash:free"))
    endpoints.append(("https://openrouter.ai/api/v1/chat/completions", openrouter_key, "qwen/qwen3-coder:free"))

result = None
for url, api_key, model in endpoints:
    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        data = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 4000,
            "temperature": 0.3
        }).encode()
        
        req = urllib.request.Request(url, data, headers)
        resp = urllib.request.urlopen(req, timeout=120)
        result = json.loads(resp.read())
        print(f"Success using: {model}")
        break
    except Exception as e:
        print(f"Endpoint {model} failed: {e}")
        continue

if result:
    content = result["choices"][0]["message"]["content"]
    
    import re
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
    print("All LLM endpoints failed - creating minimal scaffolding")
    main_path = os.path.join(root, "src", "main.py")
    os.makedirs(os.path.dirname(main_path), exist_ok=True)
    with open(main_path, "w") as fp:
        fp.write(f'"""Auto-generated scaffold for: {task[:100]}"""\n\ndef main():\n    print("Hello from agent")\n\nif __name__ == "__main__":\n    main()\n')
    print("Created: src/main.py")
PYGEN
fi

# Ensure README exists
if [ ! -f README.md ]; then
    cat > README.md << EOF
# $(basename "$TARGET_REPO")

$(cat /tmp/runner-task.txt)

## Setup

\`\`\`bash
pip install -r requirements.txt
\`\`\`

---
*Generated by autonomous coding agent*
EOF
fi

echo "=== Agent run complete ==="
ls -la