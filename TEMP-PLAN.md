# Plugin correctness fixes

## Scope and intended behavior

Fix the seven review findings while preserving the current bindings and the
documented chunk navigation behavior. In particular, keep the current chunk-based
Alt-Backspace behavior; restoring the older vanilla WORDCHARS behavior described
elsewhere in AGENTS.md is outside this plan.

Alt-L must inspect a path without executing commands from the editing buffer.
Deletion must preserve everything outside the selected region and put removed
text in the kill ring. Optional highlighting and autosuggestion plugins must not
be required for the core widgets to work.

## 1. Prevent Alt-L from executing buffer contents

Affected code: `_yt-list-directory` in `widgets.zsh`.

- Remove `${(e)target_path}` and avoid replacement approaches based on `eval`.
- Introduce a helper that resolves a selected raw argument as a path without
  executing shell code. Return its result through `reply` and check its status.
- Support literal paths, shell quoting/escaping, and leading home-directory
  expansion. Preserve quote semantics: a quoted or escaped tilde is literal.
- If supporting environment variables, resolve only simple unquoted or
  double-quoted `$NAME` / `${NAME}` references through explicit parameter lookup.
  Do not recursively evaluate their values or perform field splitting.
- Reject command substitutions, process substitutions, arithmetic expressions,
  and unsupported expansion syntax with a concise message. Do not silently list
  the current directory when path resolution fails.
- Keep glob characters literal unless a separate globbing policy is explicitly
  chosen. An existence check should inspect the resolved path directly.

Verification: use a harmless command substitution that would create a marker in
a temporary directory; confirm Alt-L does not create it. Check both `$()` and
backtick syntax, including inside double quotes. Check that single-quoted or
escaped substitution syntax remains literal.

## 2. Fix quoted and escaped paths in Alt-L

Affected code: the same path-resolution helper and `_yt-list-directory`.

- Decode shell quotes and escapes as part of the safe resolver from step 1.
  Do not merely strip the first and last quote: mixed quoted/unquoted segments
  and escaped spaces must resolve as one path.
- Pass the resolved path as one argument to the listing command, retaining `--`.
- Continue using the current directory when no argument is selected; distinguish
  that case from an explicitly selected empty or invalid path.

Verification: select `/tmp`, `"/tmp"`, `'/tmp'`, a temporary path containing
spaces, its backslash-escaped form, and a mixed-quoting form. Check a missing path
and a path beginning with `-`. Combine this verification with step 1.

## 3. Preserve the right buffer and the kill ring in Ctrl-W

Affected code: `_yt-werase`, `_yt-replace-left-buffer-with-parent-path`, and
`_yt-backward-kill-path-component` in `widgets.zsh`.

- Replace the whitespace-only `BUFFER=""` branch with deletion of `[0, CURSOR)`.
- Refactor path-parent calculation to return the new left boundary without
  assigning to `LBUFFER`. Delete from that boundary to the original cursor via
  `_yt-kill-region-between`.
- Route separator deletion and trailing-space deletion through the same helper.
  Preserve the existing path/separator boundary rules.
- Keep highlighting refresh after deletion. Avoid direct `BUFFER`/`LBUFFER`
  mutation in these deletion branches so every successful deletion enters the
  kill ring.

Verification: `   |echo keep-this` must become `|echo keep-this`; verify the
suffix also survives path and separator deletion in the middle of a buffer.
Cover `./`, `../`, `/`, `foo/bar`, `foo/bar/`, `foo-bar`, `foo`, a backslash,
empty quoted arguments, and an unfinished double quote followed by a backslash.
Check killed text for the path, separator, and whitespace branches, and verify
that yank restores it.

## 4. Make lazy word chunks independent of the seed cursor

Affected code: `_yt-split-word-chunks` and chunk scan helpers in `widgets.zsh`.

- Normalize the initial seed to an actual alnum/non-alnum boundary, or merge the
  two seed-adjacent pieces when they have the same class. Do not retain an
  artificial boundary at the initial cursor.
- Preserve lazy loading and the invariant that cached chunks are contiguous,
  have positive lengths, and alternate character classes.
- Audit helpers that extend the cache to the left: prepending chunks changes
  indices, so reacquire a selected index after extension when needed.
- Apply the corrected cache to navigation and both word-deletion widgets.

Verification: seed inside `foobar` at cursor 3, move forward to 6, then backward
to 0. Seed again, move backward to 0, then forward to 6. Repeat inside a
non-alnum run. Verify the canonical `foo --bar`, `cat /foo`, and `foo-bar`
sequences, plus a buffer large enough to exercise cache extension and reseeding.

## 5. Derive shell-argument boundaries from raw source spans

Affected code: `_yt-parse-shell-arguments` in `shell-arguments.zsh` and its callers.

- Replace the assumption that tokenizer word lengths equal source lengths.
  Newlines may become operator tokens, while backslash-newline continuations
  disappear from tokenizer output.
- Track token start/end offsets in the original buffer with a source-span
  scanner. Account for whitespace, operators, quotes, escapes, and nested shell
  substitutions without executing input. Use zsh tokenization to check grouping
  where useful, rather than using its output lengths as source offsets.
- Treat newline separators consistently with other command separators, retaining
  their actual raw spans. A continued word must include its backslash-newline
  bytes in its source span.
- Tolerate incomplete input during editing, including unfinished quotes and
  substitutions. Preserve zero-based, start-inclusive/end-exclusive boundaries,
  caching, and `reply`-based bounds lookup.
- Have Alt-L resolve the selected raw span so its token selection cannot diverge
  from the parser. Verify `_yt-sudo` still identifies command separators.

Verification: inspect exact raw spans for `echo a\ncat b`, consecutive newlines,
a word continued across backslash-newline, quoted/escaped spaces, adjacent
operators, nested substitutions, Unicode, and incomplete input. Check forward
and backward argument movement, argument deletion, and sudo toggling on a later
line. Confirm no boundary exceeds the buffer length.

## 6. Make optional plugin integrations conditional

Affected code: `yt-key-bindings.plugin.zsh`, `_yt-clear-highlighting`, and direct
autosuggestion calls in `widgets.zsh`.

- Guard calls into autosuggestions and syntax highlighting with function
  existence checks. Missing integrations must not produce command-not-found
  messages or a failing plugin load.
- Keep partial-accept widget configuration available before autosuggestions
  loads. Bind the private forward-word widget once autosuggestions is available,
  using an idempotent deferred hook when it loads later.
- Register or invoke the redraw integration only when its dependency exists,
  and ensure later dependency loading can activate it without duplicate hooks.
- Centralize guarded refresh operations where practical so deletion and history
  widgets use the same dependency checks.

Verification: load with neither dependency, each dependency separately, and both
dependencies before/after this plugin. Check load status and stderr, exercise the
affected widgets, and confirm partial suggestion acceptance still works when
autosuggestions is present.

## Execution order and completion checks

1. Implement safe Alt-L resolution and quote handling together (steps 1–2).
2. Fix Ctrl-W region deletion and kill-ring behavior together (step 3).
3. Correct chunk-cache seeding and extension (step 4).
4. Replace argument offset reconstruction and adapt its consumers (step 5).
5. Guard and defer optional integrations (step 6).
6. Document supported Alt-L expansion behavior and optional integrations.

Use direct widget/helper calls in `zsh -f`, with a timeout on every test command.
Stub ZLE dispatch only where necessary and explicitly check deletion ranges and
kill-ring behavior; do not build a PTY/expect harness. Keep regressions focused
on the reported failures and important boundary cases. Run `zsh -n` separately
for each plugin file, review the final diff, and stop once these checks pass.
