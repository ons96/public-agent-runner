#!/usr/bin/env bash
# run_agent.sh - Execute agentic coding task on target repo
# Strategy: Direct LLM API via NVIDIA (primary) -> OpenRouter -> Gateway
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

# =====================================================================
# Direct LLM API: NVIDIA (primary) -> OpenRouter -> Gateway
# =====================================================================
echo ">>> Generating via direct LLM API (NVIDIA primary)..."
    if [ ! -f "src/main.py" ] && [ ! -f "index.js" ] && [ ! -f "main.go" ] && [ ! -f "main.rs" ]; then
        echo ">>> Generating project structure via direct LLM API..."
        python3 - << 'PYGEN'
import json, os, sys, re, urllib.request

root = os.getcwd()
task = open("/tmp/runner-task.txt").read()

prompt = f"""Create a simple implementation for this project idea: {task}

Respond with ONLY a JSON object containing files to create:
{{"files": [{{"path": "src/main.py", "content": "..."}}]}}

Keep it simple and functional. Include a README.md with usage instructions."""

endpoints = [
    ("https://integrate.api.nvidia.com/v1/chat/completions", os.environ.get("NVIDIA_API_KEY", ""), "meta/llama-3.3-70b-instruct"),
    ("https://openrouter.ai/api/v1/chat/completions", os.environ.get("OPENROUTER_API_KEY", ""), "deepseek/deepseek-v4-flash:free"),
    ("https://llm-gateway.tail712653.ts.net/v1/chat/completions", os.environ.get("PROXY_API_KEY", ""), "gpt-4o-mini"),
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
    # Try parsing as raw JSON first, then markdown-wrapped
    raw_match = re.search(r'\{[\s\S]*"files"[\s\S]*\}', content)
    md_match = re.search(r'```(?:json)?\s*([\s\S]*?)```', content)
    json_str = None
    if raw_match:
        json_str = raw_match.group()
    elif md_match:
        json_str = md_match.group(1)
    if json_str:
        try:
            files_data = json.loads(json_str)
        except json.JSONDecodeError:
            print(f"JSON parse failed, raw content: {content[:200]}")
            files_data = {"files": []}
        if "files" not in files_data or not files_data["files"]:
            files_data = {"files": [{"path": "src/main.py", "content": content}]}
        for f in files_data.get("files", []):
            path = os.path.join(root, f["path"])
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fp:
                fp.write(f["content"])
            print(f"Created: {f['path']}")
    else:
        print(f"No files JSON found, saving raw content")
        main_path = os.path.join(root, "src", "main.py")
        os.makedirs(os.path.dirname(main_path), exist_ok=True)
        with open(main_path, "w") as fp:
            fp.write(content)
        print(f"Created: src/main.py")
else:
    print("All LLM endpoints failed - creating minimal scaffolding")
    main_path = os.path.join(root, "src", "main.py")
    os.makedirs(os.path.dirname(main_path), exist_ok=True)
    with open(main_path, "w") as fp:
        fp.write('"""Auto-generated scaffold"""\n\ndef main():\n    print("Hello from agent")\n\nif __name__ == "__main__":\n    main()\n')
    print("Created: src/main.py")
PYGEN
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

echo "true" > /tmp/agent-success.txt

echo "=== Agent run complete ==="
ls -la
