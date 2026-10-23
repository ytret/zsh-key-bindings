# Load Zsh key binding settings, helpers, widgets, and concrete bindings.

typeset -gr _YT_KEY_BINDINGS_DIR="${${(%):-%N}:A:h}"

source "$_YT_KEY_BINDINGS_DIR/settings.zsh"
source "$_YT_KEY_BINDINGS_DIR/shell-arguments.zsh"
source "$_YT_KEY_BINDINGS_DIR/widgets.zsh"
source "$_YT_KEY_BINDINGS_DIR/bindings.zsh"

# Configure partial acceptance even when autosuggestions loads later.
typeset -ga ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(yt-forward-shell-argument _yt-forward-word)
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=("${(@u)ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS}")

autoload -Uz add-zle-hook-widget add-zsh-hook

function _yt_zle_line_pre_redraw {
    (( $+functions[_zsh_highlight] )) && _zsh_highlight
    return 0
}

# The precmd hook also catches dependencies sourced after this plugin. Check
# widget identity so repeated prompts do not wrap an already wrapped widget.
function _yt-enable-optional-integrations {
    if (( $+functions[_zsh_autosuggest_bind_widget] )) &&
       [[ $widgets[_yt-forward-word] != user:_zsh_autosuggest_bound_* ]]; then
        _zsh_autosuggest_bind_widget _yt-forward-word partial_accept
    fi
    if (( $+functions[_zsh_highlight] )) && (( ! _yt_highlight_hook_added )); then
        add-zle-hook-widget zle-line-pre-redraw _yt_zle_line_pre_redraw
        typeset -g _yt_highlight_hook_added=1
    fi
    return 0
}

function _yt_zle_line_init {
    _yt-enable-optional-integrations
    _yt-history-search-reset
}
add-zle-hook-widget zle-line-init _yt_zle_line_init
add-zsh-hook precmd _yt-enable-optional-integrations
_yt-enable-optional-integrations
