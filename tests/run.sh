#!/usr/bin/env bash
# Feeds sample PreToolUse payloads to the hook and checks each decision. Run: tests/run.sh

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/reject-advertising.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0

# expect <deny|allow> <description> <tool_name> <tool_input JSON>
expect() {
    local want="$1" description="$2" tool_name="$3" tool_input="$4" output got
    output=$(jq -n --arg tool "$tool_name" --arg cwd "$tmp" --argjson input "$tool_input" \
        '{tool_name: $tool, cwd: $cwd, tool_input: $input}' | "$hook")
    if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output" 2>/dev/null)" == "deny" ]]; then
        got="deny"
    else
        got="allow"
    fi

    if [[ "$got" == "$want" ]]; then
        passed=$((passed + 1))
        printf 'ok    %-5s %s\n' "$want" "$description"
    else
        failed=$((failed + 1))
        printf 'FAIL  %-5s %s (got %s)\n' "$want" "$description" "$got"
    fi
}

bash_input() {
    jq -n --arg command "$1" '{command: $command}'
}

printf 'Fix bug\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' >"$tmp/msg.txt"
printf '## Summary\n\nhttps://claude.ai/code/session_123\n' >"$tmp/body.md"
printf 'Fix bug\n\nPlain message.\n' >"$tmp/clean.txt"

# Denied: attribution in the command text
expect deny "commit trailer in -m" Bash "$(bash_input 'git commit -m "Fix bug

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"')"
expect deny "commit trailer in heredoc after cd" Bash "$(bash_input 'cd repo && git commit -F - <<EOF
Fix bug

Co-authored-by: Claude <noreply@anthropic.com>
EOF')"
expect deny "git -C commit with session trailer" Bash "$(bash_input "git -C /tmp/repo commit -m 'Fix

Claude-Session: https://claude.ai/code/session_1'")"
expect deny "PR body footer" Bash "$(bash_input 'gh pr create --title x --body "Summary

🤖 Generated with [Claude Code](https://claude.com/claude-code)"')"
expect deny "anthropic noreply address on amend" Bash "$(bash_input 'git commit --amend -m "x" --trailer "Signed-off-by: bot <noreply@anthropic.com>"')"

# Denied: attribution inside a message file
expect deny "commit -F file with trailer" Bash "$(bash_input 'git commit -F msg.txt')"
expect deny "gh --body-file with session link" Bash "$(bash_input "gh pr edit 12 --body-file=$tmp/body.md")"

# Denied: GitHub MCP tools
expect deny "MCP create_pull_request footer" mcp__github__create_pull_request \
    '{"title":"x","body":"Generated with Claude Code"}'

# Allowed
expect allow "plain commit" Bash "$(bash_input 'git commit -m "Cache routes in the PHP test workflow"')"
expect allow "commit -F clean file" Bash "$(bash_input 'git commit -F clean.txt')"
expect allow "searching for the trailer" Bash "$(bash_input 'grep -rn "Co-Authored-By: Claude" .')"
expect allow "git log grep for the trailer" Bash "$(bash_input 'git log --grep "Co-Authored-By: Claude"')"
expect allow "PR body that mentions Claude Code" Bash "$(bash_input 'gh pr create --title x --body "Documents the Claude Code attribution setting"')"
expect allow "MCP PR with clean body" mcp__github__create_pull_request '{"title":"x","body":"Summary"}'

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
