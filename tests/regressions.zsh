#!/usr/bin/env zsh
# Run from the plugin directory: timeout 10 zsh -f tests/regressions.zsh
source ./settings.zsh
source ./shell-arguments.zsh
source ./widgets.zsh

function fail { print -ru2 -- "FAIL: $*"; exit 1 }
function eq { [[ $1 == "$2" ]] || fail "${3:-value}: ${(qqq)1} != ${(qqq)2}" }

# Stub only ZLE dispatch; record kill-region's selected text and emulate yank.
function zle {
    case $1 in
        kill-region)
            CUTBUFFER=${BUFFER[CURSOR+1,MARK]}
            BUFFER=${BUFFER[1,CURSOR]}${BUFFER[MARK+1,-1]}
            LBUFFER=${BUFFER[1,CURSOR]}
            ;;
        backward-kill-word)
            local end=$CURSOR start=$CURSOR ch
            while (( start > 0 )) && [[ ${BUFFER[start]} == [[:space:]] ]]; do ((start--)); done
            while (( start > 0 )); do
                ch=${BUFFER[start]}
                [[ $ch == [[:alnum:]] || $WORDCHARS == *"$ch"* ]] || break
                ((start--))
            done
            _yt-kill-region-between $start $end
            ;;
        yank)
            BUFFER=${BUFFER[1,CURSOR]}$CUTBUFFER${BUFFER[CURSOR+1,-1]}
            ((CURSOR += $#CUTBUFFER))
            ;;
        -I) ;;
        *) fail "unexpected ZLE call: $*" ;;
    esac
    return 0
}

function resolve {
    _yt-resolve-path "$1" || fail "resolve ${(qqq)1}: $reply[1]"
    eq "$reply[1]" "$2" 'resolved path'
}
resolve /tmp /tmp
resolve '"/tmp"' /tmp
resolve "'/tmp'" /tmp
resolve '/tmp/a\ b' '/tmp/a b'
resolve '/tm"p/a "b' '/tmp/a b'
resolve '~/' "$HOME/"
resolve "'~/'" '~/'
resolve '\~/' '~/'
resolve '"~/"' '~/'
resolve "'\$(touch marker)'" '$(touch marker)'
resolve '\$\(touch\ marker\)' '$(touch marker)'
resolve $'\'`literal`\'' '`literal`'
resolve '"a\qb"' 'a\qb'
resolve 'a*b?[c]' 'a*b?[c]'
resolve $'a\\\nb' ab
local_path='$(touch must-not-run) * spaces'
resolve '"$local_path"' "$local_path"
resolve '${local_path}' "$local_path"
name=/tmp raw=/tmp quote=/tmp
resolve '$name' /tmp
resolve '$raw' /tmp
resolve '$quote' /tmp
resolve '"\$(touch marker)"' '$(touch marker)'
resolve '"\`touch marker\`"' '`touch marker`'
resolve "'\$local_path'" '$local_path'
for raw in '$(touch marker)' '"$(touch marker)"' '`touch marker`' '"`touch marker`"' '<(touch marker)' '>(touch marker)' '$((1+1))' '${HOME:-/tmp}' '$HOME:t' '$' '"unfinished' 'unfinished\'; do
    _yt-resolve-path "$raw" && fail "accepted unsafe/incomplete path: $raw"
done

