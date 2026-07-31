# dry4lua

Structural duplication detector for Lua source code.

Lua equivalent of [dry4go](https://github.com/unclebob/dry4go) and [dry4clj](https://github.com/unclebob/dry4clj).

## How it works

1. Parse each Lua source file with [luacheck](https://github.com/lunarmodules/luacheck)
2. Extract function scopes from the AST
3. Normalize each function's subtree: identifiers become `ident`, literals become
   `literal/<KIND>`, function-call callees become `callee`, operators stay in the
   tag (e.g. `op/add`), and keyword tags are unchanged
4. Build structural fingerprints as the set of all serialized normalized subtrees
   (s-expression style: `(tag child1 child2 ...)`)
5. Compare all candidate pairs using Jaccard similarity over fingerprint sets
6. Report pairs that exceed the threshold

Nested functions are collapsed to a `(function)` leaf during normalization so
that a parent function's fingerprints do not include the child's body details,
and same-file entries whose line ranges overlap (a parent and its nested child)
are excluded from pairwise comparison, matching dry4java's `overlaps` semantics.

Size-based pruning eliminates ~80% of pairs before Jaccard comparison.

## Upstream Alignment (对齐上游)

`dry4lua` follows the "Lua faithful implementation of the upstream spec"
doctrine: whatever dry4clj / dry4go / dry4java do identically is the spec and
is copied verbatim; anything different is a deliberate deviation, recorded
here with its reason. Cross-repo decisions live as ADRs in the luatools notes
repo (`projects/luatools/docs/adr/`).

**Aligned invariants (对齐不变量)**

- Default parameters `threshold 0.82 / min-lines 4 / min-nodes 20` and the
  option set.
- Fingerprints = the set of serialized normalized subtrees; similarity =
  Jaccard.
- Detection unit = function scope (structurally identical to dry4go's
  `FuncDecl`).
- Text output skeleton (`DUPLICATE score=%.2f` + two `file:start-end` lines,
  `No duplicate candidates found.` when empty) and exit code 2 on unknown
  format.
- Normalization keeps operators/keywords in the tag while stripping
  identifiers and literals (closest to dry4go).

**Deliberate deviations (有意偏离)**

- JSON output with a function `name` field (dry4go also emits JSON; clj/java
  emit EDN) — CI/tooling consumption.
- Extra `--limit` option for text output.
- File collection delegates to external `find`.

## Usage

```
bin/dry4lua [options] [file-or-directory ...]
lua5.4 bin/dry4lua [options] [file-or-directory ...]
```

`bin/dry4lua` is a self-contained entrypoint: it only sets `package.path`
to the repository's `lib/` and calls `dry4lua.cli`. Project tooling
standardizes on Lua 5.4 for this repository.

## Using dry4lua in a new project

1. Install luacheck (runtime dependency):

   ```
   luarocks install luacheck
   ```

2. Vendor the repository into your project, e.g. as a git submodule or a
   pinned toolcache checkout at `eggy/vendor/dry4lua/`.
3. Run the entrypoint against your sources:

   ```
   lua5.4 vendor/dry4lua/bin/dry4lua src
   ```

   Or put the entrypoint on your `PATH` (`export PATH="$PWD/vendor/dry4lua/bin:$PATH"`)
   and simply call `dry4lua src`.
4. Alternatively, use it as a library from your own tooling:

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
| `--min-nodes N` | 20 | Minimum AST node count in a candidate function |
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

Install the runtime dependency:

```
luarocks install luacheck
```

Run the test suite:

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

The baseline captures the CLI output of the implementation on the frozen
corpus. It was regenerated when the fingerprint strategy moved from token
sliding-windows to serialized normalized AST subtrees; in this corpus the
reported duplicate pair and score remained identical.
