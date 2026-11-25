<p align="center"><a target="_blank" rel="noopener" href="https://cisoko.net"><img src="docs/img/banner.svg" alt="cis_libs: Zero-dependency base library for FiveM" width="100%"></a></p>

<p align="center">
<a target="_blank" rel="noopener" href="https://github.com/cisoko-net/cis_libs/releases/latest"><img src="docs/img/badge-version.svg" alt="version 1.0.0"></a>
<a target="_blank" rel="noopener" href="https://github.com/cisoko-net/cis_libs/blob/main/LICENSE.md"><img src="docs/img/badge-license.svg" alt="license: source-available"></a>
<a target="_blank" rel="noopener" href="https://docs.fivem.net/docs/server-download/"><img src="docs/img/badge-fxserver.svg" alt="FXServer 4500+"></a>
</p>

<p align="center">
<a target="_blank" rel="noopener" href="https://github.com/cisoko-net/cis_libs/releases/latest"><img src="docs/img/button-download.svg" alt="Download"></a>
<a target="_blank" rel="noopener" href="https://cisoko.net/docs/cis-libs/"><img src="docs/img/button-docs.svg" alt="Documentation"></a>
<a target="_blank" rel="noopener" href="https://cisoko.net"><img src="docs/img/button-website.svg" alt="Website"></a>
<a target="_blank" rel="noopener" href="https://discord.cisoko.net"><img src="docs/img/button-discord.svg" alt="Discord"></a>
<a target="_blank" rel="noopener" href="https://github.com/cisoko-net/cis_libs"><img src="docs/img/button-github.svg" alt="GitHub"></a>
</p>

# cis_libs

`cis_libs` is the zero-dependency base library for FiveM (**1.0.0**, contract **`api = 1`**). It is free and source-available.

- Zero runtime dependencies. You do not need a framework, `ox_lib`, or `oxmysql` for `cis_libs` itself.
- Shared boundary of the Cisoko platform: naming, marshalling, gating, and 24 pure-Lua modules.
- Owns no database table, reads no config file, and never calls a third-party resource by name.
- Products (`cis_core`, `cis_bridge`, `cis_keys`) register into it. A server running `cis_libs` alone still boots.

The machine-readable contract is [`api.lua`](api.lua). Signatures live in [`DOCUMENTATION.md`](DOCUMENTATION.md), generated from `api.lua`.

## Tested & performance

Figures for 1.0.0: stubbed suites on 2026-11-16, live servers on 2026-11-01 and 2026-11-02.

- **Stubbed suites:** **4,456 assertions** across 9 suites under fengari and real Lua 5.4. 0 failed.
- **Live servers:** 24 server cases pass on Qbox, QBCore, and ESX Legacy (2026-11-02), with 0 script errors after a full restart.
- **Server cost:** **0.0023 to 0.0042 ms** per server frame idle (`profiler record 500`), **0.0047 to 0.0065 ms** active. The self-check runs once at boot (~6 ms).
- **Load:** Simulation of 1 to 128 players scales linearly with player count.

Run ids and full tables are in [test/LIVE.md](test/LIVE.md).

## Install

> **Note:** You need OneSync on and FXServer build 4500 or later.

