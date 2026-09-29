# Wellformed

Runs on a plate-reader PC, watches the export folder, and checks every new file with
[CHESSParsers](https://github.com/jensenlab/CHESS) so truncated or corrupt exports are caught
**before the plate is discarded**. A file is well-formed if it parses; a failure pops up a
blocking dialog and posts to a Basecamp Campfire. Successes are only logged.

```
julia --project -e 'using Wellformed; exit(main(["--check", "export.xlsx"]))'   # one-off check
wellformed wellformed.toml                                                       # watch mode
```

Checks: zero-byte / truncated zip (`.xlsx`), format detection, a full CHESSParsers parse, then
sanity checks (non-empty reads, equal reading counts per well, rectangular well blocks). Files are
only checked once they stop changing (`settle_seconds`), so a file still being written is not
reported as truncated.

Config: copy `wellformed.example.toml` to `wellformed.toml`. Basecamp: create a Campfire chatbot
and put its URL in `[basecamp] url` or `WELLFORMED_BASECAMP_URL`.

Deploy: `build/build_app.jl` on a Windows machine, copy `dist/wellformed/` and the config to the
instrument PC. Tests: `julia --project -e 'using Pkg; Pkg.test()'` (needs `../CHESS/CHESSParsers`).
