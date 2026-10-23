# Parse shell arguments in $BUFFER and expose helpers for nearby argument bounds.

typeset -ga _yt_arg_starts
typeset -ga _yt_arg_ends
typeset -g _yt_arg_cached_buffer=

function _yt-parse-shell-arguments {
    [[ $BUFFER == $_yt_arg_cached_buffer ]] && return

    _yt_arg_starts=()
    _yt_arg_ends=()

    local pos=1 length=$#BUFFER start ch next quote='' op
    local -a closes quotes

    while (( pos <= length )); do
        ch=${BUFFER[pos]}
        # Newlines have their own raw span, like other command separators.
        if [[ $ch == [[:space:]] && $ch != $'\n' ]]; then
            ((pos++))
            continue
        fi
        # A continuation between words is not an argument.
        if [[ ${BUFFER[pos,pos+1]} == $'\\\n' ]]; then
            ((pos += 2))
            continue
        fi
        start=$pos
        if [[ $ch == (';'|'&'|'|'|'('|')'|'<'|'>'|$'\n') ]] &&
           [[ ${BUFFER[pos,pos+1]} != ('<('|'>(') ]]; then
            # Longest shell operator, without consuming adjacent words.
            for op in '&>>' '>>&' '>>|' '>>!' '<<<' '<<-' ';;&' '&&' '||' '|&' ';;' ';&' '<<' '>>' '<&' '>&' '<>' '>|' '&>' ; do
                if [[ ${BUFFER[pos,pos+$#op-1]} == "$op" ]]; then
                    ((pos += $#op))
                    break
                fi
            done
            (( pos == start )) && ((pos++))
        else
            quote=''
            closes=() quotes=()
            while (( pos <= length )); do
                ch=${BUFFER[pos]}
                next=${BUFFER[pos+1]}
                if [[ $quote == ansi ]]; then
                    if [[ $ch == '\' ]]; then
                        ((pos += 2))
                        (( pos > length + 1 )) && pos=$((length + 1))
                    else
                        [[ $ch == "'" ]] && quote=''
                        ((pos++))
                    fi
                    continue
                fi
                if [[ $quote == "'" ]]; then
                    [[ $ch == "'" ]] && quote=''
                    ((pos++))
                    continue
                fi
                if [[ $ch == '\' ]]; then
                    ((pos += 2))
                    (( pos > length + 1 )) && pos=$((length + 1))
                    continue
                fi
                if [[ $quote == '`' ]]; then
                    if [[ $ch == '`' ]]; then
                        quote=''
                        if [[ $closes[-1] == '`' ]]; then
                            quote=$quotes[-1]
                            closes[-1]=() quotes[-1]=()
                        fi
                    fi
                    ((pos++))
                    continue
                fi
                if [[ -z $quote && $ch == '$' && $next == "'" ]]; then
                    quote=ansi
                    ((pos += 2))
                    continue
                fi
                # Save the enclosing quote state while scanning nested source.
                if [[ $ch == '$' && $next == ('('|'{'|'[') ]] ||
                   [[ -z $quote && $ch == ('<'|'>') && $next == '(' ]]; then
                    quotes+=("$quote")
                    case $next in
                        '(') closes+=(')') ;;
                        '{') closes+=('}') ;;
                        '[') closes+=(']') ;;
                    esac
                    quote=''
                    ((pos += 2))
                    continue
                fi
                if [[ $quote == '"' ]]; then
                    [[ $ch == '"' ]] && quote=''
                    [[ $ch == '`' ]] && { quotes+=("$quote"); closes+=('`'); quote='`'; }
                    ((pos++))
                    continue
                fi
                if [[ -n $closes && $ch == $closes[-1] ]]; then
                    quote=$quotes[-1]
                    closes[-1]=() quotes[-1]=()
                elif [[ $ch == ("'"|'"'|'`') ]]; then
                    quote=$ch
                elif (( $#closes )) && [[ $ch == '(' ]]; then
                    closes+=(')') quotes+=('')
                elif (( ! $#closes )) && [[ $ch == ([[:space:]]|';'|'&'|'|'|'('|')'|'<'|'>') ]]; then
                    break
                fi
                ((pos++))
            done
        fi
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
