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
    local trailed=$arg_prefix

    if [[ $arg_prefix == */ ]]; then
        arg_prefix=${arg_prefix%/}
    fi

    [[ $arg_prefix == */* ]] || {
        [[ $trailed == */ ]] || return 1
        reply=("$before_arg")
        return 0
    }

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

# Lazy chunk cache.  On first access after a buffer change, we seed a small
# window (~20 chunks) around the cursor and extend on demand when traversal
# hits the edges.  This keeps per-keystroke cost low even on huge prompts.
typeset -ga _yt_chunk_starts
typeset -ga _yt_chunk_ends
typeset -g _yt_chunk_cached_buffer=
typeset -gi _yt_chunk_left_char=0
typeset -gi _yt_chunk_right_char=0

function _yt-chunk-scan-one-right {
    local pos=$1
    local len=$#BUFFER
    (( pos >= len )) && return 1

    local class=alnum
    [[ ${BUFFER[pos+1]} == [[:alnum:]] ]] || class=non-alnum

    local end=$pos
    while (( end < len )); do
        if [[ $class == alnum ]]; then
            [[ ${BUFFER[end+1]} == [[:alnum:]] ]] || break
        else
            [[ ${BUFFER[end+1]} == [[:alnum:]] ]] && break
        fi
        ((end++))
    done

    _yt_chunk_starts+=($pos)
    _yt_chunk_ends+=($end)
    _yt_chunk_right_char=$end
}

function _yt-chunk-scan-one-left {
    local pos=$1
    (( pos <= 0 )) && return 1

    local class=alnum
    [[ ${BUFFER[pos]} == [[:alnum:]] ]] || class=non-alnum

    local start=$((pos - 1))
    while (( start > 0 )); do
        if [[ $class == alnum ]]; then
            [[ ${BUFFER[start]} == [[:alnum:]] ]] || break
        else
            [[ ${BUFFER[start]} == [[:alnum:]] ]] && break
        fi
        ((start--))
    done

    _yt_chunk_starts=($start $_yt_chunk_starts[@])
    _yt_chunk_ends=($pos $_yt_chunk_ends[@])
    _yt_chunk_left_char=$start
}

