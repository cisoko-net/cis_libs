-- Capability registry.

CisRegistry = {}

-- The capability slots, and the contract each one answers to.
CisRegistry.SLOTS = {
    -- Framework slot. Provider supplies the normalised API.
    framework = {
        get = 'CisCoreFramework() -> the normalized API table',
        NormalizedPlayer = 'NormalizedPlayer(src) -> { id, name, job, identifier, money, metadata }. Server only',
        Notify = 'Notify(src, message, kind) -> nil. Server only',
        ShowNotification = 'ShowNotification(message, kind) -> nil. Client only',
        IsLoaded = 'IsLoaded() -> boolean',
        HasPermission = 'HasPermission(src, permission) -> boolean',
        GetPlayerJob = 'GetPlayerJob(src) -> job|nil. Server only',
    },
    -- SQL. Query / Single / Scalar / Insert / Update / Transaction, all yielding and
    -- so a caller waits for the answer; IsReady says whether the driver is up.
    database = {
        query = 'Query(sql, params) -> rows',
        single = 'Single(sql, params) -> row|nil',
        scalar = 'Scalar(sql, params) -> cell',
        insert = 'Insert(sql, params) -> id',
        update = 'Update(sql, params) -> affected',
        transaction = 'Transaction(queries) -> ok, err',
        ready = 'IsReady() -> boolean',
    },
    -- Target slot. create / remove / update / exists / available.
    target = {
        available = 'Available() -> boolean',
        create = 'Create(spec) -> ok, reason',
        remove = 'Remove(name, spec, isPed) -> ok, reason',
        exists = 'Exists(name) -> boolean',
        named = 'name() -> string|nil',
    },
    -- The inventory SERVICE: name -> amount normalisation, framework fallback, and the
    -- hand-off to the adapter behind it (inventoryProvider).
    inventory = {
        count = 'Count(src, item) -> number. On the client: Count(item)',
        add = 'Add(src, item, amount, metadata) -> boolean. Server only',
        remove = 'Remove(src, item, amount) -> boolean. Server only',
        has = 'Has(src, item, amount) -> boolean. On the client: Has(item, amount)',
        snapshot = 'Snapshot(src) -> { [item] = count }',
    },
    -- The third-party inventory ADAPTER behind the service.
    inventoryProvider = {
        name = 'Name() -> string',
        available = 'Available() -> boolean',
        count = 'Count(src, item) -> number|nil',
        add = 'Add(src, item, amount, metadata) -> boolean',
        remove = 'Remove(src, item, amount) -> boolean',
    },
    -- Doors, keys and access. Scoped credentials are a product; the boundary that
    -- product plugs into is this slot.
    doors = {
        state = 'GetDoorState(doorId) -> boolean|nil',
        lock = 'LockDoors(identifier) -> number',
        unlock = 'UnlockDoors(identifier) -> number',
        add = 'AddDoorToSystem(doorData, internal) -> boolean',
        addGroup = 'AddDoorGroup(groupData) -> boolean',
        breakDoor = 'BreakDoor(identifier) -> nil',
        fixDoor = 'FixDoor(identifier) -> nil',
        all = 'GetAllDoorData() -> { doors, groups }',
        -- Whether this install has EVER persisted anything.
        persisted = 'IsPersisted() -> boolean',
    },
    -- The CLIENT half of the same thing, which is a genuinely different problem: the
    -- client adds doors, finds the closest one and asks for a lock state.
    doorsClient = {
        add = 'AddDoorToSystem(data) -> boolean',
        addGroup = 'AddDoorGroup(data) -> boolean',
        closest = 'GetClosestDoor() -> { id, distance, door }|nil',
        state = 'GetDoorState(doorId) -> boolean|nil',
        -- The client asks for a lock state through this slot, not a raw event.
        RequestState = 'RequestState(identifier, lock) -> any',
    },
    -- Discord webhooks and any other outbound sink.
    discord = {
        log = 'Log(webhookUrl, title, message, color, ping) -> nil',
        depth = 'QueueDepth() -> number',
    },
    -- The function that actually drops a cheating player.
    security = {
        drop = 'Drop(src, reason) -> nil',
    },
    -- Whether this server has ever stored anything, used to decide install posture.
    dataProbe = {
        hasRows = 'HasRows() -> boolean|nil',
    },
    -- cis_migrate. A single dispatcher taking the action as its first argument.
    migration = {
        plan = 'plan(sourceName, options) -> report|nil, err',
        apply = "apply(sourceName, { confirm = 'APPLY' }) -> result|nil, err",
        sources = 'sources() -> { name }',
    },
    -- cis_libs ships no NUI.
    ui = {
        Notify = 'Notify(message, kind) -> boolean, string. Client only',
        TextUIShow = 'TextUIShow(text, opts) -> boolean, string. Client only',
        TextUIHide = 'TextUIHide() -> boolean, string. Client only',
        TextUIIsOpen = 'TextUIIsOpen() -> boolean. Client only',
        Progress = 'Progress(opts) -> boolean, string. Client only',
        Confirm = 'Confirm(opts) -> any, string. Client only',
        Input = 'Input(opts) -> any, string. Client only',
    },
    -- Cell signal and jammers (cis_signal). A host binds it softly and fails soft:
    -- no signal provider means every device keeps full service.
    signal = {
        api = 'api() -> 1, minor. Server only',
        read = "read(ref, band) -> { bars = 0..4, quality = 'crisp'|'degraded'|'static'|'lost', jammed = boolean, gen?, voice?, sms?, dataKbps?, latencyMs?, dbm?, aps? } | false, reason ('bad_ref'|'bad_band'|'not_ready'|'disabled'). Bands: cellular, data, rf, gps, video, wifi. Server only",
        jammed = "jammed(ref, band) -> true, kind | false | false, nil, reason ('bad_ref'|'bad_band'|'not_ready'). Server only",
        addJammer = "addJammer(id, { coords, radius, bands, strength, bucket?, ttlMs? }) -> true | false, reason ('bad_id'|'bad_spec'|'not_allowed'|'limit'). Server only, allow-listed. Optional since minor 0",
        removeJammer = "removeJammer(id) -> true | false, reason ('bad_id'|'not_owner'|'unknown_jammer'). Server only, owner only. Optional since minor 0",
        summary = "summary() -> true, { towers = { [id] = state }, jammers = count } | false, 'not_ready'. Server only. Optional since minor 0",
        addAccessPoint = "addAccessPoint(id, { coords, bucket, ssid, gen, kind, outside?, glass?, planKbps?, lan? }) -> true | false, reason ('disabled'|'bad_id'|'bad_spec'|'not_allowed'|'limit'). Server only, allow-listed. Optional since minor 0",
        removeAccessPoint = "removeAccessPoint(id) -> true | false, reason ('disabled'|'bad_id'|'not_owner'|'unknown_ap'). Server only, owner only. Optional since minor 0",
        address = "address(src, apId?) -> true, { cell, wifi? } | false, reason ('disabled'|'bad_ref'|'unknown_ap'|'pool_full'). Server only. Optional since minor 0",
    },
    -- The power grid (cis_electricity). Same soft binding: no power provider means
    -- everything is powered.
    power = {
        api = 'api() -> 1, minor. Server only',
        isPowered = 'isPowered(ref) -> true, reason | false, reason. Server only',
        addConsumer = "addConsumer(id, { coords, profile, bucket?, payer?, shell?, priority? }) -> true, circuitId | false, reason ('bad_id'|'bad_spec'|'not_owner'|'not_allowed'|'limit'). Server only, allow-listed",
        removeConsumer = "removeConsumer(id) -> true | false, reason ('bad_id'|'not_owner'|'unknown_consumer'). Server only, owner only",
        addConsumers = "addConsumers(list) -> true, accepted, rejected | false, reason ('bad_spec'|'not_allowed'|'limit'). Server only, allow-listed. Optional since minor 0",
        occupy = "occupy(src, consumerId|nil) -> true | false, reason ('bad_player'|'unknown_consumer'|'not_owner'|'wrong_bucket'|'too_far'). Server only, caller must own the consumer. Optional since minor 0",
        requestOutage = "requestOutage(ref, reason, ms) -> true | false, reason ('bad_ref'|'bad_spec'|'bad_ms'|'not_allowed'|'limit'). Server only, allow-listed. Optional since minor 0",
        restore = "restore(ref) -> true | false, reason ('bad_ref'|'not_allowed'). Server only, allow-listed, ends only the caller's own outages. Optional since minor 0",
        districtAt = "districtAt(coords) -> true, districtId | false, reason ('bad_spec'|'outside_grid'). Server only. Optional since minor 0",
        summary = 'summary() -> true, { city = reason, districts = { [id] = reason } }. Server only. Optional since minor 0',
        nearestAsset = "nearestAsset(coords, maxDist) -> true, { id, kind, state } | false, reason ('bad_spec'|'none'). Server only, maxDist clamped to 50. Optional since minor 0",
    },
}

