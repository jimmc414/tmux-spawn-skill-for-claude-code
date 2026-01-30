# Install tmux-spawn Skill

Install this skill and its library for Claude Code.

## What This Skill Does

Spawns tmux sessions with optional Claude Code instances. Useful for background agents, parallel work, observable automation.

## Installation

Use AskUserQuestion to gather user preferences. Call it as many times as needed to fully clarify requirements before proceeding.

Questions to ask:

1. **Scope**: Global (`~/.claude/`) or project-level (`./.claude/`)?

2. **Python environment** for Claude CLI:
   - Conda (ask for env name)
   - Venv (ask for path)
   - System Python (no activation)
   - None/Manual

3. **Default Claude launch flags**: Keep default (`--dangerously-skip-permissions`) or specify different flags?
   - Common alternatives: `--allowedTools`, `--permission-mode`, or no special flags
   - If user wants custom flags, ask what they should be

Check if `tmux` is installed. If missing, offer to install it for the user's platform.

Modify source files **in-place** with user's choices:
- In `lib/tmux-spawn.sh`, set `TMUX_SPAWN_ENV_TYPE` and `TMUX_SPAWN_ENV_NAME` based on Python environment choice
- In `tmux-spawn.md`, update `CLAUDE_FLAGS` default if user specified custom flags

Then copy to target location:
- `tmux-spawn.md` → `{scope}/commands/`
- `lib/tmux-spawn.sh` → `{scope}/lib/`

Verify installation works with `/tmux-spawn --list`.

## Files

- `tmux-spawn.md` - Skill definition (the `/tmux-spawn` command)
- `lib/tmux-spawn.sh` - Bash library (functions for session/pane management)
