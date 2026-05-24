# Load Zsh key binding settings, helpers, widgets, and concrete bindings.

typeset -gr _YT_KEY_BINDINGS_DIR="${${(%):-%N}:A:h}"

source "$_YT_KEY_BINDINGS_DIR/settings.zsh"
source "$_YT_KEY_BINDINGS_DIR/shell-arguments.zsh"
source "$_YT_KEY_BINDINGS_DIR/widgets.zsh"
source "$_YT_KEY_BINDINGS_DIR/bindings.zsh"

# zsh-syntax-highlighting on zsh >=5.9 selects the pre-redraw codepath,
# but its own hook is registered only when [[ -o zle ]] at plugin load
# time — which is false during startup.  Consequently, _zsh_highlight is
# never called by zsh-syntax-highlighting's own mechanism.  We register a
# zle-line-pre-redraw hook that calls _zsh_highlight directly.
autoload -U add-zle-hook-widget
_yt_zle_line_pre_redraw() {
  _zsh_highlight
}
add-zle-hook-widget zle-line-pre-redraw _yt_zle_line_pre_redraw

# Integrate with zsh-autosuggestions: pressing Ctrl-Alt-F accepts the next
# shell argument from the suggestion (like fish's word-accept but
# argument-aware).
{
  typeset -ga ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS
  ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(yt-forward-shell-argument)
}
