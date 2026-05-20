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
    r"Bearer [A-Za-z0-9\-._~+/]{30,}=*",
]

FALSE_POSITIVE_PATTERNS = [
    r"\$\{?[A-Z_]+_API_KEY\}?",
    r"<[a-z_]+>",
    r"\bYOUR_[A-Z_]+\b",
    r"\bREPLACE[A-Z_]*\b",
    r"\bINSERT_[A-Z_]+\b",
    r"\bEXAMPLE_[A-Z_]+\b",
    r"sk-or-v1-[a-f0-9]{8}\.\.\.",
    r"ghp_[x*]+",
    r"\*\*\*",
]

IGNORED_DIRS = {".git", "__pycache__", ".venv", "node_modules", ".opencode", ".gitignore"}
DOC_EXTENSIONS = {".md", ".rst", ".txt", ".adoc"}


def _is_false_positive(line: str) -> bool:
    for fp in FALSE_POSITIVE_PATTERNS:
        if re.search(fp, line):
            return True
    return False


def scan_file(path: Path) -> list[str]:
    hits = []
    is_doc = path.suffix in DOC_EXTENSIONS
    try:
        content = path.read_text(errors="replace")
        for pattern in PATTERNS:
            for match in re.finditer(pattern, content):
                matched_text = match.group(0)
                start = max(0, match.start() - 80)
                end = min(len(content), match.end() + 80)
                context = content[start:end]
                if _is_false_positive(context):
                    continue
                if is_doc and matched_text.startswith("Bearer "):
                    line_start = content.rfind("\n", 0, match.start()) + 1
                    line_end = content.find("\n", match.end())
                    line = content[line_start:line_end] if line_end != -1 else content[line_start:]
                    if _is_false_positive(line):
                        continue
                hits.append(f" {path}: matched {pattern!r} -> {matched_text[:40]}")
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
