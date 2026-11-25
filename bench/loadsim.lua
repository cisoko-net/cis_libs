-- cis_libs player-load simulation.
--
--   lua bench/loadsim.lua <players>        (run from the repo root; default 64)
--
-- WHAT THIS IS. The library's own server Lua (fxmanifest shared_scripts, then
-- server_scripts) loaded unmodified under stock Lua 5.4 with the FiveM natives
-- stubbed, then driven for 60 SIMULATED seconds per workload by <players> fake
-- players. CPU is os.clock around the whole 60 s run (os.clock ticks in 1 ms
-- steps on this box, so per-call timing would be noise), minus a "dry" baseline:
-- the same driver loop (player movement, scheduler, argument construction) with
-- the library work removed. Best of REPS repetitions of each.
--
-- WHAT THIS IS NOT. Not resmon. Native cost (GetEntityCoords, TriggerClientEvent,
-- msgpack, the event queue) is excluded because the natives are stubs, and stock
-- PUC Lua 5.4 is not CfxLua. Numbers are RELATIVE, and an upper bound of the
-- Lua-side cost of the library's own code, nothing more. The shape of the curve
-- over players (the scaling ratio) is the part worth reading.

-- This file stands in for the engine: it defines the natives the library
-- calls, so writing those globals is the point here, not a mistake.
-- luacheck: ignore 121 122 142

local N = tonumber(arg and arg[1]) or 64
local SIM_SECONDS = 60
local STEP_MS = 50
local REPS = tonumber(arg and arg[2]) or 3
local MAP_SPREAD = 1500.0 -- half-extent of the "spread" layout, metres
local MAP_HUB = 150.0     -- half-extent of the "hub" layout, metres

math.randomseed(20261101)

-- ------------------------------------------------------------------ the sim
local sim = {
    now = 60000, -- a server that has been up a minute; some code treats 0 as "unset"
    threads = {},
    seq = 0,
    errors = {},
    prints = 0,
    missing = {},
    counts = {},     -- client event name -> calls
    entries = 0,     -- syncBatch upserts + removes carried
    triggers = 0,    -- TriggerEvent (server-local) calls
    netEvents = {},  -- name -> { fn }
    handlers = {},   -- name -> { fn }
    loadErrors = {},
}

local real = { print = print, collectgarbage = collectgarbage }

-- A coroutine per CreateThread; Wait yields the sleep. Run order is wake time,
-- then creation order, which is what the engine's scheduler gives within a tick.
function CreateThread(fn)
    sim.seq = sim.seq + 1
    sim.threads[#sim.threads + 1] = {
        co = coroutine.create(fn), wake = sim.now, seq = sim.seq,
    }
end
function Wait(ms)
    ms = tonumber(ms) or 0
    if coroutine.isyieldable() then
        coroutine.yield(ms)
    else
        sim.now = sim.now + ms
    end
end
function SetTimeout(ms, fn)
    CreateThread(function()
        Wait(ms)
        fn()
    end)
end
function GetGameTimer() return sim.now end

