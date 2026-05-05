# Define custom ZLE widgets and the small helpers they share.

function _yt-edit-command-line-in-nvim {
    emulate -L zsh
    local EDITOR=nvim
    local VISUAL=nvim
    zle edit-command-line
}
zle -N _yt-edit-command-line-in-nvim

function _yt-kill-region-between {
    local start=$1
    local end=$2

    CURSOR=$start
    MARK=$end
    REGION_ACTIVE=1
    zle kill-region
}

function _yt-skip-forward-space {
    while (( CURSOR < $#BUFFER )) && [[ ${BUFFER[CURSOR + 1]} == [[:space:]] ]]; do
        ((CURSOR++))
    done
}

function _yt-current-word-bounds {
    (( CURSOR > 0 )) || return 1

    zle backward-word
    local word_start=$CURSOR
    zle forward-word
    local word_end=$CURSOR

    reply=($word_start $word_end)
}

function _yt-trim-trailing-space {
    local text=$1
    local cursor=$#text

    while (( cursor > 0 )) && [[ ${text[cursor]} == [[:space:]] ]]; do
        ((cursor--))
    done

    (( cursor < $#text )) || return 1

    reply=("${text[1,cursor]}" "$cursor")
}

function _yt-path-parent-prefix {
    local before_arg=$1
    local arg_prefix=$2

    if [[ $arg_prefix == */ ]]; then
        arg_prefix=${arg_prefix%/}
    fi

    [[ $arg_prefix == */* ]] || return 1

    reply=("${before_arg}${arg_prefix%/*}/")
}

function _yt-with-temporary-buffer {
    local temporary_buffer=$1
    local temporary_cursor=$2
    local callback=$3
    local saved_buffer=$BUFFER
    local saved_cursor=$CURSOR
    local callback_status

    BUFFER=$temporary_buffer
    CURSOR=$temporary_cursor
    $callback
    callback_status=$?

    BUFFER=$saved_buffer
    CURSOR=$saved_cursor
    return $callback_status
}

function _yt-left-buffer-parent-path-after-trailing-space {
    local left_buffer=$1

    _yt-trim-trailing-space "$left_buffer" || return 1
    local trimmed_left=$reply[1]
    local trimmed_cursor=$reply[2]

    _yt-with-temporary-buffer "$trimmed_left" "$trimmed_cursor" _yt-shell-argument-bounds-left-of-cursor || return 1

    local start=$reply[1]
    local before_arg=${trimmed_left[1,start]}
    local arg_prefix=${trimmed_left[start + 1,-1]}

    _yt-path-parent-prefix "$before_arg" "$arg_prefix" || return 1
}

function _yt-replace-left-buffer-with-parent-path {
    _yt-shell-argument-bounds-left-of-cursor || return 1

    local start=$reply[1]
    local before_arg=${LBUFFER[1,start]}
    local arg_prefix=${LBUFFER[start + 1,-1]}

    _yt-path-parent-prefix "$before_arg" "$arg_prefix" || return 1
    LBUFFER=$reply[1]
}

function _yt-forward-shell-argument {
    local original_cursor=$CURSOR

    _yt-shell-argument-bounds-right-of-cursor || return

    local start=$reply[1]
    local end=$reply[2]

    if (( original_cursor < end )); then
        CURSOR=$end
    else
        CURSOR=$start
    fi

    _yt-skip-forward-space
}
zle -N _yt-forward-shell-argument

function _yt-backward-shell-argument {
    local original_cursor=$CURSOR

    _yt-shell-argument-bounds-left-of-cursor || return

    local start=$reply[1]
    (( original_cursor > start )) || return

    CURSOR=$start
}
zle -N _yt-backward-shell-argument

function _yt-backward-kill-shell-argument {
    local original_cursor=$CURSOR

    _yt-shell-argument-bounds-left-of-cursor || return
    _yt-kill-region-between "$reply[1]" "$original_cursor"
}
zle -N _yt-backward-kill-shell-argument

function _yt-kill-shell-argument {
    local original_cursor=$CURSOR

    _yt-shell-argument-bounds-right-of-cursor || return
    _yt-kill-region-between "$original_cursor" "$reply[2]"
}
zle -N _yt-kill-shell-argument

function _yt-kill-current-word {
    _yt-current-word-bounds || return
    _yt-kill-region-between "$reply[1]" "$reply[2]"
}
zle -N _yt-kill-current-word

function _yt-backward-kill-path-component {
    if (( CURSOR > 0 )) && [[ ${LBUFFER[CURSOR]} == [[:space:]] ]]; then
        if _yt-left-buffer-parent-path-after-trailing-space "$LBUFFER"; then
            LBUFFER=$reply[1]
            return
        fi
    fi

    _yt-replace-left-buffer-with-parent-path && return
    zle backward-kill-word
}
zle -N _yt-backward-kill-path-component
