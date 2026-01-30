# tmux-spawn

A Claude Code skill for spawning observable tmux sessions with optional Claude instances.

<img width="1872" height="621" alt="Screenshot 2026-01-30 120250" src="https://github.com/user-attachments/assets/1db5c5eb-900b-4a91-aa2a-0e6946f19597" />

Also works with anything else you can run at the command line.

![1768892788702](https://github.com/user-attachments/assets/e568cee9-3627-4521-944e-8b4353880029)

## Why

Claude Code runs in your terminal. When it spawns background work or parallel agents, you can't see what's happening. This skill creates tmux sessions that automatically open an observer window, so you can watch Claude work in real-time.

Useful for:
- Running Claude agents you want to monitor
- Parallel workstreams in separate panes
- Long-running tasks that benefit from visibility
- Debugging agent behavior

## Components

**`tmux-spawn.md`** - The skill definition. Gives Claude Code the `/tmux-spawn` command.

**`lib/tmux-spawn.sh`** - A bash library with functions for session management, command sending, and Claude launching. Can be sourced independently for scripting.

## Quick Start

In Claude Code, reference the install prompt and ask it to install:

```
> @install_prompt.md install this skill
```

Claude will read the file and ask you questions about installation scope, Python environment, and default launch flags. It may ask follow-up questions to clarify your preferences.

## Manual Installation

Copy files to your Claude config directory:

```bash
# Global installation
mkdir -p ~/.claude/commands ~/.claude/lib
cp tmux-spawn.md ~/.claude/commands/
cp lib/tmux-spawn.sh ~/.claude/lib/

# Edit lib/tmux-spawn.sh to set your Python environment:
# TMUX_SPAWN_ENV_TYPE="conda"  # or: venv, system, none
# TMUX_SPAWN_ENV_NAME="myenv"  # env name or path to venv

# Optionally edit tmux-spawn.md to change default Claude flags:
# CLAUDE_FLAGS="--dangerously-skip-permissions"  # or your preference
```

## Usage

You can invoke the skill with explicit flags or natural language. Both work.

### Natural Language

```
"Spawn a tmux session called work"
"Create a session named agent with Claude running in it"
"I need 3 panes in a session called multi, put Claude in the first one"
"Launch a background Claude agent in tmux that I can observe"
"Kill the work session"
"List my tmux sessions"
```

Claude will interpret these requests and invoke the skill with appropriate arguments.

### Explicit Flags

```bash
# Basic session
/tmux-spawn work

# Session with Claude instance
/tmux-spawn agent --claude

# Multiple panes, Claude in first
/tmux-spawn multi --panes 3 --claude

# With initial prompt
/tmux-spawn agent --claude --prompt "Read the codebase and summarize"

# Pass environment variables to Claude
/tmux-spawn worker --claude --export "MY_VAR=value"

# List sessions
/tmux-spawn --list

# Kill session
/tmux-spawn work --kill
```

## Library Functions

The bash library can be sourced for direct use:

```bash
source ~/.claude/lib/tmux-spawn.sh

target=$(spawn_session "demo" 3)    # 3 panes
send_command "$target.1" "echo hi"  # send to pane 1
capture_pane "$target.1" 20         # read last 20 lines
kill_session "demo"
```

Key functions: `spawn_session`, `kill_session`, `send_command`, `capture_pane`, `launch_claude`, `add_pane`

## Pane Scaling

When you request multiple panes, the library:

1. Creates the session with a single pane
2. Splits iteratively, applying `tiled` layout after each split
3. Rebalances at the end for even distribution

```bash
/tmux-spawn work --panes 4
```

Results in a 2x2 grid. Pane indices are discovered dynamically since tmux configurations vary (some start at 0, others at 1).

With `--claude`, Claude launches in the first pane. Remaining panes are available for manual use or programmatic control:

```bash
source ~/.claude/lib/tmux-spawn.sh

# Add a pane to existing session (auto-rebalances)
new_pane=$(add_pane "work")

# Send commands to specific panes
send_command "work:1.0" "npm run dev"
send_command "work:1.1" "npm run test -- --watch"

# Launch Claude in a specific pane
launch_claude "work:1.2" "--dangerously-skip-permissions" "review the test output"
```

The target format is `SESSION:WINDOW.PANE`. Window index is looked up via `get_window_index` rather than assumed, since tmux's `base-index` setting varies.

## Platform Support

- WSL2: Opens Windows Terminal tab
- macOS: Opens Terminal.app window
- Linux: Tries gnome-terminal, xterm, or prints attach command

## Requirements

- tmux
- Claude Code CLI (for `--claude` flag)
