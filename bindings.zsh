# Bind custom widgets to the escape sequences used in this shell setup.

bindkey '^[l' _yt-list-directory

# Fish-style Alt-F / Alt-B move by shell argument.
bindkey '^[f' yt-forward-shell-argument
bindkey '^[F' yt-forward-shell-argument
bindkey '^[b' _yt-backward-shell-argument
bindkey '^[B' _yt-backward-shell-argument

# Ctrl-Alt-F / Ctrl-Alt-B variants (used by some terminal setups).
bindkey '^[^F' yt-forward-shell-argument
bindkey '^[^B' _yt-backward-shell-argument

bindkey '^[^W' _yt-backward-kill-shell-argument
bindkey '^[^D' _yt-kill-shell-argument
bindkey '^[^?' _yt-backward-kill-word
bindkey '^U' backward-kill-line
bindkey '^W' _yt-backward-kill-path-component
bindkey '^[s' _yt-sudo
bindkey '^[e' edit-command-line

bindkey '^P' _yt-history-search-backward
bindkey '^N' _yt-history-search-forward
bindkey '^[[A' _yt-history-search-backward
bindkey '^[[B' _yt-history-search-forward
