# Source explicitly from an interactive local zsh. No key bindings change on source.
# The helper and Python executable can be configured before sourcing this file.
if [[ ! -o interactive ]]; then
    return 0
fi

typeset -g _FREEPUNTO_BRIDGE="${${(%):-%N}:A:h}/bridge.py"
typeset -g FREEPUNTO_HELPER="${FREEPUNTO_HELPER:-${_FREEPUNTO_BRIDGE:h:h:h}/.build/release/punto-transform}"
typeset -g FREEPUNTO_PYTHON="${FREEPUNTO_PYTHON:-python3}"
typeset -g _FREEPUNTO_CYCLE_SESSION=''

freepunto-layout() {
    emulate -L zsh
    local old_left="$LBUFFER" old_right="$RBUFFER"
    local next_left next_session marker
    [[ "$LASTWIDGET" == freepunto-layout ]] || _FREEPUNTO_CYCLE_SESSION=''
    if [[ ! -x "$FREEPUNTO_HELPER" ]]; then
        zle -M 'FreePunto: build/configure punto-transform first'
        return 1
    fi
    if ! {
        IFS= read -r -d '' next_left &&
        IFS= read -r -d '' next_session &&
        IFS= read -r -d '' marker
    } < <(
        printf '%s\0' "$old_left" "$old_right" "$_FREEPUNTO_CYCLE_SESSION" |
            "$FREEPUNTO_PYTHON" "$_FREEPUNTO_BRIDGE" "$FREEPUNTO_HELPER"
    ); then
        _FREEPUNTO_CYCLE_SESSION=''
        zle -M 'FreePunto: transformation unavailable; buffer unchanged'
        return 1
    fi
    if [[ "$marker" != ok || "$LBUFFER" != "$old_left" || "$RBUFFER" != "$old_right" ]]; then
        _FREEPUNTO_CYCLE_SESSION=''
        return 1
    fi
    # Assigning LBUFFER changes only the text before the caret; RBUFFER is untouched.
    LBUFFER="$next_left"
    if [[ "$LBUFFER" == "$next_left" && "$RBUFFER" == "$old_right" ]]; then
        _FREEPUNTO_CYCLE_SESSION="$next_session"
    else
        _FREEPUNTO_CYCLE_SESSION=''
    fi
}

zle -N freepunto-layout