function _yt-ensure-chunks-reach {
    local target=$1
    while (( target >= _yt_chunk_right_char && _yt_chunk_right_char < $#BUFFER )); do
        _yt-chunk-scan-one-right $_yt_chunk_right_char || break
    done
    while (( target <= _yt_chunk_left_char && _yt_chunk_left_char > 0 )); do
        _yt-chunk-scan-one-left $_yt_chunk_left_char || break
    done
}

function _yt-split-word-chunks {
    if [[ $BUFFER == $_yt_chunk_cached_buffer ]]; then
        # Cache hit, but cursor may have jumped far from the covered range.
        # If so, discard and re-seed — extending piecemeal would be too slow.
        if (( _yt_chunk_left_char <= CURSOR && _yt_chunk_right_char >= CURSOR )); then
            _yt-ensure-chunks-reach $CURSOR
            return
        fi
        local gap
        if (( CURSOR < _yt_chunk_left_char )); then
            gap=$(( _yt_chunk_left_char - CURSOR ))
        else
            gap=$(( CURSOR - _yt_chunk_right_char ))
        fi
        (( gap > 200 )) || { _yt-ensure-chunks-reach $CURSOR; return }
        # Gap too large — fall through to rebuild.
    fi

    _yt_chunk_starts=()
    _yt_chunk_ends=()
    _yt_chunk_cached_buffer=$BUFFER
    _yt_chunk_left_char=$CURSOR
    _yt_chunk_right_char=$CURSOR

    local len=$#BUFFER
    (( len == 0 )) && return

    local left_count=0 right_count=0 target=20 cursor=$CURSOR

    # Scan right for up to target/2 chunks.
    while (( _yt_chunk_right_char < len && right_count < target / 2 )); do
        _yt-chunk-scan-one-right $_yt_chunk_right_char || break
        ((right_count++))
    done

    # Scan left for up to target/2 chunks.
    while (( _yt_chunk_left_char > 0 && left_count < target / 2 )); do
        _yt-chunk-scan-one-left $_yt_chunk_left_char || break
        ((left_count++))
    done

    # Fill remaining quota on whichever side has more content.
    while (( _yt_chunk_right_char < len && (right_count + left_count) < target )); do
        _yt-chunk-scan-one-right $_yt_chunk_right_char || break
        ((right_count++))
    done
    while (( _yt_chunk_left_char > 0 && (right_count + left_count) < target )); do
        _yt-chunk-scan-one-left $_yt_chunk_left_char || break
        ((left_count++))
    done

    # If we built at least one chunk, tighten _yt_chunk_left_char to
    # the actual first chunk start.
    (( $#_yt_chunk_starts > 0 )) && _yt_chunk_left_char=$_yt_chunk_starts[1]
}

# Binary search: first chunk whose end > cursor.
function _yt-chunk-index-forward {
    local lo=1 hi=$#_yt_chunk_ends mid
    while (( lo < hi )); do
        mid=$(( (lo + hi) / 2 ))
        if (( _yt_chunk_ends[mid] <= $1 )); then
            lo=$(( mid + 1 ))
        else
            hi=$mid
        fi
    done
    (( lo <= $#_yt_chunk_ends && _yt_chunk_ends[lo] > $1 )) || return 1
    reply=($lo)
}

# Binary search: last chunk whose start < cursor.
function _yt-chunk-index-backward {
    local lo=1 hi=$#_yt_chunk_starts mid
    while (( lo < hi )); do
        mid=$(( (lo + hi + 1) / 2 ))
        if (( _yt_chunk_starts[mid] < $1 )); then
            lo=$mid
        else
            hi=$(( mid - 1 ))
        fi
    done
    (( lo >= 1 && _yt_chunk_starts[lo] < $1 )) || return 1
    reply=($lo)
}

function _yt-backward-word {
    (( CURSOR == 0 )) && return
    _yt-split-word-chunks

    _yt-ensure-chunks-reach $CURSOR
    _yt-chunk-index-backward $CURSOR || return
    local i=$reply[1]

    local raw_start=$_yt_chunk_starts[i]
    local raw_end=$_yt_chunk_ends[i]
    local vs=$raw_start

    # Non-alnum chunk: skip leading spaces to find the visual start.
    if [[ ${BUFFER[vs+1]} != [[:alnum:]] ]]; then
        while (( vs < raw_end )) && [[ ${BUFFER[vs+1]} == [[:space:]] ]]; do
            ((vs++))
        done
    fi

    if (( CURSOR > vs )); then
        CURSOR=$vs
    elif (( i > 1 )); then
        # Already at the visual start — move to the previous chunk.
        _yt-ensure-chunks-reach $((_yt_chunk_starts[i] - 1))
        local prev_start=$_yt_chunk_starts[i-1]
        local prev_end=$_yt_chunk_ends[i-1]
        local prev_vs=$prev_start
        if [[ ${BUFFER[prev_vs+1]} != [[:alnum:]] ]]; then
            while (( prev_vs < prev_end )) && [[ ${BUFFER[prev_vs+1]} == [[:space:]] ]]; do
                ((prev_vs++))
            done
        fi
        CURSOR=$prev_vs
    else
        # At the first chunk — fall back to its raw start.
        CURSOR=$raw_start
    fi
}
zle -N _yt-backward-word

function _yt-forward-word {
    (( CURSOR == $#BUFFER )) && return
    _yt-split-word-chunks

    _yt-ensure-chunks-reach $((CURSOR + 1))
    _yt-chunk-index-forward $CURSOR || return
    CURSOR=$_yt_chunk_ends[reply[1]]
}
zle -N _yt-forward-word

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

function _yt-backward-kill-word {
    (( CURSOR == 0 )) && return
    _yt-split-word-chunks

    _yt-ensure-chunks-reach $CURSOR
    _yt-chunk-index-backward $CURSOR || return
    local i=$reply[1]

    local raw_start=$_yt_chunk_starts[i]
    local raw_end=$_yt_chunk_ends[i]
    local vs=$raw_start

    # Non-alnum chunk: skip leading spaces to find the visual start.
    if [[ ${BUFFER[vs+1]} != [[:alnum:]] ]]; then
        while (( vs < raw_end )) && [[ ${BUFFER[vs+1]} == [[:space:]] ]]; do
            ((vs++))
        done
    fi

    if (( CURSOR > vs )); then
        _yt-kill-region-between "$vs" "$CURSOR"
    elif (( i > 1 )); then
        # Already at the visual start — kill from previous chunk's visual start.
        _yt-ensure-chunks-reach $((raw_start - 1))
        local prev_start=$_yt_chunk_starts[i-1]
        local prev_end=$_yt_chunk_ends[i-1]
        local prev_vs=$prev_start
        if [[ ${BUFFER[prev_vs+1]} != [[:alnum:]] ]]; then
            while (( prev_vs < prev_end )) && [[ ${BUFFER[prev_vs+1]} == [[:space:]] ]]; do
                ((prev_vs++))
            done
        fi
        _yt-kill-region-between "$prev_vs" "$CURSOR"
    else
        # At the first chunk — kill from its raw start.
        _yt-kill-region-between "$raw_start" "$CURSOR"
    fi

    _yt-clear-highlighting
}
zle -N _yt-backward-kill-word

function _yt-werase {
    (( CURSOR == 0 )) && return
    local pos=$CURSOR
    # Skip trailing whitespace
    while (( pos > 0 )) && [[ ${BUFFER[$pos]} == ' ' ]]; do
        (( pos-- ))
    done
    (( pos == 0 )) && { BUFFER=""; CURSOR=0; return }

    local char=$BUFFER[$pos]

    if [[ $char == [[:alnum:]] ]] || [[ $WORDCHARS == *"$char"* ]]; then
        # Word char at cursor: use standard backward-kill-word
        zle backward-kill-word
        return
    fi

    # Separator at cursor: check what precedes it
    local prev=${BUFFER[$pos-1]}
    if (( pos == 1 )) || [[ $prev == [[:alnum:]] ]] || [[ $WORDCHARS == *"$prev"* ]] || [[ $prev == ' ' ]]; then
        # At start, or preceded by word char or space: delete just this one separator
        BUFFER=$BUFFER[1,$pos-1]$BUFFER[$CURSOR+1,-1]
        CURSOR=$((pos - 1))
    else
        # Preceded by more separators: delete all consecutive separators
        local start=$pos
        while (( start > 0 )) && [[ ${BUFFER[$start]} != ' ' ]] \
            && [[ ${BUFFER[$start]} != [[:alnum:]] ]] \
            && [[ $WORDCHARS != *"${BUFFER[$start]}"* ]]; do
            (( start-- ))
        done
        if (( start > 0 )); then
            (( start++ ))
            BUFFER=$BUFFER[1,$start-1]$BUFFER[$CURSOR+1,-1]
            CURSOR=$((start - 1))
        else
            BUFFER=$BUFFER[$CURSOR+1,-1]
            CURSOR=0
        fi
    fi
}

function _yt-backward-kill-path-component {
    if (( CURSOR > 0 )) && [[ ${LBUFFER[CURSOR]} == [[:space:]] ]]; then
        if _yt-left-buffer-parent-path-after-trailing-space "$LBUFFER"; then
            LBUFFER=$reply[1]
            _yt-clear-highlighting
            return
        fi
    fi

    _yt-replace-left-buffer-with-parent-path || {
        _yt-werase
    }
    _yt-clear-highlighting
}
zle -N _yt-backward-kill-path-component

function _yt-list-directory {
  local target_path
  local index

  _yt-parse-shell-arguments

  for (( index = 1; index <= $#_yt_arg_starts; index++ )); do
    local start=$_yt_arg_starts[index]
    local end=$_yt_arg_ends[index]

    if (( CURSOR > start && CURSOR <= end )); then
      local -a words
      words=("${(@z)BUFFER}")
      target_path=$words[index]
      target_path=${(e)target_path}
      target_path=${~target_path}

      if [[ -n $target_path && ! -e $target_path ]]; then
        zle -I
        echo "ls: $target_path: No such file or directory" >&2
        return 0
      fi
      break
    fi
  done

  zle -I

  local -a ls_cmd
  if [[ -n $aliases[ls] ]]; then
    ls_cmd=("${(@z)aliases[ls]}")
  else
    ls_cmd=(ls)
  fi

  if [[ -n $target_path && -e $target_path ]]; then
    "${ls_cmd[@]}" -- "$target_path"
  else
    "${ls_cmd[@]}" -- .
  fi
}
zle -N _yt-list-directory

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

# --- History-prefix search (fish-like Ctrl-P/Ctrl-N) ---

typeset -g _yt_history_search_prefix=
typeset -g _yt_history_search_cursor=0
typeset -ga _yt_history_search_matches=()
typeset -gi _yt_history_search_pos=0
typeset -gi _yt_history_search_active=0

function _yt-history-search-stale-prefix {
    (( _yt_history_search_active )) || return 1
    [[ $BUFFER == $_yt_history_search_prefix ]] && return 1
    local match
    for match in $_yt_history_search_matches; do
        [[ $BUFFER == $match ]] && return 1
    done
    return 0
}

function _yt-history-search-reset {
    _yt_history_search_prefix=
    _yt_history_search_cursor=0
    _yt_history_search_matches=()
    _yt_history_search_pos=0
    _yt_history_search_active=0
}

function _yt-history-search-backward {
    if _yt-history-search-stale-prefix; then
        _yt-history-search-reset
    fi

    if (( ! _yt_history_search_active )); then
        _yt_history_search_active=1
        _yt_history_search_prefix=$BUFFER
        _yt_history_search_cursor=$CURSOR

        _yt_history_search_matches=()
        local key
        typeset -A _seen
        for (( key = HISTCMD; key >= 1; key-- )); do
            local cmd=$history[$key]
            [[ -n $cmd ]] || continue
            if [[ $cmd == $_yt_history_search_prefix* ]] && [[ -z $_seen[$cmd] ]]; then
                _seen[$cmd]=1
                _yt_history_search_matches+=("$cmd")
                (( $#_yt_history_search_matches >= 100 )) && break
            fi
        done
        _yt_history_search_pos=0
    fi

    if (( _yt_history_search_pos < $#_yt_history_search_matches )); then
        (( _yt_history_search_pos++ ))
        BUFFER=$_yt_history_search_matches[_yt_history_search_pos]
        CURSOR=$#BUFFER
        POSTDISPLAY=
        _zsh_autosuggest_fetch
    fi
}
zle -N _yt-history-search-backward

function _yt-history-search-forward {
    if _yt-history-search-stale-prefix; then
        _yt-history-search-reset
        return 1
    fi

    (( _yt_history_search_active )) || return 1

    if (( _yt_history_search_pos > 1 )); then
        (( _yt_history_search_pos-- ))
        BUFFER=$_yt_history_search_matches[_yt_history_search_pos]
        CURSOR=$#BUFFER
        POSTDISPLAY=
        _zsh_autosuggest_fetch
    else
        BUFFER=$_yt_history_search_prefix
        CURSOR=$_yt_history_search_cursor
        POSTDISPLAY=
        _zsh_autosuggest_fetch
        _yt-history-search-reset
    fi
}
zle -N _yt-history-search-forward
