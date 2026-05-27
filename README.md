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
lua tools/quality/dry.lua [options] [file-or-directory ...]
lua5.4 tools/quality/dry.lua [options] [file-or-directory ...]
```

Project tooling standardizes on Lua 5.4 for this repository.

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
