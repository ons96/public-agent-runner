#!/usr/bin/env bash
# answer_questions.sh - Use LLM to answer questions from QUESTIONS.md
# Saves answers to ANSWERS.md without modifying code
set -euo pipefail

PACKET_FILE="${1:?Usage: answer_questions.sh <packet.json> <target-root>}"
TARGET_ROOT="${2:?Usage: answer_questions.sh <packet.json> <target-root>}"

cd "$TARGET_ROOT"

# Find questions file
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

# Extract unanswered questions (lines starting with - [ ] or similar patterns)
QUESTIONS=$(grep -E '^\s*-\s*\[[ x]?\]\s*|^\s*\d+\.\s*|^[-*]\s+[A-Z]' "$QUESTIONS_FILE" 2>/dev/null | head -20 || cat "$QUESTIONS_FILE" | head -30)

if [ -z "$QUESTIONS" ]; then
    echo "No questions found to answer"
    exit 0
fi

echo "Questions to answer:"
echo "$QUESTIONS"
echo "---"

# Call LLM gateway to answer questions
python3 << 'PYGEN' "$QUESTIONS" "$TARGET_ROOT"
import json, os, sys
import urllib.request

questions = sys.argv[1]
root = sys.argv[2]

prompt = f"""You are a helpful assistant answering technical questions about a software project.

Here are questions from the project's QUESTIONS.md file:

{questions}

Please provide clear, concise answers to each question. Format your response as:

## Answers

### Q1: [First question summary]
[Your answer]

### Q2: [Second question summary]
[Your answer]

... and so on.

If you're unsure about something, say so honestly. Focus on actionable guidance."""

# Try VPS gateway first
endpoints = [
    ("http://VPS_IP_REDACTED:8000/v1/chat/completions", os.environ.get("PROXY_API_KEY", "GATEWAY_KEY_REDACTED"), "chat-smart"),
    ("https://api.groq.com/openai/v1/chat/completions", os.environ.get("GROQ_API_KEY", ""), "llama-3.3-70b-versatile"),
]

result = None
for url, api_key, model in endpoints:
    if not api_key:
        continue
    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        data = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 4000,
            "temperature": 0.5
        }).encode()
        
        req = urllib.request.Request(url, data, headers)
        resp = urllib.request.urlopen(req, timeout=120)
        result = json.loads(resp.read())
        print(f"Using: {url} ({model})")
        break
    except Exception as e:
        print(f"Endpoint {url} failed: {e}")
        continue

if result:
    answers = result["choices"][0]["message"]["content"]
    
    # Write to ANSWERS.md
    answers_file = os.path.join(root, "ANSWERS.md")
    with open(answers_file, "a" if os.path.exists(answers_file) else "w") as f:
        f.write(f"\n---\n*Generated on: {__import__('datetime').datetime.now().isoformat()}*\n\n")
        f.write(answers)
        f.write("\n")
    print(f"Wrote answers to: {answers_file}")
    print(answers[:500] + "..." if len(answers) > 500 else answers)
else:
    print("All LLM endpoints failed")
    sys.exit(1)
PYGEN

echo "=== Question answering complete ==="
