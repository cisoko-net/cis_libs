-- Server-side mirror of who is online and what job they hold.

local store = CisHistogram.new()

function CisJobCount(jobs)
    return CisHistogram.count(store, jobs)
end

-- Accepts a job table OR a bare job name, because the framework events are not
-- all the same shape: some send a table, some send only the name.
-- ONLY A CONNECTED PLAYER IS REMEMBERED. Only playerDropped removes an entry, so
-- an id nobody holds would be counted -- as an on-duty officer, say -- until the
-- server restarts.
function CisRememberJob(src, job)
    if type(src) ~= 'number' or src <= 0 or not GetPlayerName(src) then
        return false
    end
    CisHistogram.set(store, src, job)
    return true
end

function CisForgetPlayer(src)
    CisHistogram.remove(store, src)
end

exports('GetOnlineJobCount', CisJobCount)

-- A RESTART OF cis_libs EMPTIES THE HISTOGRAM. It lives in memory, and a
-- publisher sends a job only when it changes, so every player already online
-- counted in no job until they changed it. When a framework provider registers,
-- as it does again after the restart, it is asked for the job of each connected
-- player the histogram has no job for. A job a publisher sent first is newer
-- and stays.
local function rebuildFromFramework()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and store.players[src] == nil then
            local called, ok, job = pcall(CisRegistry.call, 'framework', 'GetPlayerJob', src)
            local name = type(job) == 'table' and job.name or job
            if called and ok and type(name) == 'string' and store.players[src] == nil then
                CisRememberJob(src, job)
            end
        end
    end
end

-- Each call into the provider can yield, so the walk runs on its own thread.
AddEventHandler('cis_libs:capabilityChanged', function(change)
    if type(change) == 'table' and change.slot == 'framework' and change.action == 'registered' then
        CreateThread(rebuildFromFramework)
    end
end)

-- Not tidy: without it the store grows by one entry per connection for the life of the
-- server.
AddEventHandler('playerDropped', function()
    CisForgetPlayer(source)
end)
