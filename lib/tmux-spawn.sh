#!/bin/bash
# tmux-spawn.sh - Library for spawning and managing tmux sessions
# Used by /tmux-spawn skill and can be sourced by other scripts
#
# Critical patterns encoded:
# - Split message from Enter with sleep (prevents lost keystrokes)
# - Use Enter not C-m for Claude CLI (C-m creates newline)
# - Dynamic window index discovery (may be 0 or 1)
# - Tiled layout after pane creation
# - Configurable Python environment activation

#------------------------------------------------------------------------------
# Python Environment Configuration (set during installation)
#------------------------------------------------------------------------------
TMUX_SPAWN_ENV_TYPE="${TMUX_SPAWN_ENV_TYPE:-none}"  # conda|venv|system|none
TMUX_SPAWN_ENV_NAME="${TMUX_SPAWN_ENV_NAME:-}"      # env name or path

#------------------------------------------------------------------------------
# Python Environment Activation
#------------------------------------------------------------------------------

activate_python_env() {
    local target="$1"
    case "$TMUX_SPAWN_ENV_TYPE" in
        conda)
            [[ -n "$TMUX_SPAWN_ENV_NAME" ]] && send_command "$target" "conda activate $TMUX_SPAWN_ENV_NAME" 2
            ;;
        venv)
            [[ -n "$TMUX_SPAWN_ENV_NAME" ]] && send_command "$target" "source $TMUX_SPAWN_ENV_NAME/bin/activate" 2
            ;;
        system|none|*)
            # No activation needed
            ;;
    esac
}

#------------------------------------------------------------------------------
# Platform Detection
#------------------------------------------------------------------------------

detect_platform() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

#------------------------------------------------------------------------------
# Observer Window
#------------------------------------------------------------------------------

open_observer() {
    local session="$1"
    local platform=$(detect_platform)

    case "$platform" in
        wsl)
            wt.exe wsl tmux attach -t "$session" &
            ;;
        macos)
            osascript -e "tell app \"Terminal\" to do script \"tmux attach -t $session\"" 2>/dev/null
            ;;
        linux)
            # For native Linux, user attaches manually or we try common terminals
            if command -v gnome-terminal &>/dev/null; then
                gnome-terminal -- tmux attach -t "$session" &
            elif command -v xterm &>/dev/null; then
                xterm -e "tmux attach -t $session" &
            else
                echo "Attach with: tmux attach -t $session"
            fi
            ;;
    esac
}

#------------------------------------------------------------------------------
# Session Management
#------------------------------------------------------------------------------

get_window_index() {
    local session="$1"
    tmux list-windows -t "$session" -F '#{window_index}' 2>/dev/null | head -1
}

spawn_session() {
    local session="$1"
    local panes="${2:-1}"
    local open_obs="${3:-true}"

    # Kill existing session if present
    tmux kill-session -t "$session" 2>/dev/null
    sleep 1

    # Create new session
    tmux new-session -d -s "$session"

    # Get window index (critical - may be 0 or 1 depending on tmux config)
    local win=$(get_window_index "$session")

    # Open observer window for user
    if [[ "$open_obs" == "true" ]]; then
        open_observer "$session"
        sleep 1
    fi

    # Create additional panes if requested
    for ((i=1; i<panes; i++)); do
        tmux split-window -t "$session:$win"
        tmux select-layout -t "$session:$win" tiled
    done

    # Final layout adjustment
    if [[ $panes -gt 1 ]]; then
        tmux select-layout -t "$session:$win" tiled
    fi

    # Return session:window for targeting
    echo "$session:$win"
}

kill_session() {
    local session="$1"
    tmux kill-session -t "$session" 2>/dev/null
}

list_sessions() {
    tmux list-sessions 2>/dev/null || echo "No tmux sessions running"
}

session_exists() {
    local session="$1"
    tmux has-session -t "$session" 2>/dev/null
}

#------------------------------------------------------------------------------
# Pane Operations
#------------------------------------------------------------------------------

add_pane() {
    local session="$1"
    local win=$(get_window_index "$session")

    tmux split-window -t "$session:$win"
    tmux select-layout -t "$session:$win" tiled

    # Return the new pane index
    tmux list-panes -t "$session:$win" -F '#{pane_index}' | tail -1
}

list_panes() {
    local session="$1"
    local win=$(get_window_index "$session")
    tmux list-panes -t "$session:$win" -F '#{pane_index}: #{pane_current_command}'
}

get_pane_indices() {
    local session="$1"
    local win=$(get_window_index "$session")
    tmux list-panes -t "$session:$win" -F '#{pane_index}'
}

#------------------------------------------------------------------------------
# Command Sending - CRITICAL PATTERNS
#------------------------------------------------------------------------------

send_command() {
    local target="$1"  # SESSION:WIN.PANE format
    local cmd="$2"
    local delay="${3:-1}"

    # CRITICAL: Split message from Enter to prevent lost keystrokes
    tmux send-keys -t "$target" "$cmd"
    sleep "$delay"
    tmux send-keys -t "$target" Enter
}

send_text() {
    local target="$1"
    local text="$2"

    # Send text without Enter (for partial input)
    tmux send-keys -t "$target" "$text"
}

send_enter() {
    local target="$1"

    # Use Enter (not C-m) - C-m creates newline in Claude CLI
    tmux send-keys -t "$target" Enter
}

send_interrupt() {
    local target="$1"
    tmux send-keys -t "$target" C-c
}

#------------------------------------------------------------------------------
# Output Capture
#------------------------------------------------------------------------------

