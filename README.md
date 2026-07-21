# dry4lua

Structural duplication detector for Lua source code.

Lua equivalent of [dry4go](https://github.com/unclebob/dry4go) and [dry4clj](https://github.com/unclebob/dry4clj).

## How it works

1. Tokenize each Lua source file
2. Extract function scopes
3. Normalize tokens within each scope (strip identifier names, literal values; keep keywords, operators, control flow)
4. Build structural fingerprints using sliding windows (size 3-7)
5. Compare all candidate pairs using Jaccard similarity over fingerprint sets
6. Report pairs that exceed the threshold

Size-based pruning eliminates ~80% of pairs before Jaccard comparison.

## Usage

```
bin/dry4lua [options] [file-or-directory ...]
lua5.4 bin/dry4lua [options] [file-or-directory ...]
```

`bin/dry4lua` is a self-contained entrypoint: it only sets `package.path`
to the repository's `lib/` and calls `dry4lua.cli`. Project tooling
standardizes on Lua 5.4 for this repository.

## Using dry4lua in a new project

dry4lua has no dependencies and no project-specific configuration, so any
project can adopt it as-is. Example: a project called `eggy`.

1. Vendor the repository into your project, e.g. as a git submodule or a
   pinned toolcache checkout at `eggy/vendor/dry4lua/`.
2. Run the entrypoint against your sources:

   ```
   lua5.4 vendor/dry4lua/bin/dry4lua src
   ```

   Or put the entrypoint on your `PATH` (`export PATH="$PWD/vendor/dry4lua/bin:$PATH"`)
   and simply call `dry4lua src`.
3. Alternatively, use it as a library from your own tooling:

   ```lua
   package.path = "vendor/dry4lua/lib/?.lua;" .. package.path
   local cli = require("dry4lua.cli")
   os.exit(cli.run(arg))
   ```

Options, defaults, and output formats are identical in all three modes.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--threshold N` | 0.82 | Minimum structural similarity score (0.0-1.0) |
| `--min-lines N` | 4 | Minimum source lines in a candidate function |
| `--min-nodes N` | 20 | Minimum normalized token count |
| `--limit N` | unlimited | Maximum text duplicate rows to print; `0` means unlimited |
| `--json` | | Output in JSON format |
| `--text` | | Output in text format (default) |

## Output

```
DUPLICATE score=0.89
  src/gameplay/dice.lua:12-25  roll_dice
  src/gameplay/movement.lua:30-44  advance_player
```

## Development

Run the test suite (pure Lua, no dependencies):

```
lua5.4 tests/run.lua
```

Run the full behavior check — unit tests, CLI output diff against the
baseline in `tests/baseline/`, and a syntax check of all sources:

```
sh tests/check.sh
```

Run the benchmark (repeated `find_duplicates` over the frozen corpus in
`tests/corpus/` and `tests/fixtures/`):

```
lua5.4 tests/bench.lua 500
```

The baseline captures the CLI output of the original implementation on the
frozen corpus, so refactors and optimizations can prove they did not change
behavior.
