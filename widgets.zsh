# Define custom ZLE widgets and the small helpers they share.

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

function _yt-clear-highlighting {
    typeset -g _ZSH_HIGHLIGHT_PRIOR_BUFFER=
    typeset -ga _zsh_highlight__highlighter_main_cache=()
    typeset -ga _zsh_highlight__highlighter_brackets_cache=()
    typeset -ga _zsh_highlight__highlighter_cursor_cache=()
    region_highlight=( "${(@)region_highlight:#*memo=zsh-syntax-highlighting*}" )
    _zsh_autosuggest_highlight_reset
    POSTDISPLAY=
    _zsh_autosuggest_fetch
    _zsh_autosuggest_highlight_apply
}

function yt-forward-shell-argument {
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
zle -N yt-forward-shell-argument

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
            _yt-clear-highlighting
            return
        fi
    fi

    _yt-replace-left-buffer-with-parent-path || {
        zle backward-kill-word
    }
    _yt-clear-highlighting
}
zle -N _yt-backward-kill-path-component

function _yt-sudo {
    if [[ -z $BUFFER ]]; then
        local last_cmd
        last_cmd=$(fc -ln -1 2>/dev/null | tail -1)
        if [[ -n $last_cmd ]]; then
            BUFFER=$last_cmd
            CURSOR=$#BUFFER
        fi
    fi

    _yt-parse-shell-arguments

    local i sep_end=-1 word

    for (( i = $#_yt_arg_starts; i >= 1; i-- )); do
        word="${BUFFER[_yt_arg_starts[i]+1,_yt_arg_ends[i]]}"
        if (( _yt_arg_ends[i] < CURSOR + 1 )) && [[ $word == ('|'|'||'|'|&'|';'|'&&') ]]; then
            sep_end=$_yt_arg_ends[i]
            break
        fi
    done

    if (( sep_end >= 0 )); then
        local ins=$((sep_end + 1))
        while (( ins <= $#BUFFER )) && [[ ${BUFFER[ins]} == [[:space:]] ]]; do
            ((ins++))
        done

        local rest=$BUFFER[ins,-1]
        local old_cursor=$CURSOR

        if [[ $rest == sudo[[:space:]]* ]]; then
            BUFFER=$BUFFER[1,ins-1]$BUFFER[ins+5,-1]
            if (( old_cursor > ins + 3 )); then
                CURSOR=$((old_cursor - 5))
            elif (( old_cursor >= ins )); then
                CURSOR=$((ins - 1))
            fi
        elif [[ $rest == sudo ]]; then
            BUFFER=$BUFFER[1,ins-1]
            if (( old_cursor > ins + 2 )); then
                CURSOR=$((old_cursor - 4))
            elif (( old_cursor >= ins )); then
                CURSOR=$((ins - 1))
            fi
        else
            BUFFER=$BUFFER[1,ins-1]"sudo "$BUFFER[ins,-1]
            (( old_cursor >= ins )) && CURSOR=$((old_cursor + 5))
        fi
    else
        local old_cursor=$CURSOR

        if [[ $BUFFER == sudo[[:space:]]* ]]; then
            BUFFER=$BUFFER[6,-1]
            CURSOR=$((old_cursor - 5))
            (( CURSOR < 0 )) && CURSOR=0
        elif [[ $BUFFER == sudo ]]; then
            BUFFER=""
            CURSOR=0
        else
            BUFFER="sudo $BUFFER"
            CURSOR=$((old_cursor + 5))
        fi
    fi
}
zle -N _yt-sudo