-- SLOTS THAT MOVED OUT (docs/V1.md section 3). Third-party behaviour is
-- cis_bridge's job and framework concerns are cis_core's, so these slots, and the
-- DetectFramework / DetectDatabase exports, are deprecated in 1.0.0 and removed in
-- 2.0.0. Until then each one still works, and the first use from each resource
-- logs one line naming what to call instead.
CisRegistry.DEPRECATED_SINCE = '1.0.0'
CisRegistry.DEPRECATED_UNTIL = '2.0.0'
CisRegistry.DEPRECATED = {
    framework = 'the cis_bridge player API',
    inventory = 'the cis_bridge inventory API',
    inventoryProvider = 'the cis_bridge inventory API',
    target = 'the cis_bridge target API',
    doors = 'the cis_bridge doors API',
    doorsClient = 'the cis_bridge doors API',
    database = 'the oxmysql API, served by oxmysql or cis_database',
    dataProbe = 'cis_core',
    migration = 'cis_core',
    DetectFramework = 'the cis_bridge detection',
    DetectDatabase = 'the cis_bridge detection',
    -- Exports that warn under their own name: they never reach a slot, or reach
    -- one only when a provider is registered.
    GetKnownTargets = 'the cis_bridge detection',
    RequestInventorySync = 'the cis_bridge inventory API',
    RequestLockDoors = 'the cis_bridge doors API',
    RequestUnlockDoors = 'the cis_bridge doors API',
}

