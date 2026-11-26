# Parse shell arguments in $BUFFER and expose helpers for nearby argument bounds.

typeset -ga _yt_arg_starts
typeset -ga _yt_arg_ends
typeset -g _yt_arg_cached_buffer=

function _yt-parse-shell-arguments {
    [[ $BUFFER == $_yt_arg_cached_buffer ]] && return

    _yt_arg_starts=()
    _yt_arg_ends=()

    # Let zsh handle quoting, glob syntax, and nested shell grammar. Tokens keep
    # their raw spelling except for same-width operator normalization (e.g. >!
    # becomes >|, a newline becomes ;) and removed backslash-newline pairs.
    local -a words
    words=("${(@z)BUFFER}")
    local pos=1 length=$#BUFFER start word index

    for word in "${words[@]}"; do
        # Quoted expansion of an empty token list can yield one empty element.
        [[ -n $word ]] || continue
        # Whitespace and continuations before a token have no argument span.
        while (( pos <= length )); do
            if [[ ${BUFFER[pos,pos+1]} == $'\\\n' ]]; then
                ((pos += 2))
            elif [[ ${BUFFER[pos]} == [[:space:]] && ${BUFFER[pos]} != $'\n' ]]; then
                ((pos++))
            else
                break
            fi
        done
        start=$pos
        index=1
        while (( index <= $#word && pos <= length )); do
            # A continuation inside single/ANSI quotes survives tokenization;
            # consume it literally. Else skip the pair only in the raw buffer.
            if [[ ${BUFFER[pos,pos+1]} == $'\\\n' &&
                  ${word[index,index+1]} != $'\\\n' ]]; then
                ((pos += 2))
            else
                ((pos++, index++))
            fi
        done
        _yt_arg_starts+=($((start - 1)))
        _yt_arg_ends+=($((pos - 1)))
    done

    _yt_arg_cached_buffer=$BUFFER
}

function _yt-shell-argument-bounds-left-of-cursor {
    local position=$CURSOR
    local index

    _yt-parse-shell-arguments

    for (( index = $#_yt_arg_starts; index >= 1; index-- )); do
        local start=$_yt_arg_starts[index]
        local end=$_yt_arg_ends[index]

        if (( position > start && position <= end )) || (( end < position )); then
            reply=($start $end)
            return 0
        fi
    done

    return 1
}

function _yt-shell-argument-bounds-right-of-cursor {
    local position=$CURSOR
    local index

    _yt-parse-shell-arguments

    for (( index = 1; index <= $#_yt_arg_starts; index++ )); do
        local start=$_yt_arg_starts[index]
        local end=$_yt_arg_ends[index]

        if (( position >= start && position < end )) || (( start >= position )); then
            reply=($start $end)
            return 0
        fi
    done

    return 1
}
