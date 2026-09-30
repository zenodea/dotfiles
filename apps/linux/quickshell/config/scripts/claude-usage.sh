#!/usr/bin/env bash

creds="$HOME/.claude/.credentials.json"

text() {
    grep -o "\"$1\":\"[^\"]*\"" "$creds" 2> /dev/null | head -n 1 | cut -d'"' -f4
}

number() {
    grep -o "\"$1\":[0-9]*" "$creds" 2> /dev/null | head -n 1 | cut -d: -f2
}

token=$(text accessToken)
[[ -n "$token" ]] || exit 2

expires=$(number expiresAt)
[[ -n "$expires" ]] && ((expires / 1000 < $(date +%s))) && exit 3

usage=$(
    curl -fsS --max-time 10 -K - https://api.anthropic.com/api/oauth/usage << EOF
header = "Authorization: Bearer $token"
header = "anthropic-beta: oauth-2025-04-20"
EOF
) || exit 1

printf '{"plan":"%s","usage":%s}\n' "$(text subscriptionType)" "$usage"