capture_pane() {
    local target="$1"
    local lines="${2:-50}"

    tmux capture-pane -t "$target" -p -S "-$lines"
}

capture_pane_full() {
    local target="$1"
    tmux capture-pane -t "$target" -p -S -
}

#------------------------------------------------------------------------------
# Claude Code Launching
#------------------------------------------------------------------------------

launch_claude() {
    local target="$1"
    local flags="${2:---dangerously-skip-permissions}"
    local prompt="${3:-}"
    local wait_time="${4:-10}"

    # Activate Python environment (uses global config)
    activate_python_env "$target"
    sleep 2

    # Launch Claude with specified flags (NO -p flag - use interactive protocol)
    send_command "$target" "claude $flags" 1
    sleep "$wait_time"  # Wait for Claude to initialize

    # Send prompt interactively if provided
    if [[ -n "$prompt" ]]; then
        send_to_claude "$target" "$prompt" 2
    fi
}

launch_claude_with_env() {
    # Launch Claude with environment variables set
    # Usage: launch_claude_with_env TARGET FLAGS PROMPT WAIT_TIME "VAR1=val1" "VAR2=val2" ...
    local target="$1"
    local flags="${2:---dangerously-skip-permissions}"
    local prompt="${3:-}"
    local wait_time="${4:-10}"
    shift 4  # Remove first 4 args, rest are env vars

    # Activate Python environment (uses global config)
    activate_python_env "$target"
    sleep 2

    # Build env var prefix
    local env_prefix=""
    for env_var in "$@"; do
        if [[ -n "$env_var" ]]; then
            env_prefix="$env_var $env_prefix"
        fi
    done

    # Launch Claude with env vars (NO -p flag - use interactive protocol)
    send_command "$target" "${env_prefix}claude $flags" 1
    sleep "$wait_time"  # Wait for Claude to initialize

    # Send prompt interactively if provided
    if [[ -n "$prompt" ]]; then
        send_to_claude "$target" "$prompt" 2
    fi
}

send_to_claude() {
    local target="$1"
    local prompt="$2"
    local wait="${3:-5}"

    # Send prompt to Claude (split from Enter)
    send_command "$target" "$prompt" 1
    sleep "$wait"
}

#------------------------------------------------------------------------------
# Convenience Functions
#------------------------------------------------------------------------------

spawn_with_claude() {
    local session="$1"
    local flags="${2:---dangerously-skip-permissions}"

    # Spawn session
    local target=$(spawn_session "$session" 1 true)

    # Launch Claude in pane 1
    launch_claude "$target.1" "$flags"

    echo "$target"
}

spawn_multi_claude() {
    local session="$1"
    local count="${2:-2}"
    local flags="${3:---dangerously-skip-permissions}"

    # Spawn session with multiple panes
    local target=$(spawn_session "$session" "$count" true)
    local win=$(get_window_index "$session")

    # Launch Claude in each pane
    local panes=($(get_pane_indices "$session"))
    for pane in "${panes[@]}"; do
        launch_claude "$session:$win.$pane" "$flags" &
    done
    wait

    echo "$target"
}

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

tmux_spawn_help() {
    cat << 'EOF'
tmux-spawn.sh - Library for spawning and managing tmux sessions

FUNCTIONS:

  Session Management:
    spawn_session SESSION [PANES] [OPEN_OBSERVER]  - Create session with panes
    kill_session SESSION                            - Kill session
    list_sessions                                   - List all sessions
    session_exists SESSION                          - Check if session exists

  Pane Operations:
    add_pane SESSION                    - Add pane to session
    list_panes SESSION                  - List panes in session
    get_pane_indices SESSION            - Get pane indices

  Command Sending:
    send_command TARGET CMD [DELAY]     - Send command with Enter
    send_text TARGET TEXT               - Send text without Enter
    send_enter TARGET                   - Send Enter keystroke
    send_interrupt TARGET               - Send Ctrl-C

  Output Capture:
    capture_pane TARGET [LINES]         - Capture last N lines
    capture_pane_full TARGET            - Capture full history

  Claude Operations:
    launch_claude TARGET [FLAGS] [PROMPT] [WAIT]  - Launch Claude in pane
    launch_claude_with_env TARGET FLAGS PROMPT WAIT "VAR=val" ...  - Launch with env vars
    send_to_claude TARGET PROMPT        - Send prompt to Claude
    spawn_with_claude SESSION           - Spawn session with Claude
    spawn_multi_claude SESSION [COUNT]  - Spawn multiple Claude instances

  Utilities:
    detect_platform                     - Returns: wsl, macos, or linux
    open_observer SESSION               - Open observer window
    get_window_index SESSION            - Get window index

TARGET FORMAT: SESSION:WINDOW.PANE (e.g., myagent:1.1)

EXAMPLES:
    source ~/.claude/lib/tmux-spawn.sh

    # Basic session
    target=$(spawn_session "demo" 3)
    send_command "$target.1" "echo hello"
    capture_pane "$target.1" 10

    # Session with Claude
    target=$(spawn_with_claude "agent")
    send_to_claude "$target.1" "Hello Claude"
EOF
}

# Export functions if sourced
export -f activate_python_env detect_platform open_observer get_window_index spawn_session \
    kill_session list_sessions session_exists add_pane list_panes \
    get_pane_indices send_command send_text send_enter send_interrupt \
    capture_pane capture_pane_full launch_claude launch_claude_with_env \
    send_to_claude spawn_with_claude spawn_multi_claude tmux_spawn_help 2>/dev/null || true
