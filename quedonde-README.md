# quedonde Repository Search

`quedonde.py` is the bundled, single-file repository search tool. It maintains
an SQLite FTS5 index and supports filename/content search plus best-effort
structural symbol queries.

## Requirements

- Python 3.9 or newer
- A writable repository root for `.code_index.sqlite` and
  `.code_index.cache`

## Required Workflow

Verify the bundled command first:

```powershell
python quedonde.py --help
```

Create or update structural tables, then index the repository:

```powershell
python quedonde.py migrate
python quedonde.py index
```

Run a content search:

```powershell
python quedonde.py "relationship mutation"
python quedonde.py --json "runtime avatar"
python quedonde.py --fuzzy --context 2 "world semantics"
python quedonde.py --paths --title tests "motion"
```

The CLI writes matches to `stdout` and status messages to `stderr`.

## Search Options

- `--json` and `--paths` select structured or paths-only output.
- `--name`, `--content`, and `--fuzzy` control matching.
- `--context N` includes surrounding lines.
- `--lines` includes line numbers where supported.
- `--title TEXT` restricts matches by path.

Queries containing SQLite FTS operators are treated as raw expressions. Plain
phrases search paths and content.

## Structural Commands

After `migrate` and `index`, these commands expose the structural data that the
indexer recognized:

```powershell
python quedonde.py find --context 2 update_structural_data
python quedonde.py callers --json update_structural_data
python quedonde.py deps --limit 25 classify_intent
python quedonde.py explain structural_ready
python quedonde.py context update_structural_data --level 1
python quedonde.py ask "who calls update_structural_data"
```

`find` locates definitions, `callers` and `deps` inspect recognized edges,
`explain` combines structural views, `context` expands surrounding structure,
and `ask` deterministically routes a natural-language query to those handlers.

## Lua Coverage and Source Validation

The bundled repository's index is **not a complete Lua call graph**. During the
inspected repository index, `36` documents were added while a dependency query
for `world_semantics` returned no dependencies despite direct source consumers.
An empty structural result is therefore not proof that a Lua module is unused.

For architecture or deletion work:

1. Run `migrate` and `index`.
2. Use `quedonde.py` for connection-style discovery.
3. Search exact Lua module IDs, slash paths, `require`, and `loadfile` strings.
4. Open the matching source and verify the owning code directly.

Re-run `python quedonde.py index` after modifying or deleting files so stale
entries are purged. If structural tables are unavailable, run `migrate` before
indexing again.