# cis_libs — live server smoke run

Recorded from a real running server, not from the fengari suite. The suite proves
contracts; this file records what a real FiveM runtime did.

## 2026-11-02 — after the final-review fixes

The live harness's `server` tier at commit bccd09d, no player.

| Server | Live run |
|---|---|
| Qbox | `run-20261102-113124` pass 24 fail 0 |
| QBCore | `run-20261102-113612` pass 24 fail 0 |
| ESX Legacy | `run-20261102-114409` pass 24 fail 0 |

After a full restart of each server: 0 script errors. Qbox starts cis_libs,
cis_bridge, ox_inventory and an inventory test resource from server.cfg. The QBCore and ESX
test servers do not ensure the cis resources in server.cfg and run no
ox_inventory; cis_libs, cis_bridge and that test resource were started from the
console after the restart, with 0 script errors.

The idle figures below were not measured again: the fixes touch no idle path.

## 2026-11-01 — release check

Each server ran the live harness's `server` tier while `profiler record 500` was
recording. A second record started about 90 s after boot, with no live cases
running, gives the idle figure. ms per frame is the sum of the
`tick (cis_libs)` spans divided by 500 frames. The active figure in brackets
leaves out the one-off self-check, because the run restarts cis_libs about
20 s before the cases start.

| Server | Live run | Idle ms/frame | Active ms/frame (without self-check) | Self-check ms |
|---|---|---|---|---|
| Qbox | `run-20261101-133321` pass 23 fail 0 | 0.0042 | 0.0181 (0.0047) | 6.679 |
| QBCore | `run-20261101-134028` pass 23 fail 0 | 0.0034 | 0.0194 (0.0065) | 6.428 |
| ESX Legacy | `run-20261101-134718` pass 23 fail 0 | 0.0023 | 0.0165 (0.0047) | 5.929 |

After a full restart of each server: 0 script errors. On Qbox, cis_libs,
cis_bridge, ox_inventory and the test resource all started; for QBCore and ESX
see 2026-11-02 above.

`bench/loadsim.lua` drives every per-player path for 1 to 128 simulated
players. Every path grows in a straight line with the player count.


## 2026-10-24 — with a game client connected

The full harness (server, player, lifecycle, modules, perf and examples tiers)
on a test server with one game client joined: `run-20261024-115302`, pass 38,
fail 0, skip 0, error 0.

## Before 2026-10-24

Earlier live runs on development builds (2026-10-02 to 2026-10-06) checked the
capability registry, export boundaries, the audit log and networked entity
creation on a real server. Their findings were fixed before the runs above,
which supersede them.