-- Methods a kept export forwards through a deprecated slot.
local NOTICE_EXEMPT = { ['framework.Notify'] = true, ['framework.ShowNotification'] = true }

-- caller -> { [name] = true }: who has been told, so each resource hears it once.
local deprecationSeen = {}

--- The one-time notice for a deprecated slot or export used by `caller`.
--- @param name string    a slot name or export name
--- @param caller string  the resource using it
--- @return string|nil    the line to log, or nil when not deprecated or already told
function CisRegistry.deprecationNotice(name, caller)
    local use = CisRegistry.DEPRECATED[name]
    if not use or type(caller) ~= 'string' then
        return nil
    end
    local seen = deprecationSeen[caller]
    if not seen then
        seen = {}
        deprecationSeen[caller] = seen
    end
    if seen[name] then
        return nil
    end
    seen[name] = true
    return ('cis_libs: %s uses %q, deprecated since %s and removed in %s. Use %s instead.')
        :format(caller, name, CisRegistry.DEPRECATED_SINCE, CisRegistry.DEPRECATED_UNTIL, use)
end

--- Forget what a resource was told, when it stops.
function CisRegistry.forgetDeprecationCaller(caller)
    deprecationSeen[caller] = nil
end

-- Log the notice through whichever logger this realm has loaded.
function CisRegistry.warnDeprecated(name, caller)
    local line = CisRegistry.deprecationNotice(name, caller)
    if not line then
        return
    end
    if type(Logging) == 'table' and Logging.Warn then
        Logging.Warn(line)
    else
        print(line)
    end
end

-- The provider-side function name a slot method answers to: the leading identifier of
-- its spec string.
local function declaredName(slot, method)
    local spec = CisRegistry.SLOTS[slot] and CisRegistry.SLOTS[slot][method]
    return type(spec) == 'string' and spec:match('^([%a_][%w_]*)') or nil
end

-- WHO CALLED, as the server itself reports it.
local function invokingResource()
    if type(GetInvokingResource) ~= 'function' then
        return nil
    end
    local ok, name = pcall(GetInvokingResource)
    if not ok then
        return nil
    end
    return type(name) == 'string' and name ~= '' and name or nil
