#!/usr/bin/env bash
# PreToolUse hook: deny any git/gh command, or GitHub MCP tool call, whose text attributes the work to
# Claude or Anthropic (Co-Authored-By trailers, "Generated with Claude Code" footers, session links).
#
# Reads the hook payload as JSON on stdin. Exits 0 with no output to allow the call, or prints a
# PreToolUse "deny" decision so Claude Code blocks it and tells the model why.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "reject-advertising-hook: jq is required but was not found on PATH" >&2
    exit 1
fi

payload=$(cat)
tool_name=$(jq -r '.tool_name // empty' <<<"$payload")
cwd=$(jq -r '.cwd // empty' <<<"$payload")

# Case-insensitive extended regexes for attribution text.
patterns=(
    'co-authored-by:.*(claude|anthropic)'
    'noreply@anthropic\.com'
    'generated (with|by) \[?claude'
    'claude\.ai/code'
    'claude-session:'
)

# Commands that write commit, tag, PR, issue, review, comment, release, gist or discussion text: git and gh
# subcommands, plus raw HTTP clients calling the GitHub API.
writer_regex='(^|[^[:alnum:]_-])(git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|tag|notes|merge|rebase|revert|cherry-pick|am)|gh[[:space:]]+(pr|issue|release|api|repo|gist))([[:space:]]|$)'
http_regex='(^|[^[:alnum:]_-])(curl|wget|http|xh)[[:space:]].*(api\.github\.com|/api/v3/|/api/graphql)'

quoted_token='("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]]+)'

# Appends the contents of a file named in the command to $text, resolving relative paths against the hook's cwd.
append_file() {
    local path="$1"
    path="${path%\"}"; path="${path#\"}"
    path="${path%\'}"; path="${path#\'}"
    [[ -z "$path" || "$path" == "-" ]] && return
    [[ "$path" != /* && -n "$cwd" ]] && path="$cwd/$path"
    [[ -f "$path" ]] && text+=$'\n'"$(cat "$path")"
}

text=""

if [[ "$tool_name" == "Bash" ]]; then
    command=$(jq -r '.tool_input.command // empty' <<<"$payload")
    grep -qiE "$writer_regex|$http_regex" <<<"$command" || exit 0
    text="$command"

    # Text passed by file never appears in the command itself:
    #   git commit -F msg, gh pr comment --body-file body.md, gh api --input payload.json
    while IFS= read -r path; do
        append_file "$path"
    done < <(grep -oE "(-F|--file|--body-file|--input)(=|[[:space:]]+)$quoted_token" <<<"$command" \
        | sed -E 's/^(-F|--file|--body-file|--input)(=|[[:space:]]+)//')

    #   gh api -F body=@comment.md, curl -d @comment.json, curl --data-binary @comment.json
    while IFS= read -r path; do
        append_file "$path"
    done < <(grep -oE "(-F|-f|--field|--raw-field|-d|--data|--data-binary|--data-raw|--data-urlencode|--body-file|--post-file)(=|[[:space:]]+)[\"']?[]A-Za-z0-9_.[-]*=?@[^[:space:]\"']+" <<<"$command" \
        | sed -E 's/^.*@//')
else
    # GitHub MCP tools (create_pull_request, add_issue_comment, add_comment_to_pending_review, ...): check every argument.
    text=$(jq -r '.tool_input | tostring' <<<"$payload")
fi

for pattern in "${patterns[@]}"; do
    if match=$(grep -oiE "$pattern" <<<"$text" | head -n 1) && [[ -n "$match" ]]; then
        jq -n --arg match "$match" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: ("Blocked by reject-advertising-hook: the text attributes this work to Claude (matched \"" + $match + "\"). Remove every Co-Authored-By trailer, \"Generated with Claude Code\" line and claude.ai session link, then retry.")
            }
        }'
        exit 0
    fi
done

exit 0
