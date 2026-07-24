#!/usr/bin/env bash
# Release expo without letting a same-version installer update become a no-op.
set -u

err() { printf '%s\n' "$1" >&2; }
ok() { printf '%s\n' "$1"; }

if [ "$#" -ne 2 ]; then
  err 'usage: scripts/release.sh <patch|minor> "<commit message>"'
  exit 1
fi

kind=$1
message=$2
case $kind in
  patch|minor) ;;
  *) err "release kind must be patch or minor"; exit 1 ;;
esac

cd "$(dirname "$0")/.." || { err "cannot find repo root"; exit 1; }

branch=$(git branch --show-current 2>/dev/null || true)
if [ "$branch" != main ]; then
  err "current branch is not main"
  exit 1
fi

if ! git fetch origin main:refs/remotes/origin/main; then
  err "cannot fetch origin/main"
  exit 1
fi
if ! behind=$(git rev-list --count HEAD..origin/main 2>/dev/null); then
  err "cannot compare HEAD to origin/main"
  exit 1
fi
if [ "$behind" -ne 0 ]; then
  err "local main is behind origin/main - pull/rebase first"
  exit 1
fi

installed_user_sha() { # installed_plugins.json
  python3 - "$1" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        entries = json.load(source)["plugins"]["expo@expo"]
except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
    raise SystemExit(f"cannot read installed expo@expo entries: {exc}")

for entry in entries:
    if isinstance(entry, dict) and entry.get("scope") == "user":
        try:
            print(entry["gitCommitSha"])
        except KeyError:
            raise SystemExit("user-scope expo@expo entry has no gitCommitSha")
        break
else:
    raise SystemExit("no user-scope expo@expo entry in installed_plugins.json")
PY
}

dirty=$(git status --porcelain 2>/dev/null) || { err "cannot read git status"; exit 1; }
ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null) || {
  err "cannot compare HEAD to origin/main"
  exit 1
}
claude_present=false
if command -v claude >/dev/null 2>&1; then
  claude_present=true
fi

resume_push=false
resume_refresh=false
if [ -z "$dirty" ] && [ "$ahead" -ne 0 ] &&
  git show --format= --name-only HEAD | grep -qx '.claude-plugin/plugin.json'; then
  ok "resuming: pushing existing release commit"
  resume_push=true
elif [ -z "$dirty" ] && [ "$ahead" -eq 0 ] && [ "$claude_present" = true ]; then
  expected_sha=$(git rev-parse HEAD) || { err "cannot read HEAD"; exit 1; }
  install_file="$HOME/.claude/plugins/installed_plugins.json"
  installed_sha=$(installed_user_sha "$install_file" 2>/dev/null || true)
  if [ -n "$installed_sha" ] && [ "$installed_sha" != "$expected_sha" ]; then
    ok "resuming: refreshing install"
    resume_refresh=true
  fi
fi

if [ -z "$dirty" ] && [ "$ahead" -eq 0 ] && [ "$resume_refresh" = false ]; then
  err "nothing to release"
  exit 1
fi

if [ "$resume_push" = false ] && [ "$resume_refresh" = false ]; then
  # Check BEFORE bumping - a failed check must not leave a half-applied bump in the
  # tree, where a rerun would double-bump the version.
  if ! bash scripts/check.sh; then
    err "full check failed"
    exit 1
  fi

  plugin_backup=$(mktemp) || { err "cannot create backup file"; exit 1; }
  cp .claude-plugin/plugin.json "$plugin_backup" || {
    err "cannot capture plugin version before bump"
    exit 1
  }
  bump_in_progress=true
  restore_bump() {
    cp "$plugin_backup" .claude-plugin/plugin.json ||
      err "cannot restore plugin version after failed bump"
  }
  release_exit() {
    status=$?
    if [ "$status" -ne 0 ] && [ "$bump_in_progress" = true ]; then
      restore_bump
    fi
    exit "$status"
  }
  trap release_exit EXIT

  if ! versions=$(python3 - "$kind" 2>/dev/null <<'PY'
import json
import sys

path = ".claude-plugin/plugin.json"
kind = sys.argv[1]
try:
    with open(path, encoding="utf-8") as source:
        plugin = json.load(source)
    major, minor, patch = map(int, plugin["version"].split("."))
except (OSError, KeyError, ValueError) as exc:
    raise SystemExit(f"invalid plugin version: {exc}")

if kind == "patch":
    patch += 1
else:
    minor += 1
    patch = 0

old = plugin["version"]
plugin["version"] = f"{major}.{minor}.{patch}"
with open(path, "w", encoding="utf-8") as target:
    json.dump(plugin, target, indent=2, ensure_ascii=False)
    target.write("\n")
print(f"{old} -> {plugin['version']}")
PY
  ); then
    err "could not bump plugin version"
    exit 1
  fi
  ok "$versions"

  if ! git add -A; then
    err "git add failed"
    exit 1
  fi
  if ! git commit -m "$message"$'\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>'; then
    err "git commit failed"
    exit 1
  fi
  bump_in_progress=false
fi

if [ "$resume_refresh" = false ] && ! git push origin main; then
  err "git push failed"
  exit 1
fi

if ! version=$(python3 -c 'import json; print(json.load(open(".claude-plugin/plugin.json"))["version"])' 2>/dev/null); then
  err "cannot read released version"
  exit 1
fi
if [ "$claude_present" = false ]; then
  printf '%s\n' "warn claude CLI not installed - skipping local install refresh and verification"
  ok "released $version at $(git rev-parse --short HEAD) (local install verification skipped)"
  exit 0
fi

if ! claude plugin marketplace update expo; then
  err "plugin marketplace update failed"
  exit 1
fi
if ! claude plugin update expo@expo; then
  err "plugin update failed"
  exit 1
fi

expected_sha=$(git rev-parse HEAD) || { err "cannot read HEAD"; exit 1; }
install_file="$HOME/.claude/plugins/installed_plugins.json"
if ! installed_sha=$(installed_user_sha "$install_file"); then
  err "cannot read installed expo@expo user-scope gitCommitSha"
  exit 1
fi
if [ "$installed_sha" != "$expected_sha" ]; then
  err "installed copy does not match HEAD"
  exit 1
fi

ok "released $version at $(git rev-parse --short HEAD)"
