#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from typing import Any


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("Usage: report_result.py <packet.json> <pr_url> <output.json>")

    packet = json.loads(Path(sys.argv[1]).read_text())
    pr_url = sys.argv[2]
    output_path = Path(sys.argv[3])

    agent_success = False
    success_file = Path("/tmp/agent-success.txt")
    if success_file.exists():
        agent_success = success_file.read_text().strip() == "true"

    if pr_url and pr_url.strip():
        status = "opened_pr"
    elif agent_success:
        status = "agent_completed_no_pr"
    else:
        status = "agent_failed"

    result: dict[str, Any] = {
        "task_id": packet.get("task_id", packet.get("id", "unknown")),
        "target_repo": packet.get("target_repo", packet.get("repo", "unknown")),
        "branch": packet.get("work_branch", packet.get("branch", "unknown")),
        "issue_number": packet.get("issue_number", ""),
        "pr_url": pr_url if pr_url else "",
        "status": status,
        "agent_success": agent_success,
        "checks_passed": False,
    }

    output_path.write_text(json.dumps(result, indent=2) + "\n")
    print(output_path)


if __name__ == "__main__":
    main()
