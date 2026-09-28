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

# Commands that write commit, tag, PR, issue or release text.
writer_regex='(^|[^[:alnum:]_-])(git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|tag|notes|merge|rebase|revert|cherry-pick|am)|gh[[:space:]]+(pr|issue|release|api|repo))([[:space:]]|$)'

text=""

if [[ "$tool_name" == "Bash" ]]; then
    command=$(jq -r '.tool_input.command // empty' <<<"$payload")
    grep -qiE "$writer_regex" <<<"$command" || exit 0
    text="$command"

    # Messages passed by file (git commit -F, gh --body-file / -F) never appear in the command itself.
    while IFS= read -r path; do
        path="${path%\"}"; path="${path#\"}"
        path="${path%\'}"; path="${path#\'}"
        [[ -z "$path" || "$path" == "-" ]] && continue
        [[ "$path" != /* && -n "$cwd" ]] && path="$cwd/$path"
        [[ -f "$path" ]] && text+=$'\n'"$(cat "$path")"
    done < <(grep -oE '(-F|--file|--body-file)(=|[[:space:]]+)("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]]+)' <<<"$command" \
        | sed -E 's/^(-F|--file|--body-file)(=|[[:space:]]+)//')
else
    # GitHub MCP tools (create_pull_request, create_or_update_file, add_issue_comment, ...): check every argument.
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
