# SECURITY SCRUB RECOVERY

This file exists because `git filter-repo` rewrote all git history in this repo
to remove accidentally-committed VPS IP addresses and gateway API keys.

If you are reading this on a machine that already had this repo cloned before
2026-05-19, **your clone has diverged from origin** and you must follow the
steps below to sync up.  Old secrets that were removed from history are still
present in your local `.git` objects until you do.

## Are you affected?

Check one of these:

```bash
git log --oneline --all | head -3
# If you see commits from before 2026-05-19 with NEW hashes (not the ones
# you remember), you have the new history.  You are fine.

grep -r "40.233.101.233" .git/ --include="*" 2>/dev/null | head -3
# If this prints anything, your clone still has the old history.
```

Typical symptoms of an out-of-date clone:
- `git pull` says "everything up to date" but files are clearly stale
- `git log` shows different commit hashes than what you see on GitHub
- `git push` is rejected with "non-fast-forward" errors

## Recovery steps

### 1. Sync this clone to the rewritten history

```bash
cd /path/to/repo/clone

# Stash local changes
git stash

# Fetch all rewritten branches/tags
git fetch --force --all
git fetch --force --tags

# Reset your local branches to match origin
git checkout main
git reset --hard origin/main

# Repeat for every other local branch you care about:
#   git checkout <branch>
#   git reset --hard origin/<branch>

# Drop the stash (may fail if you had nothing stashed — that is OK)
git stash drop 2>/dev/null || true

# Prune old unreachable objects
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

After this, `grep -r "40.233.101.233" .git/` should return nothing.

### 2. (If you had local branches not on origin)

Rebase them onto the rewritten history instead of force-pushing:

```bash
git checkout my-feature-branch
git rebase --onto origin/main <old-base-sha>
```

### 3. Tell every other machine

If you work on this repo from multiple machines, repeat step 1 on each one.

---

## Files created during the scrub

| File | Purpose |
|------|---------|
| `.secrets.baseline` | detect-secrets baseline (all false positives marked) |
| `.secrets-baseline-config.json` | detect-secrets config (ignore patterns) |

These are optional.  If you do not want detect-secrets, delete both.  No
secrets were ever committed to these files.

## detect-secrets pre-commit hook

If you want automatic secret scanning before every commit on this machine:

```bash
pip3 install detect-secrets           # or: pipx install detect-secrets
# Verify the hook works:
detect-secrets-hook --baseline .secrets.baseline --stdin <<< "safe text"
```

The baseline is already committed; the hook itself (`pre-commit`) is installed
in `.git/hooks/` and does NOT survive re-clone.  You must re-install on each
new clone.

## For the VPS / Tailscale-reachable machine

The gateway API key `poop96` was exposed in the public repo for ~9 days.
From a machine on Tailscale, verify the key has been rotated:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer poop96" \
  http://<GATEWAY_IP>:8000/v1/models
```

- **200** → key is still active — rotate it on the LiteLLM gateway now
- **401** → already rotated — all clear

Also check the LiteLLM proxy logs for unexpected access during the exposure
window (2026-05-10 to 2026-05-19):

```bash
ssh <VPS> sudo journalctl -u litellm \
  --since "2026-05-10" --until "2026-05-19"
```

## For opencode / AI agent sessions on other machines

If you are an AI agent reading this at the start of a session:

1. Check `git status` and `git log --oneline -3` for signs of divergence
2. If this repo looks stale, run the "Sync this clone" commands above
3. Verify no old secrets remain with `grep -r "40.233.101.233\|poop96" . --include="*" 2>/dev/null`
4. The `.secrets.baseline` file in the repo root is a detect-secrets audit file
   (all findings are verified false positives).  Ignore it unless you want to
   add secret scanning to this project.
