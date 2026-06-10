# Bind custom widgets to the escape sequences used in this shell setup.

bindkey '^[l' _yt-list-directory
bindkey '^[^F' yt-forward-shell-argument
bindkey '^[^B' _yt-backward-shell-argument
bindkey '^[^W' _yt-backward-kill-shell-argument
bindkey '^[^D' _yt-kill-shell-argument
bindkey '^[^?' _yt-kill-current-word
bindkey '^U' backward-kill-line
bindkey '^W' _yt-backward-kill-path-component
bindkey '^[s' _yt-sudo
bindkey '^[e' edit-command-line