function tokens {
    BUFFER=$1
    shift
    _yt-parse-shell-arguments
    eq $#_yt_arg_starts $# 'token count'
    local i=1 start end
    for expected in "$@"; do
        start=$_yt_arg_starts[i] end=$_yt_arg_ends[i]
        (( start >= 0 && end > start && end <= $#BUFFER )) || fail 'invalid raw span'
        eq "${BUFFER[start+1,end]}" "$expected" "token $i"
        ((i++))
    done
}
tokens $'echo a\ncat b' echo a $'\n' cat b
eq "$_yt_arg_starts" '0 5 6 7 11' 'newline starts'
eq "$_yt_arg_ends" '4 6 7 10 12' 'newline ends'
tokens $'a\n\nb' a $'\n' $'\n' b
tokens $'echo ab\\\ncd x' echo $'ab\\\ncd' x
eq "$_yt_arg_starts" '0 5 12' 'continuation starts'
eq "$_yt_arg_ends" '4 11 13' 'continuation ends'
tokens 'echo "a b" c\ d' echo '"a b"' 'c\ d'
tokens 'a&&b|c>>f;d' a '&&' b '|' c '>>' f ';' d
tokens 'echo $(one "$(two a)" b) <(cat x)' echo '$(one "$(two a)" b)' '<(cat x)'
tokens 'echo "$(one "two")" next' echo '"$(one "two")"' next
tokens 'echo "`one two`" x' echo '"`one two`"' x
tokens 'echo ${x:-${y}} x' echo '${x:-${y}}' x
tokens 'echo $((1 + (2))) x' echo '$((1 + (2)))' x
tokens 'эхо привет мир' эхо привет мир
tokens 'echo "unfinished text' echo '"unfinished text'
tokens 'echo $(unfinished text' echo '$(unfinished text'
tokens "echo \$'a\\' b' x" echo "\$'a\\' b'" x
tokens 'echo $[1 + 2] x' echo '$[1 + 2]' x
tokens 'echo foo\' echo 'foo\'
tokens $'echo \\\n /tmp' echo /tmp
BUFFER=$'echo a\ncat b'; CURSOR=12
_yt-sudo
eq "$BUFFER" $'echo a\nsudo cat b' 'sudo on later line'
_yt-sudo
eq "$BUFFER" $'echo a\ncat b' 'undo sudo on later line'
BUFFER=$'echo ab\\\ncd x'; CURSOR=5
yt-forward-shell-argument
eq $CURSOR 12 'forward continued argument'
_yt-backward-shell-argument
eq $CURSOR 5 'backward continued argument'
CURSOR=11
_yt-backward-kill-shell-argument
eq "$CUTBUFFER" $'ab\\\ncd' 'kill continued argument'

function navigation {
    BUFFER=$1; CURSOR=0; _yt_chunk_cached_buffer='invalid'
    local expected
    for expected in ${(s:,:)2}; do
        _yt-forward-word
        eq $CURSOR $expected 'forward chunk'
    done
    for expected in ${(s:,:)3}; do
        _yt-backward-word
        eq $CURSOR $expected 'backward chunk'
    done
}
navigation 'foo --bar' 3,6,9 6,4,0
navigation 'cat /foo' 3,5,8 5,4,0
navigation 'foo-bar' 3,4,7 4,3,0
for word in foobar '------'; do
    BUFFER=$word; CURSOR=3; _yt_chunk_cached_buffer='invalid'
    _yt-forward-word; eq $CURSOR 6 'inside run forward'
    _yt-backward-word; eq $CURSOR 0 'inside run backward'
    CURSOR=3; _yt_chunk_cached_buffer='invalid'
    _yt-backward-word; eq $CURSOR 0 'inside run backward first'
    _yt-forward-word; eq $CURSOR 6 'inside run forward second'
done
# Check actual navigation positions while crossing both lazy cache edges.
BUFFER=${(pl:1600::a --:)''}; CURSOR=0
for (( step=1; step<=40; step++ )); do
    _yt-forward-word
    eq $CURSOR $((2 * step - step % 2)) 'forward cache extension'
done
CURSOR=800; _yt_chunk_cached_buffer='invalid'
for (( step=1; step<=40; step++ )); do
    _yt-backward-word
    eq $CURSOR $((800 - 2 * step)) 'backward cache extension'
done
# Exercise extension and distant cursor reseeding, checking chunk invariants.
BUFFER=${(pl:1500::a --:)''}
for seed in 0 750 1490 20; do
    CURSOR=$seed
    repeat 30; do _yt-forward-word; done
    repeat 30; do _yt-backward-word; done
    for (( i=1; i <= $#_yt_chunk_starts; i++ )); do
        (( _yt_chunk_starts[i] < _yt_chunk_ends[i] )) || fail 'empty chunk'
        if (( i > 1 )); then
            eq $_yt_chunk_starts[i] $_yt_chunk_ends[i-1] 'contiguous chunks'
            left=${BUFFER[_yt_chunk_starts[i]]}
            right=${BUFFER[_yt_chunk_starts[i]+1]}
            if [[ $left == [[:alnum:]] ]]; then
                [[ $right != [[:alnum:]] ]] || fail 'adjacent alnum chunks'
            else
                [[ $right == [[:alnum:]] ]] || fail 'adjacent non-alnum chunks'
            fi
        fi
    done
done

function deletion {
    local prefix=$1 expected=$2 killed=$3 widget=${4:-_yt-backward-kill-path-component}
    BUFFER="$prefix keep-this"; CURSOR=$#prefix; LBUFFER=$prefix
    local original=$BUFFER original_cursor=$CURSOR
    $widget
    eq "$BUFFER" "$expected keep-this" 'deletion suffix'
    eq "$CUTBUFFER" "$killed" 'kill ring text'
    eq $CURSOR $#expected 'deletion cursor'
    zle yank
    eq "$BUFFER" "$original" 'yank restores buffer'
    eq $CURSOR $original_cursor 'yank restores cursor'
}
deletion '   ' '' '   '
deletion './' '' './'
deletion '../' '' '../'
deletion '/' '' '/'
deletion 'foo/bar' 'foo/' bar
deletion 'foo/bar/  ' 'foo/' 'bar/  '
deletion 'foo-bar' 'foo-' bar
deletion foo '' foo
deletion '\' '' '\'
deletion "''" '' "''"
deletion '""' '' '""'
deletion '"\' '' '"\'
deletion 'foo---' 'foo' '---'
deletion 'foo-' 'foo' '-'
deletion 'foobar' '' foobar _yt-backward-kill-word
function forward_deletion {
    local original=$1 original_cursor=$2 expected=$3 killed=$4
    BUFFER=$original; CURSOR=$original_cursor
    _yt-forward-kill-word
    eq "$BUFFER" "$expected" 'forward deletion buffer'
    eq "$CUTBUFFER" "$killed" 'forward deletion kill ring text'
    eq $CURSOR $original_cursor 'forward deletion cursor'
    zle yank
    eq "$BUFFER" "$original" 'forward deletion yank restores buffer'
    eq $CURSOR $((original_cursor + $#killed)) 'forward deletion yank cursor'
}
forward_deletion 'brew search' 4 brew ' search'
forward_deletion 'brew   search suffix' 4 'brew suffix' '   search'
forward_deletion $'brew \tsearch' 4 brew $' \tsearch'
forward_deletion 'brew --search' 4 brewsearch ' --'
forward_deletion 'brew   ' 4 brew '   '
forward_deletion '   ' 0 '' '   '
forward_deletion 'foobar suffix' 3 'foo suffix' bar
forward_deletion 'foo-bar' 3 foobar '-'

print -- 'Widget regressions passed'
