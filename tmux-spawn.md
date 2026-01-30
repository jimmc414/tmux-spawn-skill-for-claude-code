---
description: Spawn tmux sessions with optional Claude Code instances
argument-hint: <session-name> [--claude] [--panes N] [--prompt "..."] [--flags "..."] [--export "VAR=val"] [--kill] [--list]
---
<!-- Python environment configured in lib/tmux-spawn.sh during installation -->

# tmux-spawn

Spawn and manage tmux sessions where both you and Claude have read/write access.

## Usage

Parse the arguments from `$ARGUMENTS`:

```bash
# Source the library
source ~/.claude/lib/tmux-spawn.sh

# Parse arguments
ARGS="$ARGUMENTS"
SESSION=""
PANES=1
LAUNCH_CLAUDE=false
CLAUDE_FLAGS="--dangerously-skip-permissions"
INITIAL_PROMPT=""
EXPORT_VARS=""
ACTION="spawn"

# Extract session name (first non-flag argument)
for arg in $ARGS; do
    case "$arg" in
        --claude) LAUNCH_CLAUDE=true ;;
        --kill) ACTION="kill" ;;
        --list) ACTION="list" ;;
        --panes) ;; # Next arg is count
        --flags) ;; # Next arg is flags
        --prompt) ;; # Next arg is prompt
        --export) ;; # Next arg is env var
        [0-9]*)
            # Check if previous was --panes
            if [[ "$prev" == "--panes" ]]; then
                PANES="$arg"
            fi
            ;;
        --*) ;; # Skip other flags
        *)
            # Check context
            if [[ "$prev" == "--flags" ]]; then
                CLAUDE_FLAGS="$arg"
            elif [[ "$prev" == "--prompt" ]]; then
                INITIAL_PROMPT="$arg"
            elif [[ "$prev" == "--export" ]]; then
                # Accumulate env vars (can have multiple --export)
                EXPORT_VARS="$EXPORT_VARS $arg"
            elif [[ -z "$SESSION" ]]; then
                SESSION="$arg"
            fi
            ;;
    esac
    prev="$arg"
done
```

## Actions

### List Sessions (--list)
```bash
if [[ "$ACTION" == "list" ]]; then
    list_sessions
    exit 0
fi
```

### Kill Session (--kill)
```bash
if [[ "$ACTION" == "kill" ]]; then
    if [[ -z "$SESSION" ]]; then
        echo "Error: Session name required"
        exit 1
    fi
    kill_session "$SESSION"
    echo "Killed session: $SESSION"
    exit 0
fi
```

### Spawn Session
```bash
if [[ -z "$SESSION" ]]; then
    echo "Error: Session name required"
    echo "Usage: /tmux-spawn <session> [--claude] [--panes N] [--prompt \"...\"] [--export \"VAR=val\"] [--kill] [--list]"
    exit 1
fi

# Spawn the session
target=$(spawn_session "$SESSION" "$PANES" true)
WIN=$(get_window_index "$SESSION")

echo "Created session: $SESSION (window: $WIN, panes: $PANES)"

# Launch Claude if requested
if [[ "$LAUNCH_CLAUDE" == "true" ]]; then
    PANE_LIST=($(get_pane_indices "$SESSION"))

    if [[ $PANES -eq 1 ]]; then
        # Single pane - launch Claude with optional env vars
        if [[ -n "$EXPORT_VARS" ]]; then
            launch_claude_with_env "$target.${PANE_LIST[0]}" "$CLAUDE_FLAGS" "$INITIAL_PROMPT" 10 $EXPORT_VARS
            echo "Claude launched with env vars: $EXPORT_VARS"
        else
            launch_claude "$target.${PANE_LIST[0]}" "$CLAUDE_FLAGS" "$INITIAL_PROMPT"
        fi
        echo "Claude launched in pane ${PANE_LIST[0]}"
    else
        # Multiple panes - launch Claude in first pane
        if [[ -n "$EXPORT_VARS" ]]; then
            launch_claude_with_env "$target.${PANE_LIST[0]}" "$CLAUDE_FLAGS" "$INITIAL_PROMPT" 10 $EXPORT_VARS
            echo "Claude launched with env vars: $EXPORT_VARS"
        else
            launch_claude "$target.${PANE_LIST[0]}" "$CLAUDE_FLAGS" "$INITIAL_PROMPT"
        fi
        echo "Claude launched in pane ${PANE_LIST[0]}"
        echo "Additional panes available: ${PANE_LIST[@]:1}"
    fi

    if [[ -n "$INITIAL_PROMPT" ]]; then
        echo "Initial prompt passed at command line"
    fi
fi

echo ""
echo "Observer window opened. Session: $SESSION"
echo "Target format: $target.<pane>"
```

## Examples

```bash
# Simple session with shell
/tmux-spawn demo

# Session with 3 panes
/tmux-spawn workspace --panes 3

# Session with Claude
/tmux-spawn agent --claude

# Session with Claude and initial prompt
/tmux-spawn agent --claude --prompt "Read the README and summarize"

# Session with Claude, custom flags, and prompt
/tmux-spawn worker --claude --flags "--dangerously-skip-permissions" --prompt "Hello"

# Session with Claude and environment variable (for task list persistence)
/tmux-spawn phoenix --claude --export "CLAUDE_CODE_TASK_LIST_ID=abc-123" --prompt "/phoenix-weaver RESUME 0 session-id abc-123"

# Multiple env vars
/tmux-spawn worker --claude --export "VAR1=value1" --export "VAR2=value2"

# Multiple panes, Claude in first
/tmux-spawn multi --panes 3 --claude

# Kill a session
/tmux-spawn demo --kill

# List all sessions
/tmux-spawn --list
```

## After Spawning

Once a session is spawned, you can interact with it using library functions:

```bash
source ~/.claude/lib/tmux-spawn.sh

# Send a command to pane 1
send_command "mysession:1.1" "echo hello"

# Read output from pane 1
capture_pane "mysession:1.1" 20

# Send a prompt to Claude
send_to_claude "mysession:1.1" "Explain this code"

# Launch Claude with env vars (programmatic)
launch_claude_with_env "mysession:1.1" "--dangerously-skip-permissions" "/my-skill" 10 "CLAUDE_CODE_TASK_LIST_ID=xyz"

# Add another pane
new_pane=$(add_pane "mysession")

# Kill when done
kill_session "mysession"
```

## Key Patterns

1. **Target format**: `SESSION:WINDOW.PANE` (e.g., `demo:1.1`)
2. **Always split message from Enter** - prevents lost keystrokes
3. **Use Enter not C-m** for Claude CLI
4. **Window index may be 0 or 1** - always use `get_window_index`
5. **Rebalance with tiled layout** after adding panes
6. **Env vars via --export** - set before Claude launches (useful for CLAUDE_CODE_TASK_LIST_ID)
