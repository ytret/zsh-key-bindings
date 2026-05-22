# Parse shell arguments in $BUFFER and expose helpers for nearby argument bounds.

typeset -ga _yt_arg_starts
typeset -ga _yt_arg_ends

function _yt-parse-shell-arguments {
    _yt_arg_starts=()
    _yt_arg_ends=()

    local -a words
    local word
    local pos=1
    local length=$#BUFFER

    words=("${(@z)BUFFER}")

    for word in "${words[@]}"; do
        while (( pos <= length )) && [[ ${BUFFER[$pos]} == [[:space:]] ]]; do
            ((pos++))
        done
        (( pos > length )) && break

        _yt_arg_starts+=$((pos - 1))
        ((pos += $#word))
        _yt_arg_ends+=$((pos - 1))
    done
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
