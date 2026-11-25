-- Optional update notice. Nothing here runs on a default install: see the comment on
-- versionCheckUrl below for why.

-- The remote document is plain text, not JSON: first line is the version, everything
-- after it is the changelog. A text file needs no build step and no content-type
-- handling on the host.
--
-- The changelog lines are collected and joined ONCE: growing a string per line
-- copied everything so far each time, quadratic in the length of the body.
--
-- The version line is remote text that reaches the console too, so it loses its
-- control characters and is cut to MAX_VERSION_LINE before anything prints it.
local MAX_VERSION_LINE = 64

local function parseVersionInfo(remoteVersion)
    local versionInfo = {}
    local lines, n = {}, 0
    for line in remoteVersion:gmatch('[^\r\n]+') do
        if not versionInfo.latestVersion then
            local clean = line:gsub('%c', ''):match('^%s*(.-)%s*$')
            versionInfo.latestVersion = clean:sub(1, MAX_VERSION_LINE)
        else
            n = n + 1
            lines[n] = line
        end
    end
    if n > 0 then
        versionInfo.changelog = table.concat(lines, '\n', 1, n) .. '\n'
    end
    return versionInfo
end

-- SEMVER ORDER, not string equality. Equality called every build that was not
-- byte-identical to the published line "outdated" -- a development build AHEAD of
-- it, a "v1.2.0", a trailing build tag. MAJOR.MINOR.PATCH compare as numbers
-- (so 1.10.0 is after 1.9.0), a pre-release sorts before its release
-- (1.2.0-beta < 1.2.0), and build metadata (+sha) is ignored. The WHOLE string
-- must be a version: trailing text is not one, and is not compared.
local function parseSemver(v)
    if type(v) ~= 'string' then
        return nil
    end
    local core, rest = v:match('^%s*[vV]?(%d+%.?%d*%.?%d*)(.-)%s*$')
    if not core then
        return nil
    end
    local pre, build = rest:match('^%-([%w%.%-]+)(.*)$')
    if not pre then
        build = rest
    end
    if build ~= '' and not build:match('^%+[%w%.%-]+$') then
        return nil
    end
    local parts = {}
    for piece in core:gmatch('%d+') do
        parts[#parts + 1] = tonumber(piece)
    end
    return { parts[1] or 0, parts[2] or 0, parts[3] or 0, pre = pre }
end

-- Pre-release order is per dot-separated identifier: numeric ones as numbers
-- (rc.9 < rc.10), a numeric one before an alphanumeric one, others as text, and
-- a shorter list first when every field before its end matches.
local function comparePre(a, b)
    local x, y = {}, {}
    for id in a:gmatch('[^%.]+') do x[#x + 1] = id end
    for id in b:gmatch('[^%.]+') do y[#y + 1] = id end
    for i = 1, math.min(#x, #y) do
        local p, q = x[i], y[i]
        if p ~= q then
            local pn, qn = p:match('^%d+$'), q:match('^%d+$')
            if pn and qn then
                -- By length first: identifiers longer than a double holds still order.
                if #p ~= #q then
                    return #p < #q and -1 or 1
                end
                return p < q and -1 or 1
            elseif pn then
                return -1
            elseif qn then
                return 1
            end
            return p < q and -1 or 1
        end
    end
    if #x == #y then
        return 0
    end
    return #x < #y and -1 or 1
end

--- -1 when a is older than b, 0 when equal, 1 when newer; nil when either is not a version.
local function compareVersions(a, b)
    local x, y = parseSemver(a), parseSemver(b)
    if not x or not y then
        return nil
    end
    for i = 1, 3 do
        if x[i] ~= y[i] then
            return x[i] < y[i] and -1 or 1
        end
    end
    if x.pre == y.pre then
        return 0
    end
    if not x.pre then
        return 1
    end
    if not y.pre then
        return -1
    end
    return comparePre(x.pre, y.pre)
end

-- The changelog is remote text printed to the console; a long body would flood it.
local MAX_CHANGELOG = 512

-- NOTE on the callback's first parameter: it is the HTTP STATUS CODE, not an error,
-- so 200 is the success case.
local function checkVersion(url, currentVersion)
    PerformHttpRequest(url, function(err, remoteVersion)
        if err == 200 and remoteVersion then
            local versionInfo = parseVersionInfo(remoteVersion)
            local order = compareVersions(currentVersion, versionInfo.latestVersion)
            if order == nil then
                Logging.Warn(('Version check could not compare %s with the published %s; continuing startup.')
                    :format(tostring(currentVersion), tostring(versionInfo.latestVersion)))
            elseif order >= 0 then
                Logging.Info('Resource is up to date. Version: ' .. tostring(currentVersion) .. '.', 'master')
            else
                Logging.Warn(('Resource is outdated. Current: %s Latest: %s\n%s'):format(
                    tostring(currentVersion),
                    tostring(versionInfo.latestVersion),
                    (versionInfo.changelog or ''):sub(1, MAX_CHANGELOG)
                ), 'master')
            end
        else
            Logging.Warn('Version check failed; continuing startup.')
        end
    end, 'GET')
end

-- The endpoint comes from config, and only over HTTPS: on plain http anyone on
-- the path could rewrite the notice an operator reads.
local function versionCheckUrl()
    local url = Config and Config.VersionCheckUrl
    if type(url) ~= 'string' or not url:find('^https://') then
        return nil
    end
    return url
end

-- `set cis_check_version true|false` decides when it is set; otherwise
-- Config.CheckVersion does. Read when the check RUNS, never at load.
local function convarSwitch()
    if type(GetConvar) ~= 'function' then
        return nil
    end
    local ok, raw = pcall(GetConvar, 'cis_check_version', '')
    if not ok or type(raw) ~= 'string' then
        return nil
    end
    raw = raw:match('^%s*(.-)%s*$'):lower()
    if raw == '' then
        return nil
    end
    return raw == 'true' or raw == '1' or raw == 'yes' or raw == 'on'
end

local function checkEnabled()
    local pinned = convarSwitch()
    if pinned ~= nil then
        return pinned
    end
    return Config and Config.CheckVersion == true
end

-- How long boot waits for a configuration supplier before deciding. cis_libs
-- starts FIRST -- that is what `dependency 'cis_libs'` means -- so a thread that
-- read Config.CheckVersion on its first tick read the built-in default, false,
-- every time, and an operator who turned the check on in cis_core never got it.
local SUPPLIER_WAIT_MS = 30000
local SUPPLIER_POLL_MS = 500

-- Once per boot, and only if the operator turned it on.
CreateThread(function()
    local waited = 0
    while convarSwitch() == nil and Config and Config.__owner == 'cis_libs'
        and waited < SUPPLIER_WAIT_MS do
        Wait(SUPPLIER_POLL_MS)
        waited = waited + SUPPLIER_POLL_MS
    end
    if checkEnabled() then
        local url = versionCheckUrl()
        if not url then
            Logging.Warn('Config.CheckVersion is on but Config.VersionCheckUrl is not an https:// URL; skipping version check.')
            return
        end
        -- Read from fxmanifest, not from a constant in this file, so the value an
        -- operator sees in the manifest is the value that is compared.
        local currentVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
        checkVersion(url, currentVersion)
    end
end)