end

-- This resource's own name: its internal calls are not a consumer's use.
local function selfName()
    if type(GetCurrentResourceName) ~= 'function' then
        return 'cis_libs'
    end
    local ok, name = pcall(GetCurrentResourceName)
    return ok and name or 'cis_libs'
end

-- The realm a declared method is limited to, read off its contract string.
local function declaredRealm(spec)
    if spec:find('Server only', 1, true) then return 'server' end
    if spec:find('Client only', 1, true) then return 'client' end
    return nil
end

local function currentRealm()
    if type(IsDuplicityVersion) ~= 'function' then
        return nil
    end
    return IsDuplicityVersion() and 'server' or 'client'
end

-- slot -> { owner = resourceName, ref = 'resource:Export' or callable, at = time }
local slots = {}

-- A callable that arrived as a return value across the boundary reports type() ==
-- 'table'. CisCallable (shared/owned.lua) answers for both; it is looked up at
-- CALL time, so this file loading before owned.lua does not matter.
local function isCallable(v)
    return CisCallable(v)
end

-- How long a provider that answered the no-method probe with NIL is taken at its
-- word before being asked again. See the nil branch in CisRegistry.call.
local NIL_PROBE_MS = 5000

--- Check a provider's DECLARED CONTRACT, if it declared one.
--- @param slot string      one of CisRegistry.SLOTS
--- @param contract table|nil `{ api = number, requiredMethods = { string } }`
--- @return boolean ok, string reason
local function sortedMethodNames(slot)
    local names = {}
    local declared = CisRegistry.SLOTS[slot] or {}
    for method in pairs(declared) do
        names[#names + 1] = method
    end
    table.sort(names)
    return names
end

local function checkContract(slot, contract)
    if contract == nil then
        return true
    end
    -- A STRING is accepted and ignored, so a caller that passes a version string still
    -- registers.
    if type(contract) == 'string' then
        return true
    end
    if type(contract) ~= 'table' then
        return false, ('contract must be a table, got %s'):format(type(contract))
    end
    if contract.api ~= nil and type(contract.api) ~= 'number' then
        return false, ('contract.api must be a number, got %s'):format(type(contract.api))
    end
    if contract.requiredMethods ~= nil and type(contract.requiredMethods) ~= 'table' then
        return false, ('contract.requiredMethods must be a table, got %s')
            :format(type(contract.requiredMethods))
    end

    local declared = CisRegistry.SLOTS[slot] or {}
    if contract.requiredMethods then
        for _, method in ipairs(contract.requiredMethods) do
            if type(method) ~= 'string' then
                return false, ('contract.requiredMethods entries must be strings, got %s')
                    :format(type(method))
            end
            -- A method the SLOT does not declare cannot be called on this slot, so
            -- a contract that requires it is refused.
            if not declared[method] and not declaredName(slot, method) then
                return false, ('capability %q has no method %q; declared methods are %s')
                    :format(slot, method, table.concat(sortedMethodNames(slot), ', '))
            end
        end
    end
    return true
end

--- The contract a slot's provider declared, for diagnostics and the boot report.
function CisRegistry.contract(slot)
    local held = slots[slot]
    return held and held.contract or nil
end

-- TICK_MS is the wait step of the waiter further down (CisRegistry.wait); nowMs is
-- milliseconds from GetGameTimer, or from os.clock in the test drivers.
local TICK_MS = 50

local function nowMs()
    if GetGameTimer then
        return GetGameTimer()
    end
    return math.floor(os.clock() * 1000)
end

-- One place that turns a slot change into an event: register, unregister and the
-- release when a resource stops all announce through it, so a listener sees one event
-- shape.
function CisRegistry.announce(slot, action, previousOwner, owner)
    if not TriggerEvent then
        return
    end
    TriggerEvent('cis_libs:capabilityChanged', {
        slot = slot,
        action = action,
        owner = owner,
        previousOwner = previousOwner,
        resolved = slots[slot] ~= nil,
    })
end

--- Register a provider for a slot.
--- @param slot string     one of CisRegistry.SLOTS
--- @param provider string|function|table  A "resource:Export" string, or a callable (a
---   function, or the function reference another resource's export arrives as), or a
---   table with a `resource` field and an `export` name.
--- @param contract table|nil `{ api = number, requiredMethods = { string } }`
--- @param asOwner string|nil  for cis_libs' own code only: the client capability gate
---   files a registration it held back, after the caller's export call has returned.
--- @return boolean ok, string reason
function CisRegistry.register(slot, provider, contract, asOwner)
    if type(slot) ~= 'string' or not CisRegistry.SLOTS[slot] then
        return false, ('unknown capability slot %q'):format(tostring(slot))
    end
    -- The declared contract, checked BEFORE anything is mutated.
    local contractOk, contractReason = checkContract(slot, contract)
    if not contractOk then
        return false, contractReason
    end
    if type(provider) == 'string' then
        local resource, exportName = provider:match('^([^:]+):(.+)$')
        if not resource or not exportName then
            return false, ('provider must be "resource:Export", got %q'):format(provider)
        end
        provider = { resource = resource, export = exportName }
    end
    if not isCallable(provider) and type(provider) ~= 'table' then
        return false, 'provider must be a "resource:Export" string or a callable'
    end
    if type(provider) == 'table' and not provider.resource then
        return false, 'provider table needs a resource field'
    end

    -- A bare callable is cis_libs registering its own capability, so it is owned by
    -- cis_libs.
    local owner = asOwner or invokingResource()
        or (type(provider) == 'table' and provider.resource)
        or 'cis_libs'
    local held = slots[slot]
    if held and held.owner ~= owner then
        return false, ('capability %q is already registered by %s'):format(slot, held.owner)
    end
    local wasResolved = held ~= nil
    -- A re-registration by the OWNER (the onResourceStart-after-restart case) that
    -- passes no contract keeps the one already recorded.
    local recorded = contract or (held and held.contract) or nil
    slots[slot] = { owner = owner, ref = provider, contract = recorded }
    if owner ~= selfName() then
        CisRegistry.warnDeprecated(slot, owner)
    end
    -- Announced HERE, at the one place a slot changes hands, rather than by each
    -- caller, so no path can change a slot without an event.
    CisRegistry.announce(slot, 'registered', wasResolved and held.owner or nil, owner)
    return true
end

--- Wait for a slot to be filled, so start order stops mattering.
--- @param slot string  a slot name from CisRegistry.SLOTS
--- @param timeoutMs number|nil  default 30000; 0 polls once and answers now
--- @return boolean  true when the slot resolved within the timeout
--- @return string|nil,string  the owner when it resolved, or a reason when it did not
function CisRegistry.wait(slot, timeoutMs)
    if type(slot) ~= 'string' or not CisRegistry.SLOTS[slot] then
        return false, ('unknown capability slot %q'):format(tostring(slot))
    end
    local timeout = timeoutMs == nil and 30000 or tonumber(timeoutMs) or 30000
    -- NaN never compares >= a deadline, so it waited forever: it takes the default.
    if timeout ~= timeout then
        timeout = 30000
    end
    local deadline = nowMs() + timeout
    -- TICK_MS is a local constant rather than a literal so the waiter's cost is one
    -- Wait per tick, and the interval is set in one place.
    while not CisRegistry.has(slot) do
        if nowMs() >= deadline then
            -- %s, not %d: a fractional timeout raised "no integer representation".
            return false, ('capability %q was not provided within %sms: %s'):format(
                slot, tostring(timeout), CisRegistry.missing(slot))
        end
        Wait(TICK_MS)
    end
    return true, CisRegistry.owner(slot)
end

--- Release a slot. Only the owner may release it, or cis_libs itself at shutdown.
function CisRegistry.unregister(slot, resource)
    local held = slots[slot]
    if not held then
        return false
    end
    if resource and held.owner ~= resource then
        return false
    end
    slots[slot] = nil
    -- A release is announced too, and it is announced with the owner that held the
    -- slot, so a listener can tell who let go.
    CisRegistry.announce(slot, 'unregistered', held.owner, nil)
    return true
end

--- The callable for a slot, or nil.
function CisRegistry.resolve(slot)
    local held = slots[slot]
    if not held then
        return nil
    end
    if held.resolved ~= nil then
        return held.resolved
    end
    local ref = held.ref
    if type(ref) == 'table' and ref.resource and not isCallable(ref) then
        -- READING THE EXPORT IS GUARDED, BOTH STEPS, because `exports[res][name]`
        local okTarget, target = pcall(function()
            return exports[ref.resource]
        end)
        local fn
        if okTarget and target then
            local okFn, value = pcall(function()
                return target[ref.export]
            end)
            if okFn then
                fn = value
            end
        end
        -- MEASURED, not inferred: `exports[res][name]` is an UNBOUND method and
        -- is called with its table as the first argument.
        held.resolved = isCallable(fn) and function(...)
            return fn(target, ...)
        end or nil
        if held.resolved then
            -- Record that this provider came across the boundary, so `call` knows to
            -- look methods up on the table it hands back.
            held.crossBoundary = true
        end
        return held.resolved
    end
    held.resolved = ref
    return ref
end

--- Forget the cached resolution.
function CisRegistry.invalidate(slot)
    local held = slots[slot]
    if held then
        held.resolved = nil
        -- The method table belongs to the provider that handed it back.
        held.methods = nil
        held.lookups = nil
        held.nilProbeAt = nil
    end
end

--- Release every slot a resource owns.
function CisRegistry.releaseOwner(resource)
    local released = {}
    for slot, held in pairs(slots) do
        local ref = held.ref
        local hostsIt = type(ref) == 'table' and ref.resource == resource
        if held.owner == resource or hostsIt then
            slots[slot] = nil
            released[#released + 1] = slot
            -- Announced per slot, inside the loop, because a consumer is waiting on
            -- that slot.
            CisRegistry.announce(slot, 'unregistered', held.owner, nil)
        end
    end
    table.sort(released)
    return released
end

--- Is anything registered for this slot?
function CisRegistry.has(slot)
    return slots[slot] ~= nil
end

--- Who owns this slot?
function CisRegistry.owner(slot)
    local held = slots[slot]
    return held and held.owner or nil
end

--- The provider's METHOD TABLE for a slot: fetched, and cached like a resolution, until
--- the slot is invalidated or released.
--- @return table|nil  the method table, or nil when the slot is empty or the provider
---   has none (a dispatcher function, or a provider whose export raised)
function CisRegistry.methods(slot)
    local held = slots[slot]
    if not held then
        return nil
    end
    local cached = held.methods
    if cached ~= nil then
        return cached or nil
    end
    local provider = CisRegistry.resolve(slot)
    if not provider then
        return nil
    end
    local ok, value = pcall(provider)
    if not ok then
        return nil
    end
    if isCallable(value) then
        -- A dispatcher has no method table to hand out.
        held.methods = false
        return nil
    end
    if type(value) ~= 'table' then
        return nil
    end
    held.methods = value
    return value
end

-- Finds the function behind a declared method name. `CisRegistry.SLOTS` is a table of
-- method names per slot, and a provider table may spell one as declared, as written by
-- the caller, or with the first letter's case flipped; the spelling that matches is
-- cached per method.
function CisRegistry.lookup(held, slot, methods, method)
    local cache = held.lookups
    if not cache then
        cache = {}
        held.lookups = cache
    end
    local key = cache[method]
    if key == nil then
        key = false
        if type(method) == 'string' then
            local declared = declaredName(slot, method)
            local flipped = method:sub(1, 1):upper() == method:sub(1, 1)
                and method:sub(1, 1):lower() .. method:sub(2)
                or method:sub(1, 1):upper() .. method:sub(2)
            for _, candidate in ipairs({ method, declared, flipped }) do
                if candidate and isCallable(methods[candidate]) then
                    key = candidate
                    break
                end
            end
        end
        cache[method] = key
    end
    return key and methods[key] or nil
end

--- The declared methods of a slot that the cached provider table cannot serve in this
--- realm.
function CisRegistry.missing(slot)
    local held = slots[slot]
    local methods = held and held.methods
    local declared = CisRegistry.SLOTS[slot]
    if type(methods) ~= 'table' or not declared then
        return nil
    end
    local realm = currentRealm()
    local out = {}
    for method, spec in pairs(declared) do
        local limited = declaredRealm(spec)
        -- An Optional method arrived in a later api minor: a provider of an older
        -- minor lacks it and is not out of date.
        if (not limited or not realm or limited == realm)
            and not spec:find('Optional', 1, true)
            and not CisRegistry.lookup(held, slot, methods, method) then
            out[#out + 1] = method
        end
    end
    table.sort(out)
    return out
end

--- Call a capability. Returns true plus the provider's results, or false plus a reason.
function CisRegistry.call(slot, ...)
    -- A method name is REQUIRED, and its absence is a refusal rather than an exception.
    if select('#', ...) < 1 or type((...)) ~= 'string' then
        return false, 'method name required'
    end
    -- A deprecated slot used by another resource (not cis_libs' own code) says so once.
    -- Notify stays a cis_libs export, so routing it through `framework` is not the
    -- caller's use of a deprecated slot.
    if CisRegistry.DEPRECATED[slot] and not NOTICE_EXEMPT[slot .. '.' .. (...)] then
        local caller = invokingResource()
        if caller and caller ~= selfName() then
            CisRegistry.warnDeprecated(slot, caller)
        end
    end
    local held = slots[slot]
    local provider = held and held.resolved or CisRegistry.resolve(slot)
    if not provider then
        return false, ('no provider registered for %q'):format(tostring(slot))
    end
    local method = ...

    if held and held.crossBoundary then
        local methods = held.methods
        if methods == nil and held.nilProbeAt and nowMs() - held.nilProbeAt < NIL_PROBE_MS
            and nowMs() >= held.nilProbeAt then
            -- Probed recently and it answered nil: dispatch without asking again.
            methods = false
        end
        if methods == nil then
            -- First call for this provider: take the table it hands back.
            local ok, value = pcall(provider)
            if not ok then
                return false, tostring(value)
            end
            if isCallable(value) then
                -- The export answered with a FUNCTION rather than a method table, so it
                -- is a dispatcher and is called with the method name first.
                methods = false
                held.methods = false
            elseif type(value) == 'table' then
                -- The method table. Every table lands here.
                methods = value
                held.methods = value
            else
                -- NIL. AMBIGUOUS, AND NOT CACHED FOR GOOD: a dispatcher asked for no
                -- action answers nil, and so does a method-table provider that has
                -- not finished booting. But it is not re-asked on EVERY call either
                -- -- that invoked the provider's export twice per call, forever, for
                -- every dispatcher. Taken at its word for NIL_PROBE_MS, then asked
                -- again, so a late table is still found.
                methods = false
                held.nilProbeAt = nowMs()
            end
        end
        if methods then
            local fn = CisRegistry.lookup(held, slot, methods, method)
            if not isCallable(fn) then
                return false, ('provider for %q has no method %q'):format(
                    tostring(slot), tostring(method))
            end
            local results = table.pack(pcall(fn, select(2, ...)))
            if not results[1] then
                return false, tostring(results[2])
            end
            return true, table.unpack(results, 2, results.n)
        end
    end

    local results = table.pack(pcall(provider, ...))
    if not results[1] then
        return false, tostring(results[2])
    end
    return true, table.unpack(results, 2, results.n)
end

--- Call a capability and return only its first result, for the very common case where
--- the success flag is not needed and a failure reads as nil.
function CisRegistry.value(slot, ...)
    local ok, a = CisRegistry.call(slot, ...)
    if not ok then
        return nil
    end
    return a
end

--- Every slot, resolved or not, for the debug command.
function CisRegistry.snapshot()
    local out = {}
    for slot in pairs(CisRegistry.SLOTS) do
        local contract = slots[slot] and slots[slot].contract
        out[slot] = {
            owner = slots[slot] and slots[slot].owner or nil,
            resolved = CisRegistry.resolve(slot) ~= nil,
            missing = CisRegistry.missing(slot),
            -- The api the provider declared at registration, nil when it declared none.
            api = type(contract) == 'table' and contract.api or nil,
        }
    end
    return out
end

--- Count of registered slots. Cheap enough for the boot report.
function CisRegistry.registered()
    local n = 0
    for _ in pairs(slots) do
        n = n + 1
    end
    return n
end
