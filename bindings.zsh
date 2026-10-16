# Bind custom widgets to the escape sequences used in this shell setup.

# Treat Shift-Tab as Tab, preserving whatever widget Tab is bound to.
bindkey -s '^[[Z' '^I'
bindkey -s '^[[9;2u' '^I'

bindkey '^[l' _yt-list-directory
bindkey '^[b' _yt-backward-word
bindkey '^[f' _yt-forward-word
bindkey '^[d' _yt-forward-kill-word
bindkey '^[^F' yt-forward-shell-argument
bindkey '^[^B' _yt-backward-shell-argument
bindkey '^[^W' _yt-backward-kill-shell-argument
bindkey '^[^D' _yt-kill-shell-argument

# CSI-u equivalents for Ctrl-Alt keys when extended keyboard reporting is
# enabled (for example, tmux with extended-keys-format csi-u).
# Modifier 7 = 1 + Alt (2) + Ctrl (4); retain the legacy bindings above.
bindkey '^[[102;7u' yt-forward-shell-argument
bindkey '^[[98;7u' _yt-backward-shell-argument
bindkey '^[[119;7u' _yt-backward-kill-shell-argument
bindkey '^[[100;7u' _yt-kill-shell-argument

bindkey '^D' delete-char
bindkey '^[^?' _yt-backward-kill-word
bindkey '^U' backward-kill-line
bindkey '^W' _yt-backward-kill-path-component
bindkey '^[s' _yt-sudo
bindkey '^[e' edit-command-line