1. **Download the release, not the source.** On the [releases page](https://github.com/cisoko-net/cis_libs/releases), download `cis_libs-<version>.zip` and `SHA256SUMS`. Do not use **Code → Download ZIP**: that is the development tree with tests in a folder named `cis_libs-main`.
2. **Check the download.** In the folder holding both files:

   ```bash
   sha256sum -c SHA256SUMS        # Linux (must print OK)
   Get-FileHash cis_libs-*.zip    # Windows PowerShell (compare with SHA256SUMS)
   ```

3. **Unzip into `resources`.** Keep the folder name `cis_libs` exactly: resources load `@cis_libs/init.lua` by it, and the licence requires it. When replacing an older copy, stop the server, delete the old `cis_libs` folder, then unzip.
4. **Add to `server.cfg`**, after your framework and `oxmysql` and before every resource that uses `cis_libs`:

   ```cfg
   ensure cis_libs
   ```

5. **Start the server and check it.** Run `cis_doctor` in the server console. It prints `[cis_libs] self-check: ok`. At boot, `[cis_libs] SECURITY: door and sync mutations are REFUSED` is expected on a fresh install until you authorise resources (see **Trust and Security** below).

A resource written for an earlier, unpublished build may log `cis_libs: <resource> uses "<name>", deprecated since 1.0.0 and removed in 2.0.0`. It still works; the line is for that resource's author.

### For resource authors

```lua
-- consumer fxmanifest.lua — both lines, always
dependency 'cis_libs'
shared_script '@cis_libs/init.lua'
```

Never `shared_script` any other file from `cis_libs`. Call exports with a colon (`:`), never a bracket:

```lua
local caps = exports['cis_libs']:GetCapabilities()
assert(type(caps) == 'table')
```

## Modules

Twenty-four pure-Lua modules (`Cis.requireList()` names them) load on demand into the calling resource's own Lua state, with no global left behind:

```lua
local semver = Cis.require('semver')
local ok = semver.satisfies('1.4.2', '^1.2')   -- true
```

| Need | Module |
|---|---|
| Translations from `locales/<lang>.json`, convar `cis:locale` | `locale` |
| Levelled console output, convar `cis:printlevel[:<resource>]` | `print` |
| Pausable timers, `setTimeout` / `setInterval` with cancellation | `timer` |
| Cron schedules (`*/15 9-17 * * mon-fri`, `@daily`), server only | `cron` |
| Classes with inheritance and private fields | `class` |
| Arrays with an explicit length, stable sort, groupBy, chunk, zip | `array` |
| Set, ring buffer, heap, LRU, sparse set | `set`, `ringbuffer`, `heap`, `lru`, `sparse` |
| Rounding, remap, hex, digit grouping, weighted pick | `mathx` |
| Case, split, fuzzy match, `random('1AA111')` | `string` |
| Seeded randomness, ids, semver, JSON, validation, durations | `random`, `id`, `semver`, `json`, `validate`, `time` |
| Easing, damping, splines, rate limits, sliding windows | `interp`, `curve`, `rate`, `window` |
| Deep copy, merge, sorted keys | `table` |

```lua
local locale, print = Cis.require('locale'), Cis.require('print')
print.info(locale.t('shop.welcome', { name = 'Ana' }))

-- cron is server only: it reads the wall clock, which the client has no access to.
if IsDuplicityVersion() then
    local cron = Cis.require('cron')
    cron.schedule('0 4 * * *', function() print.info('nightly cleanup') end)
end
```

Your own files load the same way: `Cis.require('client.utils')` reads `client/utils.lua` from the calling resource and `Cis.require('@other_resource/shared/config')` from another. Each file is read once per Lua state, as text only, into its own environment; a circular require raises and names the chain ([DOCUMENTATION.md](DOCUMENTATION.md) §5.1).

## Handlers

Zones, points, and keybinds made through `init.lua` run in **your** resource's VM, so their handlers are plain functions, nothing crosses per frame ([DOCUMENTATION.md](DOCUMENTATION.md) §5.2), and they survive a `cis_libs` restart:

```lua
Cis.zones.box('shop', vector3(1.0, 2.0, 3.0), vector3(4.0, 4.0, 3.0), {
    onEnter = function(zone) Cis.ui.textUI.show('[E] Shop') end,
    onExit = function(zone) Cis.ui.textUI.hide() end,
})
```

Hook and callback handlers still cross the exports boundary: use an event name or `'resource:export'` there.

## More details

<details>
<summary><b>Trust and Security</b></summary>

Client asks, server decides. Players are untrusted; server resources are trusted code.

- **Mutating exports** (`SyncCreate`, door writes, etc.) consult `Security.AuthorizedResources`. An empty list is always restrictive and prints the fix when refusing a caller.
- **Configuration:** `SetConfig(config, security, discord)` is first caller wins (`cis_core` is the intended supplier). On production, pin both in `server.cfg`:
  ```cfg
  set cis_config_supplier "cis_core"
  set cis_authorized_resources "cis_core,my_resource"
  ```
- **Clients:** Every net event `cis_libs` owns checks `source`, is rate limited per player, and bounds its payload. Players run at most 10 `cis_libs` commands/sec.
- **Open exports:** `Inventory*`, `SendDiscordLog`, and `Db*` are not behind `Security.AuthorizedResources`; they forward directly. Install only server resources you trust.
- **Your own events:** A point's or zone's event, or a context option's `serverEvent`, is fired by the client. Re-derive position with `GetEntityCoords(GetPlayerPed(source))` and never trust price, item, or count from the client.
- **Diagnostics:** Console commands `cis_debug` and `cis_doctor`. `exports['cis_libs']:GetDiagnostics({ collect = true })` returns counts only, never player data.
- **Version check:** Off by default. When on, fetches only an `https://` `Config.VersionCheckUrl` (max 512 chars).

</details>

<details>
<summary><b>Development and Testing</b></summary>

```bash
npm ci
npm test              # every suite under fengari (Lua 5.3 semantics)
npm run test:all      # full gate CI runs, including real Lua 5.4
npm run test:mutate   # every known defect must break the suite
```

`npm run test:lua54` needs `lua5.4` on `PATH` (or `LUAC_LUA54`).

Three testing tiers:
- **Stubbed** (`npm run test:all`): suites under fengari and real Lua 5.4 against hand-written native stubs.
- **Live server** (`test/live/`): runs `server` and `lifecycle` tiers on a real FXServer (restarts `cis_libs`; run on a test server only).
- **Player** (`cis_test run player`): zones, points, debug draw, client sync spawn path, and `perf` tier.

See [test/live/README.md](test/live/README.md) and [test/live/UNRUN.md](test/live/UNRUN.md).

</details>

## Compatibility

| Item | Status |
|---|---|
| FXServer | Build 4500 or newer. OneSync must be enabled. |
| Dependencies | None. Does not require a framework, `ox_lib`, or `oxmysql`. |
| Frameworks | Tested on Qbox, QBCore, and ESX Legacy ([test/LIVE.md](test/LIVE.md)). |
| Contract | `api = 1` ([api.lua](api.lua)). |

## Documentation

| Topic | Link |
|---|---|
| Signatures & internals | [DOCUMENTATION.md](DOCUMENTATION.md) |
| Migrating from ox_lib | [docs/MIGRATING-FROM-OX_LIB.md](docs/MIGRATING-FROM-OX_LIB.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Live test run ids | [test/LIVE.md](test/LIVE.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Security policy | [SECURITY.md](SECURITY.md) |
| Licence | [LICENSE.md](LICENSE.md) |

## Support and licence

- Help: [Discord](https://discord.cisoko.net).
- Bugs and pull requests: [CONTRIBUTING.md](CONTRIBUTING.md).
- Security problems: [SECURITY.md](SECURITY.md) (report privately, never file a public issue).
- Licence: Cisoko Platform Source-Available License 1.0, in [LICENSE.md](LICENSE.md).
- More FiveM resources by Cisoko: [cisoko.net](https://cisoko.net).

Author: Cisoko. Source: https://github.com/cisoko-net/cis_libs.
