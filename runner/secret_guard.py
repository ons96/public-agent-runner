import re
import sys
from pathlib import Path

PATTERNS = [
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"gh[pousr]_[A-Za-z0-9]{20,}",
    r"AIza[0-9A-Za-z\-_]{20,}",
    r"sk-[A-Za-z0-9]{20,}",
    r"sk_live_[A-Za-z0-9]{20,}",
    r"rk_live_[A-Za-z0-9]{20,}",
    r"AKIA[A-Z0-9]{16}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"Bearer [A-Za-z0-9\-._~+/]+=*",
]

IGNORED_DIRS = {".git", "__pycache__", ".venv", "node_modules", ".opencode", ".gitignore"}


def scan_file(path: Path) -> list[str]:
    hits = []
    try:
        content = path.read_text(errors="replace")
        for pattern in PATTERNS:
            if re.search(pattern, content):
                hits.append(f"  {path}: matched {pattern}")
    except (OSError, UnicodeDecodeError):
        pass
    return hits


def scan_dir(path: Path) -> list[str]:
    hits = []
    for entry in path.rglob("*"):
        if entry.is_dir() or any(ign in entry.parts for ign in IGNORED_DIRS):
            continue
        hits += scan_file(entry)
    return hits


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: secret_guard.py <path>")

    target = Path(sys.argv[1])
    if not target.exists():
        raise SystemExit(f"Path not found: {target}")

    hits = scan_dir(target) if target.is_dir() else scan_file(target)

    if hits:
        print("SECRET GUARD FAILED — potential secrets detected:")
        for h in hits:
            print(h)
        raise SystemExit(1)
    print("Secret guard passed")


if __name__ == "__main__":
    main()
