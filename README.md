# reject-advertising-hook

A Claude Code plugin that blocks commits, pull requests, issues, comments, reviews and releases whose text attributes the work to Claude.

The `attribution` setting stops Claude Code from supplying attribution text, but the model can still write it into a commit message or PR body by itself. This plugin adds a `PreToolUse` hook that checks the text before the command runs and denies the call when it finds any of:

- a `Co-Authored-By:` trailer naming Claude or Anthropic
- `noreply@anthropic.com`
- a "Generated with Claude Code" line
- a `claude.ai/code` session link or `Claude-Session:` trailer

The denial tells the model what matched, so it can remove the text and retry.

## What it checks

| Tool call | Text checked |
|---|---|
| `Bash` running `git commit`, `tag`, `notes`, `merge`, `rebase`, `revert`, `cherry-pick` or `am` | The command, plus any file passed with `-F` / `--file` |
| `Bash` running `gh pr`, `issue`, `release`, `api`, `repo` or `gist`, including `gh pr comment`, `gh issue comment` and `gh pr review` | The command, plus any file passed with `--body-file`, `-F`, `--input` or `-F field=@file` |
| `Bash` running `curl`, `wget`, `http` or `xh` against the GitHub API | The command, plus any file passed with `-d @file` / `--data-binary @file` |
| GitHub MCP tools for pull requests, commits, issues, releases, reviews, comments, discussions, gists and file pushes | Every argument |

Other commands, such as `grep` or `git log --grep`, can mention the same text without being blocked.

## Install

```sh
claude plugin marketplace add https://github.com/dashworthy/reject-advertising-hook.git
claude plugin install reject-advertising-hook@reject-advertising-hook
```

Run `/reload-plugins` or restart Claude Code to load the hook in open sessions.

Pair it with these user settings so Claude Code supplies no attribution text either:

```json
"attribution": { "commit": "", "pr": "", "sessionUrl": false }
```

## Requirements

- `bash` and `jq` on `PATH`

## Test

```sh
tests/run.sh
```

## License

[MIT](LICENSE.md)
