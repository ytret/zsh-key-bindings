#!/usr/bin/env zsh
# Run from the plugin directory: timeout 10 zsh -f tests/list-directory.zsh
source ./shell-arguments.zsh
source ./widgets.zsh
function fail { print -ru2 -- "FAIL: $*"; exit 1 }
function zle { [[ $1 == -I ]] || fail "unexpected ZLE call: $*" }
function ls { listed=("$@") }
unalias ls 2>/dev/null
local temporary_dir=$(mktemp -d)
trap 'command rm -rf -- "$temporary_dir"' EXIT
mkdir -- "$temporary_dir/with space" "$temporary_dir/-dash"
local -a listed
function check_list {
    BUFFER="ls $1"; CURSOR=$#BUFFER; listed=()
    _yt-list-directory
    [[ $#listed == 2 && $listed[1] == -- && $listed[2] == "$2" ]] || fail "listing: $1"
}
check_list /tmp /tmp
check_list '"/tmp"' /tmp
check_list "'/tmp'" /tmp
check_list "\"$temporary_dir/with space\"" "$temporary_dir/with space"
check_list "$temporary_dir/with\\ space" "$temporary_dir/with space"
check_list "$temporary_dir/wi\"th sp\"ace" "$temporary_dir/with space"
# Literal substitution syntax, glob characters, and option-like names.
mkdir -- "$temporary_dir/\$(literal)" "$temporary_dir/\`literal\`" "$temporary_dir/*"
check_list "'$temporary_dir/\$(literal)'" "$temporary_dir/\$(literal)"
check_list "$temporary_dir/\\\$\\(literal\\)" "$temporary_dir/\$(literal)"
check_list "'$temporary_dir/\`literal\`'" "$temporary_dir/\`literal\`"
check_list "$temporary_dir/*" "$temporary_dir/*"
(
    cd -- "$temporary_dir" || exit 1
    check_list -dash -dash
) || fail 'path beginning with dash'
BUFFER=''; CURSOR=0; listed=(); _yt-list-directory
[[ $listed[2] == . ]] || fail 'no selected argument'
for raw in "\$(touch $temporary_dir/marker)" "\"\$(touch $temporary_dir/marker)\"" "\`touch $temporary_dir/marker\`" "\"\`touch $temporary_dir/marker\`\"" "<(touch $temporary_dir/marker)" "''" '""' "$temporary_dir/missing"; do
    BUFFER="ls $raw"; CURSOR=$#BUFFER; listed=()
    _yt-list-directory 2>"$temporary_dir/stderr"
    [[ ! -e $temporary_dir/marker ]] || fail 'executed editing buffer'
    [[ $#listed == 0 && -s $temporary_dir/stderr ]] || fail "invalid path listed current directory: $raw"
done
print -- 'Directory listing regressions passed'
