* `CTRL-ALT-F` – move cursor to next argument
* `CTRL-ALT-B` – move cursor to previous argument
* `CTRl-ALT-W` – delete from cursor to argument start
* `CTRL-ALT-D` – delete from cursor to argument end
* `ALT-BACKSPACE` – delete from cursor to word start
* `CTRL-U` – delete from cursor to command start
* `CTRL-W` – delete from cursor to path component start
* `ALT-S` – toggle `sudo`
* `ALT-E` – edit command in `$EDITOR`
* `ALT-F` / `ALT-B` – move across alphanumeric and punctuation chunks
* `ALT-D` – delete the next chunk
* `ALT-L` – list the path under the cursor

Regression checks (run from this directory):

```sh
timeout 10 zsh -f tests/regressions.zsh
timeout 10 zsh -f tests/list-directory.zsh
```

To check a particular optional-plugin load order, pass `before` or `after` and
the two dependency paths (use an empty string for an absent dependency):

```sh
timeout 10 zsh -f tests/integrations.zsh after \
  ../zsh-autosuggestions/zsh-autosuggestions.zsh \
  ../zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```
