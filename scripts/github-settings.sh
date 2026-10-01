#!/usr/bin/env bash
# Applies the repository settings of the backend, platform, and documentation repositories
# (docs/guides/engineering-workflow.md §4) with the GitHub CLI: description, homepage, topics, merge options,
# default branch, security features, and a branch ruleset. The frontend repositories are configured by their
# owner and are not listed.
#
# Usage:
#   scripts/github-settings.sh            print what would change (dry run)
#   scripts/github-settings.sh --apply    apply the settings (requires `gh auth login` with admin rights)
#
# Run it after `develop` and `main` exist on GitHub: the ruleset then requires pull requests for both.
set -euo pipefail

org="veritrace-platform"
homepage="https://github.com/${org}/veritrace"
apply=false
[[ "${1:-}" == "--apply" ]] && apply=true

common_topics="veritrace,supply-chain,traceability"

# repository|description|extra topics
repos=(
  "veritrace|Project home for VeriTrace: multi-tenant GS1 supply chain traceability with real-time cold-chain monitoring and blockchain-anchored verification. Docs, roadmap, decisions, and workspace tooling.|gs1,cold-chain,multi-tenant,architecture,documentation"
  "platform-infrastructure|VeriTrace runtime infrastructure: PostgreSQL + TimescaleDB, Kafka (KRaft), Mosquitto, Redis, and Caddy gateway with Docker Compose, plus the IoT fleet simulator.|docker-compose,postgresql,timescaledb,kafka,mqtt,iot"
  "core-business-service|VeriTrace core REST API in Go: tenants, identity, GS1 catalog, lots, inventory, shipments, custody handover, emergency recall, and a hash-chained event log.|golang,rest-api,postgresql,row-level-security,gs1"
  "telemetry-stream-service|VeriTrace telemetry service in Go: MQTT ingestion, Kafka streaming, TimescaleDB storage, cold-chain breach detection, and WebSocket notifications.|golang,mqtt,kafka,timescaledb,websocket,cold-chain,iot"
  "blockchain-relayer-service|VeriTrace gasless relayer in Go: Merkle batching of event hashes, nonce-safe Polygon commits, chain indexing, and inclusion proofs.|golang,blockchain,polygon,merkle-tree,redis"
  "smart-contracts|VeriTrace on-chain commitment contract for Merkle roots (Solidity, Foundry, OpenZeppelin, Polygon Amoy).|solidity,foundry,polygon,smart-contracts,merkle-tree"
  ".github|VeriTrace organization profile and shared community health files.|"
)

run() {
  if $apply; then
    "$@" >/dev/null
  else
    printf '  would run: %s\n' "$*"
  fi
}

ruleset_json() {
  cat <<'JSON'
{
  "name": "protect-main-and-develop",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main", "refs/heads/develop"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } }
  ]
}
JSON
}

for entry in "${repos[@]}"; do
  IFS='|' read -r repo description extra_topics <<<"$entry"
  echo "== ${org}/${repo}"

  run gh api -X PATCH "repos/${org}/${repo}" \
    -f description="$description" -f homepage="$homepage" \
    -F has_wiki=false -F allow_squash_merge=true -F allow_merge_commit=true -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true -F allow_update_branch=true \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
    -f merge_commit_title=PR_TITLE -f merge_commit_message=PR_BODY

  topics="$common_topics${extra_topics:+,$extra_topics}"
  topic_args=()
  IFS=',' read -ra topic_list <<<"$topics"
  for topic in "${topic_list[@]}"; do topic_args+=(-f "names[]=$topic"); done
  run gh api -X PUT "repos/${org}/${repo}/topics" "${topic_args[@]}"

  run gh api -X PUT "repos/${org}/${repo}/vulnerability-alerts"
  run gh api -X PUT "repos/${org}/${repo}/automated-security-fixes"
  run gh api -X PUT "repos/${org}/${repo}/private-vulnerability-reporting"

  if $apply; then
    # Visitors see released code; work pull requests target develop explicitly.
    gh api -X PATCH "repos/${org}/${repo}" -f default_branch=main >/dev/null
    if gh api "repos/${org}/${repo}/rulesets" --jq '.[].name' | grep -qx protect-main-and-develop; then
      echo "  ruleset already present"
    else
      ruleset_json | gh api -X POST "repos/${org}/${repo}/rulesets" --input - >/dev/null
    fi
  else
    printf '  would set default branch to main and create ruleset protect-main-and-develop\n'
  fi
done

$apply || echo -e "\nDry run only. Re-run with --apply to change the repositories."
