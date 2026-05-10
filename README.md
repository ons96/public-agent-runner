# Public Agent Runner

Autonomous coding agent runner using **free** GitHub Actions minutes (unlimited on public repos).

## How It Works

1. **VPS orchestrator** dispatches task packets via `repository_dispatch`
2. **This repo** receives packets and runs agentic coding workflows
3. **LLM Gateway** (VPS_IP_REDACTED:8000) provides AI capabilities with multi-provider fallback
4. **Results** are pushed as PRs to target repos

## Triggering a Task

```bash
# From VPS or local machine
gh workflow run runner-dispatch.yml \
  --repo ons96/public-agent-runner \
  -f packet='{"target_repo": "ons96/some-project", "task": "implement basic CLI"}'
```

Or via API:
```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/ons96/public-agent-runner/dispatches \
  -d '{"event_type": "code-task", "client_payload": {"target_repo": "ons96/some-project", "task": "implement feature X"}}'
```

## Security

- **No secrets in this repo** - uses scoped tokens passed at runtime
- **No private data** - only receives sanitized task descriptions
- **Target repos** are checked out with minimal permissions

## Supported Event Types

- `task-packet` - Full packet with all fields (from coordinator)
- `code-task` - Minimal format: just `target_repo` + `task`
- `answer-questions` - Answer questions from QUESTIONS.md (no coding)

## LLM Provider Stack

Uses VPS gateway as primary (centralizes rate limits):
1. VPS Gateway (VPS_IP_REDACTED:8000) - `coding-fast` virtual model
2. Direct Groq (fallback) - `llama-3.3-70b-versatile`

## Files

```
.github/workflows/
  runner-dispatch.yml    # Main workflow entry point
runner/
  validate_packet.py     # Packet validation
  checkout_target.sh     # Clone target repo
  run_agent.sh           # Execute agentic coding
  push_branch_and_pr.sh  # Create PR with changes
```

---
*Part of the [vps-gh-agent-loop](https://github.com/ons96/vps-gh-agent-loop) autonomous coding system*
