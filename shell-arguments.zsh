# Parse shell arguments in $BUFFER and expose helpers for nearby argument bounds.

typeset -ga _yt_arg_starts
typeset -ga _yt_arg_ends

function _yt-shell-arguments-reset {
    _yt_arg_starts=()
    _yt_arg_ends=()
}

function _yt-shell-arguments-add {
    local start_char=$1
    local end_char=$2

    _yt_arg_starts+=$((start_char - 1))
    _yt_arg_ends+=$end_char
}

function _yt-shell-argument-handle-unquoted-char {
    local char=$1

    if [[ $char == \\ ]]; then
        reply=(escape)
        return
    fi

    if [[ $char == "'" ]]; then
        reply=(single-quote)
        return
    fi

    if [[ $char == '"' ]]; then
        reply=(double-quote)
        return
    fi

    if [[ $char == [[:space:]] ]]; then
        reply=(space)
        return
    fi

    reply=(plain)
}

function _yt-parse-shell-arguments {
    _yt-shell-arguments-reset

    local i=1
    local length=$#BUFFER
    local in_arg=0
    local escaped=0
    local quote=
    local start_char=0
    local char

    while (( i <= length )); do
        char=${BUFFER[i]}

        if (( ! in_arg )) && [[ $char == [[:space:]] ]]; then
            ((i++))
            continue
        fi

        if (( ! in_arg )); then
            in_arg=1
            start_char=$i
        fi

        if (( escaped )); then
            escaped=0
            ((i++))
            continue
        fi

        case $quote in
            '')
                _yt-shell-argument-handle-unquoted-char "$char"
                case $reply[1] in
                    escape)
                        escaped=1
                        ;;
                    single-quote)
                        quote="'"
                        ;;
                    double-quote)
                        quote='"'
                        ;;
                    space)
                        _yt-shell-arguments-add "$start_char" $((i - 1))
                        in_arg=0
                        start_char=0
                        ;;
                esac
                ;;
            "'")
                [[ $char == "'" ]] && quote=
                ;;
            '"')
                if [[ $char == \\ ]]; then
                    escaped=1
                elif [[ $char == '"' ]]; then
                    quote=
                fi
                ;;
        esac

        ((i++))
    done

    (( in_arg )) && _yt-shell-arguments-add "$start_char" "$length"
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
