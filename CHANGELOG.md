# Changelog

All notable changes to `cis_libs`. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

The **contract** is versioned separately and is `api = 1`.

## 1.0.0 (2026-11-02)

The first public release: the free base library of the Cisoko platform.

### For server owners

- **Install from the release zip** and keep the folder name `cis_libs`;
  README.md § Install has the steps, including the checksum.
- **Nothing to configure for a fresh install.** At boot, a
  `SECURITY: door and sync mutations are REFUSED` block is expected until a
  resource that needs those writes is authorised (DOCUMENTATION.md §3).
- **Idle cost** measured on Linux FXServer with no player, beside cis_bridge:
  0.0023 to 0.0042 ms per server frame on the
  ESX, QBCore and Qbox test servers (test/LIVE.md).
- **Licence:** the Cisoko Platform Source-Available License 1.0
  ([LICENSE.md](LICENSE.md)), the licence of `cis_database`.
- **Report a vulnerability privately** (SECURITY.md).

### Changed during release review

- Hook priority: a numeric string is refused, NaN and infinity are refused,
  and nil becomes 0.
- `cis_doctor` prints `self-check: pending (runs 20 s after boot)` in the
  first 20 s instead of a false problem list.
- Sync record fingerprints skip `rev`, `print`, `id` and `owner` at every
  depth and length-prefix strings, so records that differ only inside a
  nested table are no longer merged.
- Polygon zones accept `vector2` points (the PolyZone `vec2(x, y)` form with
  `minZ`/`maxZ`); before, every such point was refused as not finite.
- A client-local synced ped or object picks up a later change to `freeze`,
  `invincible` or `blockEvents` on the same model; before, the update moved
  it and kept the flags it spawned with.

### Known issues

- Beside ox_inventory with large stashes, two stash warnings appear
  (`mechanicstash` 500 slots, `policetrash_1` 300 slots). They come from
  those stash definitions.
- LOW review findings deferred to 1.0.1; none affects security, data or
  correctness.

### What is in it

- **Zones, points and a spatial grid**: polygon, box and sphere zones and
  points, with enter, exit and inside events, on the server and the client.
- **Owned names**: callbacks, commands, keybinds and net events are owned by
  the resource that registers them; a name another resource holds is refused.
  `Cis.command.addMany` adds a batch of commands with one read of the server's
  command list.
- **Hardened net boundary**: every net event cis_libs owns checks `source`,
  bounds its payload and is rate limited per player.
- **Synced entities**: peds, vehicles and props the server declares are
  spawned on each client in range; an entry that did not change is not sent
  again.
- **Hooks, a capability registry and a self-check** (`cis_doctor`,
  `GetSelfCheck`), with an opt-in update notice that reads `version.txt`.
- **A first-party NUI**: notifications, progress bars, context and list
  menus, a radial menu, input and confirm dialogs, skill checks and text UI.
- **Twenty-four pure-Lua modules** loaded on demand with `Cis.require`
  (README.md § Modules).
- Every export answers `false` plus a reason when it refuses; the machine
  readable contract is `api.lua`, and DOCUMENTATION.md is generated from it.

### Deprecated

Deprecated in 1.0.0 and removed in 2.0.0. These names are kept so resources
written for the earlier, unpublished builds keep working. cis_libs logs one
warning per calling resource and per name, which is forgotten when that
resource stops.

- **The framework, inventory, inventoryProvider, target, doors and
  doorsClient slots** belong to cis_bridge, which detects the framework,
  inventory and target and exposes its own player, inventory, target and
  doors API. The raw exports `GetNormalizedPlayer`, `InventoryCount`,
  `InventoryHas`, `InventoryAdd`, `InventoryRemove`, `RequestInventorySync`,
  `PublishInventory`, `CreateTarget`, `RemoveTarget`, `UpdateTarget`,
  `TargetExists`, `TargetAvailable`, `AddDoorToSystem`, `AddDoorGroup`,
  `GetDoorState`, `GetAllDoorData`, `LockDoors`, `UnlockDoors`, `BreakDoor`,
  `FixDoor`, `RequestLockDoors`, `RequestUnlockDoors` and `GetClosestDoor`
  are deprecated with them, and so are the `Cis.framework.player`,
  `Cis.inventory.*`, `Cis.target.*` and `Cis.doors.*` proxies.
  `Notify` and `ShowNotification` stay: they never warn, because the
  notification has a built-in fallback that does not need a framework.
- **The database slot and the `Db*` exports** (`DbQuery`, `DbSingle`,
  `DbScalar`, `DbInsert`, `DbUpdate`, `DbTransaction`, and `Cis.db.*`).
  Call the oxmysql API (`MySQL.query.await` and its siblings) directly; it is
  served by oxmysql or by cis_database.
- **The dataProbe and migration slots** belong to cis_core.
- **`DetectFramework`, `DetectDatabase` and `GetKnownTargets`** belong to the
  cis_bridge detection.
- **The events `cis_libs:client:inventory` and `cis_libs:server:inventorySync`**
  go with the inventory slot. The server handler does not warn, because the
  sender is a player rather than a resource; `RequestInventorySync`, which
  fires it, warns its caller instead.
- **The config keys `Framework.Type`, `Framework.Inventory`,
  `Framework.Target.*` and `Framework.Database.*`** belong to the cis_bridge
  config, because choosing a framework, inventory, target or database driver is
  detection. `Framework.Zones.Enabled` stays. Config keys do not warn.
- The `security`, `ui` and `discord` slots and the generic registry are not
  deprecated. The types file marks every deprecated export and proxy
  `---@deprecated` with its replacement.