local function runDueThreads()
    local guard = 0
    while true do
        local pick, pi
        local list = sim.threads
        for i = 1, #list do
            local t = list[i]
            if t.wake <= sim.now and (not pick or t.wake < pick.wake
                or (t.wake == pick.wake and t.seq < pick.seq)) then
                pick, pi = t, i
            end
        end
        if not pick then return end
        guard = guard + 1
        if guard > 100000 then
            sim.errors[#sim.errors + 1] = 'scheduler guard tripped (a thread loops on Wait(0))'
            return
        end
        local ok, ms = coroutine.resume(pick.co)
        if not ok then
            sim.errors[#sim.errors + 1] = tostring(ms)
            table.remove(list, pi)
        elseif coroutine.status(pick.co) == 'dead' then
            table.remove(list, pi)
        else
            pick.wake = sim.now + (tonumber(ms) or 0)
            pick.seq = sim.seq + 1
            sim.seq = sim.seq + 1
        end
    end
end

-- ------------------------------------------------------------ the fake world
local players = {}   -- src -> { x, y, z, vx, vy }
local playerList = {} -- GetPlayers() result: cached, so the native's cost is excluded
local names = {}

local world = { half = MAP_SPREAD }

local function relayout(half)
    world.half = half
    for src = 1, N do
        local speed = (src % 3 == 0) and 2.0 or 20.0 -- a third on foot, the rest driving
        local a = math.random() * 2 * math.pi
        players[src] = {
            x = (math.random() * 2 - 1) * half,
            y = (math.random() * 2 - 1) * half,
            z = 30.0,
            vx = math.cos(a) * speed, vy = math.sin(a) * speed,
        }
    end
end

local function movePlayers(dt)
    local h = world.half
    for src = 1, N do
        local p = players[src]
        local x, y = p.x + p.vx * dt, p.y + p.vy * dt
        if x > h or x < -h then p.vx = -p.vx; x = p.x + p.vx * dt end
        if y > h or y < -h then p.vy = -p.vy; y = p.y + p.vy * dt end
        p.x, p.y = x, y
    end
end

for src = 1, N do
    playerList[src] = tostring(src)
    names[src] = 'Player' .. src
end
relayout(MAP_SPREAD)

function GetPlayers() return playerList end
function GetPlayerPed(src) return (tonumber(src) or 0) + 1000 end
-- Returns the live per-player table: the library reads .x .y .z, and a real
-- GetEntityCoords hands back a vector3 that costs the Lua side no allocation.
function GetEntityCoords(ped) return players[ped - 1000] end
function GetPlayerName(src)
    src = tonumber(src)
    return src and names[src] or nil
end
function GetPlayerRoutingBucket() return 0 end
function GetCurrentResourceName() return 'cis_libs' end
function IsDuplicityVersion() return 1 end
sim.invoking = nil
function GetInvokingResource() return sim.invoking end
function GetResourceState() return 'started' end
function GetConvar(_, default) return default end
function DropPlayer() end
function joaat(s)
    if type(s) == 'number' then return s end
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 0x7FFFFFFF end
    return h
end

function TriggerClientEvent(name, _, ...)
    sim.counts[name] = (sim.counts[name] or 0) + 1
    if name == 'cis_libs:client:syncBatch' then
        local _, ups, rems = ...
        sim.entries = sim.entries + (ups and #ups or 0) + (rems and #rems or 0)
    end
end
function TriggerLatentClientEvent(name, target, _, ...)
    TriggerClientEvent(name, target, ...)
end
function TriggerEvent() sim.triggers = sim.triggers + 1 end

function RegisterNetEvent(name, fn)
    if fn then
        sim.netEvents[name] = sim.netEvents[name] or {}
        table.insert(sim.netEvents[name], fn)
    end
end
function AddEventHandler(name, fn)
    sim.handlers[name] = sim.handlers[name] or {}
    table.insert(sim.handlers[name], fn)
end
local function fireLocal(name, src, ...)
    source = src
    for _, fn in ipairs(sim.handlers[name] or {}) do fn(...) end
end

-- exports: a callable registrar (exports('Name', fn)), indexable by resource
-- name for consumers (nil here: no other resource exists in this sim).
local EXPORTS = setmetatable({}, { __call = function(t, name, fn) rawset(t, name, fn) end })
exports = EXPORTS

json = {
    encode = function() return '{}' end,
    decode = function() return nil, 'not stubbed' end,
}
-- CfxLua has os.nanotime; stock Lua does not. CisTiming.measure picks it up when
-- present, so providing it keeps that wrapper's cost honest.
os.nanotime = function() return os.clock() * 1e9 end

-- Counted, never silently absorbed: any native a driven path calls that this
-- file did not stub answers nil and is listed in the report.
setmetatable(_G, {
    __index = function(_, key)
        if type(key) ~= 'string' then return nil end
        for _, prefix in ipairs({
            'Get', 'Is', 'Has', 'Set', 'Add', 'Remove', 'Does', 'Can', 'Create', 'Delete',
            'Register', 'Count', 'Perform', 'Load', 'Execute', 'Stop', 'Start',
        }) do
            if key:sub(1, #prefix) == prefix then
                sim.missing[key] = (sim.missing[key] or 0) + 1
                return function() return nil end
            end
        end
        return nil
    end,
})

print = function() sim.prints = sim.prints + 1 end

-- --------------------------------------------------------- load the library
local function manifestList(block)
    local f = assert(io.open('fxmanifest.lua', 'rb'))
    local text = f:read('a')
    f:close()
    local body = text:match(block .. '%s*(%b{})')
    local out = {}
    for line in body:gmatch('[^\r\n]+') do
        local code = line:gsub('%-%-.*$', '')
        local path = code:match("^%s*'([^']+%.lua)'")
        if path then out[#out + 1] = path end
    end
    return out
end

local SKIPPED = { ['server/selfcheck.lua'] = 'one-shot boot report 20 s after start (resource enumeration natives); no hot path' }
local loaded, skipped = 0, {}
local order = {}
for _, f in ipairs(manifestList('shared_scripts')) do order[#order + 1] = f end
for _, f in ipairs(manifestList('server_scripts')) do order[#order + 1] = f end
for _, path in ipairs(order) do
    if SKIPPED[path] then
        skipped[#skipped + 1] = path .. ' (' .. SKIPPED[path] .. ')'
    else
        local chunk, err = loadfile('./' .. path)
        if not chunk then
            sim.loadErrors[#sim.loadErrors + 1] = path .. ': ' .. tostring(err)
        else
            local ok, e = xpcall(chunk, debug.traceback)
            if ok then
                loaded = loaded + 1
            else
                sim.loadErrors[#sim.loadErrors + 1] = path .. ': ' .. tostring(e)
            end
        end
    end
end

-- Boot: let the ready/version threads run out before anything is measured.
local stepNo = 0
local function advance(ms)
    sim.now = sim.now + ms
    runDueThreads()
end
for _ = 1, 700 do advance(50) end -- 35 s: past the 30 s supplier wait

-- Bench-only wiring: one authorised resource, and the allow-list rebuilt.
Security.AuthorizedResources = { 'cis_bench' }
if CisSecurityRebuild then CisSecurityRebuild() end

-- ------------------------------------------------------------- the driver
local function simulate(seconds, hook)
    local stop = sim.now + seconds * 1000
    while sim.now < stop do
        stepNo = stepNo + 1
        sim.now = sim.now + STEP_MS
        if stepNo % 5 == 0 then movePlayers(0.25) end
        if hook then hook(stepNo) end
        runDueThreads()
    end
end

local function timed(fn)
    real.collectgarbage('collect')
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local function kb()
    real.collectgarbage('collect')
    real.collectgarbage('collect')
    return real.collectgarbage('count')
end

local function resetCounters()
    sim.counts, sim.entries, sim.triggers = {}, 0, 0
end

local function totalEvents()
    local n = 0
    for _, c in pairs(sim.counts) do n = n + c end
    return n
end

-- --------------------------------------------------------------- workloads
local cbPayload = { id = 7, name = 'abc', extra = { 1, 2, 3 } }
local keys = {}
for src = 1, N do keys[src] = 'k' .. src end
local function noop() end

local function cbEvent() return sim.netEvents['cis_libs:cb'][1] end

local CB_SCHEMA = { id = { type = 'integer', min = 1 }, name = { type = 'string', maxLen = 32 } }

local function setupCallbacks()
    sim.invoking = 'cis_bench'
    local ok, why = CisRegisterCallback('bench:echo', function(_, a) return a, 1 end,
        { schema = CB_SCHEMA })
    sim.invoking = nil
    assert(ok, why)
end

local function setupNet()
    sim.invoking = 'cis_bench'
    local ok, why = CisNetOn('bench:net', function() end,
        { schema = CB_SCHEMA, windowMs = 1000, maxHits = 1000 })
    local ok2, why2 = CisNetOn('bench:flood', function() end, { windowMs = 1000, maxHits = 8 })
    sim.invoking = nil
    assert(ok, why)
    assert(ok2, why2)
end

-- 5 callback requests per player per second (every 4th 50 ms step, staggered).
local function cbHook(fire)
    return function(step)
        for src = 1, N do
            if (step + src) % 4 == 0 then
                source = src
                fire('bench:echo', keys[src], cbPayload)
            end
        end
    end
end

-- 10 secure net events per player per second.
local function netHook(fire)
    return function(step)
        for src = 1, N do
            if (step + src) % 2 == 0 then
                source = src
                fire(cbPayload)
            end
        end
    end
end

local RATE_NAMES = { 'ev:a', 'ev:b', 'ev:c', 'ev:d' }
-- 10 rate checks per player per second, rotating four names, never limited.
local function rateHook(check)
    return function(step)
        local nm = RATE_NAMES[step % 4 + 1]
        for src = 1, N do
            if (step + src) % 2 == 0 then
                check(src, nm, 1000, 100000)
            end
        end
    end
end

-- One attacker, 500 events/s into a handler that allows 8 a second.
local function floodHook(fire)
    return function()
        source = 1
        for _ = 1, 25 do fire(cbPayload) end
    end
end

-- Zones: 20 spheres, 20 rotated boxes, 10 polygons.
local zoneIds = {}
local function setupZones(half)
    sim.invoking = nil
    local function rnd(a, b) return a + math.random() * (b - a) end
    local function centre()
        return { x = rnd(-half, half), y = rnd(-half, half), z = rnd(20, 40) }
    end
    local opts = { onEnterEvent = 'bench:enter', onExitEvent = 'bench:exit' }
    for _ = 1, 20 do
        zoneIds[#zoneIds + 1] = assert(CisServerZoneSphere(centre(), rnd(15, 60), opts))
    end
    for _ = 1, 20 do
        local o = { onEnterEvent = 'bench:enter', onExitEvent = 'bench:exit', heading = rnd(0, 359) }
        zoneIds[#zoneIds + 1] = assert(CisServerZoneBox(centre(), { x = rnd(15, 80), y = rnd(15, 80), z = 60 }, o))
    end
    for _ = 1, 10 do
        local c = centre()
        local pts, n = {}, math.random(5, 8)
        for i = 1, n do
            local a, r = (i / n) * 2 * math.pi, rnd(20, 60)
            pts[i] = { x = c.x + math.cos(a) * r, y = c.y + math.sin(a) * r }
        end
        zoneIds[#zoneIds + 1] = assert(CisServerZonePoly(pts,
            { onEnterEvent = 'bench:enter', onExitEvent = 'bench:exit', minZ = 0, maxZ = 80 }))
    end
end
local function teardownZones()
    for i = #zoneIds, 1, -1 do CisServerZoneRemove(zoneIds[i]); zoneIds[i] = nil end
end

-- Sync: 200 client-local props.
local syncIds = {}
local SYNC_RECORDS = 200
local function setupSync(half)
    sim.invoking = 'cis_bench'
    for i = 1, SYNC_RECORDS do
        local id = 'e' .. i
        syncIds[i] = id
        local made, why = EXPORTS.SyncCreate('prop', {
            id = id, model = 'prop_barrier_05a',
            coords = { x = (math.random() * 2 - 1) * half, y = (math.random() * 2 - 1) * half, z = 30.0 },
            heading = 0.0,
        })
        assert(made, why)
    end
    sim.invoking = nil
    -- Deliver the creation pushes and the first streaming passes before timing.
    for _ = 1, 100 do advance(50) end
end
local function teardownSync()
    sim.invoking = 'cis_bench'
    EXPORTS.SyncClear()
    sim.invoking = nil
    syncIds = {}
    for _ = 1, 40 do advance(50) end
end

-- 5 record updates per second: a changed heading is a new revision.
local headingSeq = 0
local function syncUpdateHook()
    return function(step)
        if step % 10 == 0 then
            headingSeq = headingSeq + 1
            local i = (headingSeq % SYNC_RECORDS) + 1
            sim.invoking = 'cis_bench'
            local rec = { id = syncIds[i], model = 'prop_barrier_05a',
                coords = { x = 0.0, y = 0.0, z = 30.0 }, heading = (headingSeq % 359) + 0.5 }
            -- keep the original position: read it back from SyncList is costly, so
            -- the update is created at the hub centre, which is where a hub entity lives.
            EXPORTS.SyncCreate('prop', rec)
            sim.invoking = nil
        end
    end
end

-- Player churn: N/8 drops a minute, handlers run with `source` set.
local function churnHook()
    local drops = math.max(1, N // 8)
    local every = math.max(1, (SIM_SECONDS * 1000 // STEP_MS) // drops)
    return function(step)
        if step % every == 0 then
            fireLocal('playerDropped', (step // every) % N + 1)
        end
    end
end

-- ------------------------------------------------------------------ measure
local rows = {}

local function best(reps, fn)
    local b = math.huge
    for _ = 1, reps do
        local t = fn()
        if t < b then b = t end
    end
    return b
end

-- ph = { name, setup, teardown, live=hook, dry=hook, calls=n per run,
--        baselineAfterSetup=bool, layout=half }
local function measure(ph)
    if ph.layout then relayout(ph.layout) end
    local memBefore = kb()
    local base
    local function runBase()
        return best(REPS, function()
            return timed(function() simulate(SIM_SECONDS, ph.dry) end)
        end)
    end
    if not ph.baselineAfterSetup then base = runBase() end
    if ph.setup then ph.setup() end
    if ph.baselineAfterSetup then base = runBase() end
    -- one untimed pass so first-contact state (sets, buckets) exists
    simulate(5, ph.live)
    local gross
    local counters
    gross = best(REPS, function()
        resetCounters()
        local t = timed(function() simulate(SIM_SECONDS, ph.live) end)
        counters = { events = totalEvents(), entries = sim.entries, triggers = sim.triggers }
        return t
    end)
    local memAfter = kb()
    local net = math.max(0, gross - base)
    rows[#rows + 1] = {
        path = ph.name,
        players = N,
        msPerSec = net * 1000 / SIM_SECONDS,
        grossMs = gross * 1000 / SIM_SECONDS,
        baseMs = base * 1000 / SIM_SECONDS,
        msPerCall = ph.calls and ph.calls > 0 and (net * 1000 / ph.calls) or nil,
        calls = ph.calls,
        evPerSec = counters.events / SIM_SECONDS,
        entriesPerSec = counters.entries / SIM_SECONDS,
        trigPerSec = counters.triggers / SIM_SECONDS,
        memDelta = memAfter - memBefore,
        memAbs = memAfter,
    }
    if ph.teardown then ph.teardown() end
end

-- callbacks ----------------------------------------------------------------
setupCallbacks()
setupNet()
local cbCalls = N * 5 * SIM_SECONDS
measure({
    name = 'callback request (cis_libs:cb)', calls = cbCalls,
    live = cbHook(function(...) cbEvent()(...) end),
    dry = cbHook(noop),
})

-- secure net event ---------------------------------------------------------
local netCalls = N * 10 * SIM_SECONDS
measure({
    name = 'secure net event (CisNetOn)', calls = netCalls,
    live = netHook(function(...) sim.netEvents['bench:net'][1](...) end),
    dry = netHook(noop),
})

-- rate limiter -------------------------------------------------------------
measure({
    name = 'rate check (CisRateOk, allowed)', calls = netCalls,
    live = rateHook(CisRateOk),
    dry = rateHook(noop),
})

-- flood: refused events through the dispatcher
local floodCalls = 500 * SIM_SECONDS
measure({
    name = 'net flood, 1 attacker 500/s (refused)', calls = floodCalls,
    live = floodHook(function(...) sim.netEvents['bench:flood'][1](...) end),
    dry = floodHook(noop),
})

-- zones --------------------------------------------------------------------
for _, layout in ipairs({ { 'spread', MAP_SPREAD }, { 'hub', MAP_HUB } }) do
    measure({
        name = ('zones pass, 50 zones, %s'):format(layout[1]),
        calls = SIM_SECONDS * 2, -- one pass per 500 ms
        layout = layout[2],
        setup = function() setupZones(layout[2]) end,
        teardown = teardownZones,
        live = nil, dry = nil,
    })
end

-- sync stream --------------------------------------------------------------
for _, layout in ipairs({ { 'spread', MAP_SPREAD }, { 'hub', MAP_HUB } }) do
    measure({
        name = ('sync stream pass, 200 records, %s'):format(layout[1]),
        calls = SIM_SECONDS, -- one pass per second
        layout = layout[2],
        setup = function() setupSync(layout[2]) end,
        teardown = teardownSync,
        live = nil, dry = nil,
    })
end

-- sync updates on top of the hub stream: baseline taken with the records live
do
    local half = MAP_HUB
    measure({
        name = 'sync updates 5/s on hub stream (delta over stream)',
        calls = 5 * SIM_SECONDS,
        layout = half,
        baselineAfterSetup = true,
        setup = function()
            setupSync(half)
        end,
        teardown = teardownSync,
        live = syncUpdateHook(), dry = nil,
    })
end

-- everything at once (hub), plus churn --------------------------------------
do
    local cbH, netH, rateH, churn = cbHook(function(...) cbEvent()(...) end),
        netHook(function(...) sim.netEvents['bench:net'][1](...) end),
        rateHook(CisRateOk), churnHook()
    measure({
        name = 'ALL TOGETHER, hub (cb+net+rate+zones+sync+churn)',
        layout = MAP_HUB,
        setup = function() setupZones(MAP_HUB); setupSync(MAP_HUB) end,
        teardown = function() teardownZones(); teardownSync() end,
        live = function(step) cbH(step); netH(step); rateH(step); churn(step) end,
        dry = nil,
        baselineAfterSetup = false,
    })
end

-- ------------------------------------------------------------------ report
print = real.print
real.print(('cis_libs loadsim  players=%d  sim=%ds  reps=%d (best)  step=%dms'):format(N, SIM_SECONDS, REPS, STEP_MS))
real.print('interpreter: ' .. _VERSION .. ' (stock PUC Lua, NOT CfxLua)')
real.print('STUBBED NATIVES, native cost excluded. Numbers are RELATIVE and an UPPER BOUND of the')
real.print('Lua-side cost of the library code only. This is not resmon. CPU = os.clock (1 ms ticks)')
real.print('over the whole 60 sim-second run minus a dry driver-loop baseline.')
real.print(('files loaded: %d; skipped: %s'):format(loaded, #skipped > 0 and table.concat(skipped, '; ') or 'none'))
if #sim.loadErrors > 0 then
    for _, e in ipairs(sim.loadErrors) do real.print('LOAD ERROR ' .. e) end
end
if #sim.errors > 0 then
    real.print(('thread errors: %d, first: %s'):format(#sim.errors, sim.errors[1]))
end
local miss = {}
for k, v in pairs(sim.missing) do miss[#miss + 1] = k .. 'x' .. v end
table.sort(miss)
real.print('unstubbed natives hit (answered nil): ' .. (#miss > 0 and table.concat(miss, ', ') or 'none'))
real.print('')
real.print(('%-52s %4s %10s %10s %10s %9s %9s %10s %10s'):format(
    'path', 'N', 'ms/simsec', 'ms/call', 'cliEv/s', 'entries/s', 'localEv/s', 'memDelta', 'memAbs'))
for _, r in ipairs(rows) do
    real.print(('%-52s %4d %10.3f %10s %10.1f %9.1f %9.1f %10.0f %10.0f'):format(
        r.path, r.players, r.msPerSec,
        r.msPerCall and ('%.5f'):format(r.msPerCall) or '-',
        r.evPerSec, r.entriesPerSec, r.trigPerSec, r.memDelta, r.memAbs))
end
real.print('')
for _, r in ipairs(rows) do
    real.print(('ROW|%s|%d|%.4f|%s|%.2f|%.2f|%.2f|%.0f|gross=%.3f|base=%.3f'):format(
        r.path, r.players, r.msPerSec, r.msPerCall and ('%.6f'):format(r.msPerCall) or '-',
        r.evPerSec, r.entriesPerSec, r.trigPerSec, r.memDelta, r.grossMs, r.baseMs))
end
