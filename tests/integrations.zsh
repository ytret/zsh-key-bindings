#!/usr/bin/env zsh
# Optional real-plugin check. Arguments: before|after, autosuggestions path or
# empty string, syntax-highlighting path or empty string. Run with timeout 10.
function fail { print -ru2 -- "FAIL: $*"; exit 1 }
local order=$1 autosuggestions=$2 highlighting=$3
function load_dependencies {
    [[ -z $autosuggestions ]] || source "$autosuggestions" || fail 'autosuggestions load'
    [[ -z $highlighting ]] || source "$highlighting" || fail 'highlighting load'
    return 0
}
[[ $order == before ]] && load_dependencies
source ./yt-key-bindings.plugin.zsh || fail 'plugin load'
[[ $order == after ]] && load_dependencies
# Simulate the first prompt, which activates integrations loaded after the plugin.
_yt-enable-optional-integrations
local widget=$widgets[_yt-forward-word]
local hooks=${(j: :)${zle_line_pre_redraw_functions:-}}
_yt-enable-optional-integrations
[[ $widgets[_yt-forward-word] == $widget ]] || fail 'rebound on second prompt'
[[ ${(j: :)${zle_line_pre_redraw_functions:-}} == $hooks ]] || fail 'duplicate redraw hook'
(( ${ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS[(Ie)_yt-forward-word]} )) || fail 'missing partial accept setting'
if [[ -n $highlighting ]]; then
    (( _yt_highlight_hook_added )) || fail 'highlight hook missing'
else
    (( ! _yt_highlight_hook_added )) || fail 'highlight hook without dependency'
fi
if [[ -n $autosuggestions ]]; then
    [[ $widget == user:_zsh_autosuggest_bound_* ]] || fail 'private widget not bound'
    # Only the dispatcher needs stubbing outside an active ZLE session. Exercise
    # the real autosuggestions partial-accept implementation and our widget.
    function _zsh_autosuggest_invoke_original_widget { _yt-forward-word }
    BUFFER=foo; CURSOR=3; POSTDISPLAY=' --bar'; KEYMAP=emacs
    _zsh_autosuggest_partial_accept
    [[ $BUFFER == 'foo --' && $POSTDISPLAY == bar && $CURSOR == 6 ]] || fail 'partial acceptance'
    BUFFER=foo; CURSOR=3; POSTDISPLAY=' * bar'
    _zsh_autosuggest_partial_accept
    [[ $BUFFER == 'foo *' && $POSTDISPLAY == ' bar' && $CURSOR == 5 ]] || fail 'partial acceptance visual end'
    _zsh_autosuggest_partial_accept
    [[ $BUFFER == 'foo * bar' && -z $POSTDISPLAY && $CURSOR == 9 ]] || fail 'partial acceptance after visual end'
fi
# Refresh and history operations work with any subset of the dependencies.
_yt-clear-highlighting
_yt_history_search_active=1
_yt_history_search_prefix=echo
_yt_history_search_cursor=4
_yt_history_search_matches=('echo first' 'echo second')
_yt_history_search_pos=1
BUFFER='echo first'; CURSOR=$#BUFFER
_yt-history-search-forward
[[ $BUFFER == echo ]] || fail 'history restore'
print -- "Integration checks passed: $order ${autosuggestions:t} ${highlighting:t}"
