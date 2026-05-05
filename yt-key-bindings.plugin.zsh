# Load Zsh key binding settings, helpers, widgets, and concrete bindings.

typeset -gr _YT_KEY_BINDINGS_DIR="${${(%):-%N}:A:h}"

source "$_YT_KEY_BINDINGS_DIR/settings.zsh"
source "$_YT_KEY_BINDINGS_DIR/shell-arguments.zsh"
source "$_YT_KEY_BINDINGS_DIR/widgets.zsh"
source "$_YT_KEY_BINDINGS_DIR/bindings.zsh"
