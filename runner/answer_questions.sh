#!/usr/bin/env bash
# answer_questions.sh - Use LLM to answer questions from QUESTIONS.md
set -euo pipefail

PACKET_FILE="${1:?Usage: answer_questions.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: answer_questions.sh <packet.json> <target-root>}"

cd "$TARGET_ROOT"

QUESTIONS_FILE=""
for f in QUESTIONS.md questions.md .planning/QUESTIONS.md; do
    if [ -f "$f" ]; then
        QUESTIONS_FILE="$f"
        break
    fi
done

if [ -z "$QUESTIONS_FILE" ]; then
    echo "No QUESTIONS.md found, nothing to answer"
    exit 0
fi

echo "=== Question Answering Agent ==="
echo "Found: $QUESTIONS_FILE"

QUESTIONS=$(grep -E '^\s*-\s*\[[ x]?\]\s*|^\s*\d+\.\s*|^[-*]\s+[A-Z]' "$QUESTIONS_FILE" 2>/dev/null | head -20 || cat "$QUESTIONS_FILE" | head -30)

if [ -z "$QUESTIONS" ]; then
    echo "No questions found to answer"
    exit 0
fi

echo "Questions to answer:"
echo "$QUESTIONS"
echo "---"

echo "$QUESTIONS" > /tmp/runner-questions.txt

python3 << 'PYGEN'
import json, os, sys
import urllib.request

questions = open("/tmp/runner-questions.txt").read()
root = os.environ.get("TARGET_ROOT", ".")

prompt = f"""You are a helpful assistant answering technical questions about a software project.

Here are questions from the project's QUESTIONS.md file:

{questions}

Provide clear, concise answers. If unsure, say so. Focus on actionable guidance."""

endpoints = []
groq_key = os.environ.get("GROQ_API_KEY", "")
openrouter_key = os.environ.get("OPENROUTER_API_KEY", "")

if groq_key:
    endpoints.append(("https://api.groq.com/openai/v1/chat/completions", groq_key, "llama-3.3-70b-versatile"))
if openrouter_key:
    endpoints.append(("https://openrouter.ai/api/v1/chat/completions", openrouter_key, "deepseek/deepseek-v4-flash:free"))

result = None
for url, api_key, model in endpoints:
    try:
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        data = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 4000, "temperature": 0.5}).encode()
        req = urllib.request.Request(url, data, headers)
        resp = urllib.request.urlopen(req, timeout=120)
        result = json.loads(resp.read())
        print(f"Using: {model}")
        break
    except Exception as e:
        print(f"{model} failed: {e}")

if result:
    answers = result["choices"][0]["message"]["content"]
    answers_file = os.path.join(root, "ANSWERS.md")
    with open(answers_file, "a" if os.path.exists(answers_file) else "w") as f:
        f.write(f"\n---\n*Generated on: {__import__('datetime').datetime.now().isoformat()}*\n\n")
        f.write(answers)
        f.write("\n")
    print(f"Wrote answers to: {answers_file}")
else:
    print("All LLM endpoints failed")
    sys.exit(1)
PYGEN

echo "=== Question answering complete ==="