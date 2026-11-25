# Live harness

The suites under `test/` run under fengari and a real Lua 5.4 against
hand-written native stubs. The resources in this folder run the same library on
a real FXServer, against FiveM's own natives. Use a test server, never one that
players are on: the lifecycle tier restarts `cis_libs`, and that restarts every
resource that depends on it.

| Resource | What it is |
|---|---|
| `cis_test` | The runner. The `cis_test` console command, the suites, the results files. |
| `cis_test_providers` | Recording fakes for the capability slots, so a run needs no framework. |
| `cis_test_b`, `cis_test_c` | Second and third consumers, for ownership and cleanup cases. |
| `cis_test_badmeta` | A consumer with a malformed manifest entry, which the library must refuse. |

[UNRUN.md](UNRUN.md) lists what has never produced a live result.

## Set up

1. Copy the repository folder into your server's `resources` as `cis_libs`,
   and the five folders above beside it.
2. Add to `server.cfg`, after `ensure cis_libs`:

   ```
   ensure cis_test_providers
   ensure cis_test_b
   ensure cis_test_c
   ensure cis_test_badmeta
   ensure cis_test

   add_ace resource.cis_test command.ensure allow
   add_ace resource.cis_test command.stop allow
   add_ace resource.cis_test command.start allow
   add_ace resource.cis_test command.restart allow
   add_ace resource.cis_test command.refresh allow
   add_ace resource.cis_test command.cis_force_unregister allow
   add_ace resource.cis_test command.cis_audit allow
   ```

   Without the ACE lines the lifecycle tier prints the command for you to type
   instead of running it.
3. Start the server.

## Run

From the server console (the command refuses players):

```
cis_test status
cis_test list
cis_test run server
cis_test run lifecycle
```

`cis_test run <tier|suite|all>` runs one tier, one suite or everything. The
`player` and `perf` tiers need one game client connected; without one their
cases SKIP, and a SKIP is not a pass. `cis_test abort` stops a run and
`cis_test restore` gives the capability slots back.

Each run prints one line per case and ends with a tally. It also writes a
results file and `status.json` inside the `cis_test` resource folder. Neither
names a player: a results file carries the player count only.

A run passes when the tally has no FAIL and the console shows no
`SCRIPT ERROR` from `cis_libs` or the harness.
