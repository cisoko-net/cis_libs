-- cis_libs' streaming exports: the engine in client/core/streaming.lua. A
-- consumer's `Cis.streaming.*` runs the same text in its own VM.

local Streaming = CisCore.streaming
local requestAsset = Streaming.request

function RequestModelTimeout(model, timeout)
    return Streaming.model(model, timeout)
end

-- Exported under its own name rather than through the kind registrations below: it
-- answers in the model shape (loaded, hash, reason).
exports('RequestModelTimeout', RequestModelTimeout)

-- SEVEN LITERAL REGISTRATIONS, one per kind, written out so each export name can be found.
exports('AnimDict', function(name, timeout) return requestAsset('animDict', name, timeout) end)
exports('AnimSet', function(name, timeout) return requestAsset('animSet', name, timeout) end)
exports('Ptfx', function(name, timeout) return requestAsset('ptfx', name, timeout) end)
exports('TextureDict', function(name, timeout) return requestAsset('textureDict', name, timeout) end)
exports('WeaponAsset', function(name, timeout) return requestAsset('weaponAsset', name, timeout) end)
exports('Scaleform', function(name, timeout) return requestAsset('scaleform', name, timeout) end)
exports('AudioBank', function(name, timeout) return requestAsset('audioBank', name, timeout) end)

CisDiagnostics.Register('client', 'streaming', function()
    -- Counts and queries, which are the only two things that can be asked about the
    -- streaming queue.
    return {
        pending = GetNumberOfStreamingRequests(),
        -- HAVE_ALL_STREAMING_REQUESTS_COMPLETED takes the ped whose requests count.
        -- A BOOL native answers 1 or false in Lua; the report carries a boolean.
        allComplete = HaveAllStreamingRequestsCompleted(PlayerPedId()) and true or false,
    }
end)
