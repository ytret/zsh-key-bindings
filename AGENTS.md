# yt-key-bindings

Oh-My-Zsh plugin for shell-argument-aware key bindings (like fish's Alt-F/Alt-B/Alt-W etc).

## Loading order

`yt-key-bindings.plugin.zsh` sources in this order:

1. **`settings.zsh`** — removes `-`, `_`, `+` from `WORDCHARS`; autoloads `edit-command-line`
2. **`shell-arguments.zsh`** — argument parsing engine
3. **`widgets.zsh`** — all zle widgets + helper functions
4. **`bindings.zsh`** — pure `bindkey` calls

## Key bindings

| Key | Widget | Action |
|---|---|---|
| `^W` | `_yt-backward-kill-path-component` | Kill path component backward (complex) |
| `^[^W` | `_yt-backward-kill-shell-argument` | Kill backward to argument start |
| `^[^F` | `yt-forward-shell-argument` | Jump forward to next argument |
| `^[^B` | `_yt-backward-shell-argument` | Jump backward to previous argument |
| `^[^D` | `_yt-kill-shell-argument` | Kill forward to argument end |
| `^[^?` | `_yt-backward-kill-word` | Kill word backward (vanilla WORDCHARS) |
| `^U` | `backward-kill-line` | Kill to command start |
| `^[s` | `_yt-sudo` | Toggle `sudo` prefix |
| `^[e` | `edit-command-line` | Edit in $EDITOR |

## Argument parsing (`shell-arguments.zsh`)

- `_yt-parse-shell-arguments` splits `$BUFFER` with `${(@z)BUFFER}` (zsh's shell-word tokenizer), storing 0-indexed positions in global arrays `_yt_arg_starts` and `_yt_arg_ends`.
- Results are cached in `_yt_arg_cached_buffer`. Cache is invalidated when `$BUFFER` changes.
- `_yt-shell-argument-bounds-left-of-cursor` and `_yt-shell-argument-bounds-right-of-cursor` scan these arrays (backward/forward) and return `$reply=($start $end)`.

## Conventions

- **`reply=(...)` for return values**: helpers never use `echo`/`print`. Callers read `$reply[1]`, `$reply[2]` after checking status.
- **`_yt-kill-region-between $start $end`** for deletion: sets CURSOR/MARK/REGION_ACTIVE then calls `zle kill-region`. This puts killed text in the kill ring.
- **`_yt-` prefix** for internal functions and "private" widgets.
- **`yt-` prefix** (no underscore) for the one "public" widget (`yt-forward-shell-argument`), registered with autosuggestions.
- **Functions defined as** `function name { ... }` (no parentheses).
- **`zle -N`** registered immediately after each widget's function definition.

## Ctrl-W logic (`_yt-backward-kill-path-component`)

This is the most complex widget. It has three tiers:

1. **Path-aware deletion** (tries first):
   - If cursor is at a space position: trims trailing space, temporarily swaps buffer to the trimmed content, finds the shell argument bounds, then calls `_yt-path-parent-prefix` to compute the parent path.
   - If cursor is inside text: directly finds shell argument bounds and computes parent.
   - `_yt-path-parent-prefix` strips trailing `/`, then looks for a parent via `*/*`. If found, returns `${before_arg}${arg_prefix%/*}/`. If the stripped arg has no `/` AND the original ended with `/` (like `./` or `../`), returns just `$before_arg` (deletes the whole thing).

2. **`_yt-werase` fallback** (when path-aware fails):
   - If at a word character: delegates to `zle backward-kill-word`.
   - If at a separator: deletes one separator if preceded by word/space; deletes consecutive separators otherwise.

3. **Always runs `_yt-clear-highlighting`** afterward.

## `_yt-with-temporary-buffer` pattern

Swaps `$BUFFER`/`$CURSOR`, calls a callback, then restores. Used by `_yt-left-buffer-parent-path-after-trailing-space` to make the argument parser see a trimmed version of the buffer. The callback's `$reply` persists after restoration.

## Alt-Backspace logic (`_yt-backward-kill-word`)

Delegates to zsh's built-in `backward-kill-word` using the **original default `WORDCHARS`** (`*?_-.[]~=&;!#$%^(){}<>`), then restores the plugin's modified `WORDCHARS` afterward. This isolates the word-kill operation from the plugin's `WORDCHARS` changes, giving true vanilla zsh word-kill behavior. Also calls `_zsh_autosuggest_fetch` and `_zsh_autosuggest_highlight_apply` to refresh autosuggestions after the kill.

## `_yt-clear-highlighting`

Called after path deletions to flush zsh-syntax-highlighting caches and re-fetch autosuggestions. Prevents stale highlights.

## How to make changes

- **Add a new binding**: define the widget function in `widgets.zsh`, register with `zle -N`, add `bindkey` in `bindings.zsh`.
- **Add a new helper**: use a `_yt-` prefix, return values via `$reply`, callers check `|| return 1` on failure.
- **Change deletion behavior**: use `_yt-kill-region-between` (not direct BUFFER manipulation) so killed text goes to the kill ring.
- **Test Ctrl-W changes** with: `./` `../` `/` `foo/bar` `foo/bar/` `foo-bar` `foo` — verify path-aware and word-fallback both work.
- **Word behavior depends on `WORDCHARS`** — removing chars makes them word separators in `backward-word`/`backward-kill-word`.
