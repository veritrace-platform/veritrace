#!/usr/bin/env bash
# Manages the side-by-side checkout of every VeriTrace repository.
#
# Usage:
#   scripts/workspace.sh clone    clone every repository that is missing next to this one
#   scripts/workspace.sh status   show branch, pending changes, and upstream divergence of every repository
#
# VERITRACE_GIT_BASE overrides the remote base, e.g. git@github.com:veritrace-platform for SSH.
set -euo pipefail

git_base="${VERITRACE_GIT_BASE:-https://github.com/veritrace-platform}"
workspace="$(cd "$(dirname "$0")/../.." && pwd)"

repos=(
  veritrace
  platform-infrastructure
  core-business-service
  telemetry-stream-service
  blockchain-relayer-service
  smart-contracts
  enterprise-dashboard
  driver-mobile-pwa
  public-trace-portal
  .github
)

clone() {
  for repo in "${repos[@]}"; do
    if [[ -d "$workspace/$repo/.git" ]]; then
      printf '%-28s present\n' "$repo"
      continue
    fi
    printf '%-28s cloning\n' "$repo"
    # Development happens on develop; main (the default branch) only holds releases.
    git clone --quiet --branch develop "$git_base/$repo.git" "$workspace/$repo"
  done
}

status() {
  printf '%-28s %-28s %-8s %s\n' REPOSITORY BRANCH CHANGES UPSTREAM
  for repo in "${repos[@]}"; do
    dir="$workspace/$repo"
    if [[ ! -d "$dir/.git" ]]; then
      printf '%-28s %s\n' "$repo" "(missing: run 'make workspace')"
      continue
    fi
    branch="$(git -C "$dir" branch --show-current)"
    changes="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
    upstream="-"
    if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      read -r behind ahead < <(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD')
      upstream="ahead ${ahead}, behind ${behind}"
    fi
    printf '%-28s %-28s %-8s %s\n' "$repo" "${branch:-(detached)}" "$changes" "$upstream"
  done
}

case "${1:-}" in
  clone) clone ;;
  status) status ;;
  *)
    echo "usage: $0 clone|status" >&2
    exit 2
    ;;
esac
