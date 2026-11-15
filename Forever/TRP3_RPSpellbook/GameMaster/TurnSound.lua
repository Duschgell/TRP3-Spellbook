local _, addon = ...

addon.GameMasterTurnSound = {}

local cooldown = 5
local lastTurnAt, lastAlertAt, lastPreviewAt = -math.huge, -math.huge, -math.huge
local playing = false
local inFlight
local startGrace = 1
local owned = {}
local failedKit, failedSource
local eventFrame
local presets = {
    { value = "ready", labelKey = "GAMEMASTER_TURN_SOUND_READY", kit = "READY_CHECK", fallback = 8960 },
    { value = "whisper", labelKey = "GAMEMASTER_TURN_SOUND_WHISPER", kit = "TELL_MESSAGE" },
    { value = "soft", labelKey = "GAMEMASTER_TURN_SOUND_SOFT", kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", fallback = 856 },
}

local function positiveInteger(value)
    local ok, valid = pcall(function()
        return type(value) == "number" and value > 0 and value < math.huge
            and value == math.floor(value)
    end)
    return ok and valid
end

local function nativePlaying(handle)
    if type(C_Sound) ~= "table" or type(C_Sound.IsPlaying) ~= "function" then return nil end
    local ok, active = pcall(function()
        local value = C_Sound.IsPlaying(handle)
        if value == true then return true end
        if value == false then return false end
    end)
    if ok and type(active) == "boolean" then return active end
end

local function forget(record)
    if owned[record.handle] ~= record then return end
    owned[record.handle] = nil
    for _, key in ipairs({ "timer", "startTimer" }) do
        local timer = record[key]
        record[key] = nil
        if timer then
            pcall(function() if type(timer.Cancel) == "function" then timer:Cancel() end end)
        end
    end
end

local stopRecord

local function observe(record)
    local native = nativePlaying(record.handle)
    record.native = native
    if native == true then
        record.observedPlaying, record.pendingUntil = true, nil
        if failedKit == record.kit and failedSource == record.source then failedKit, failedSource = nil, nil end
    elseif native == false then
        if record.observedPlaying or not record.pendingUntil then
            forget(record)
        elseif not record.pendingExpired and addon.Runtime.GetMonotonicTime() >= record.pendingUntil then
             
             
            record.pendingExpired = true
            failedKit, failedSource = record.kit, record.source
            stopRecord(record)
        end
    end
    return native
end

local function collect(source, kit)
    local result = {}
    for _, record in pairs(owned) do
        observe(record)
        if owned[record.handle] == record and (not source or source == record.source) and (not kit or kit == record.kit) then
            result[#result + 1] = record
        end
    end
    return result
end

stopRecord = function(record)
    if owned[record.handle] ~= record then return true end
    if nativePlaying(record.handle) == false and not record.pendingUntil then forget(record); return true end
    if type(StopSound) ~= "function" then return false end
     
     
    local ok, result = pcall(StopSound, record.handle, 0)
    if not ok or result == false then return false end
    if nativePlaying(record.handle) ~= true then forget(record) end
    return true
end

local function schedule(record, key, delay, callback)
    local function run()
        if owned[record.handle] == record then callback() end
    end
    if type(C_Timer) ~= "table" then return false end
    if type(C_Timer.NewTimer) == "function" then
        local ok, timer = pcall(C_Timer.NewTimer, delay, run)
        if ok and timer then
            if owned[record.handle] == record then record[key] = timer end
            return true
        end
    end
    return type(C_Timer.After) == "function" and pcall(C_Timer.After, delay, run)
end

local function listenForFinish()
    if eventFrame or type(CreateFrame) ~= "function" then return end
    pcall(function()
        eventFrame = CreateFrame("Frame")
        if type(eventFrame.RegisterEvent) ~= "function" then return end
        eventFrame:RegisterEvent("SOUNDKIT_FINISHED")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")
        eventFrame:SetScript("OnEvent", function(_, event, handle)
            if event == "PLAYER_LOGOUT" then
                addon.GameMasterTurnSound.StopAll()
                return
            end
            local record = owned[handle]
             
            if record and (not record.pendingUntil or addon.Runtime.GetMonotonicTime() >= record.pendingUntil)
                and nativePlaying(handle) ~= true then forget(record) end
        end)
    end)
end

function addon.GameMasterTurnSound.GetPlaybackState(kit, source)
    local records = collect(source, kit)
    for _, record in ipairs(records) do
        if record.native == true then return "playing" end
    end
    if #records > 0 then return "unconfirmed" end
    return kit and failedKit == kit and (not source or failedSource == source) and "failed" or "idle"
end

local function soundKit(preset)
    local kit = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[preset.kit]
    return positiveInteger(kit) and kit <= 2147483647 and kit or preset.fallback
end

function addon.GameMasterTurnSound.GetPresets(selected)
    local result = {}
    for _, preset in ipairs(presets) do
        if soundKit(preset) then
            result[#result + 1] = { value = preset.value, label = addon.L(preset.labelKey) }
        end
    end
    selected = addon.Runtime.NormalizeSoundPreset(selected)
    if selected and selected:match("^kit:") then
        result[#result + 1] = { value = selected, label = addon.L("SOUND_BROWSER_ID") .. " " .. selected:sub(5) }
    end
    return result
end

function addon.GameMasterTurnSound.Stop(source, kit)
    if inFlight and (not source or source == inFlight.source) and (not kit or kit == inFlight.kit) then
        inFlight.cancelled = true
    end
    local records = collect(source, kit)
    local success = #records > 0
    for _, record in ipairs(records) do
        if not stopRecord(record) then success = false end
    end
    return success
end

function addon.GameMasterTurnSound.StopAll()
    return addon.GameMasterTurnSound.Stop()
end

function addon.GameMasterTurnSound.Play(presetID, source)
    source = source or "turn"
    if playing or (source ~= "turn" and source ~= "preview" and source ~= "feedback" and source ~= "incoming") then
        return false
    end
    if source == "incoming" then
        local state = addon.GameMasterPlayerState
        if not state.ShouldPlayIncomingActionSound() then return false end
        presetID = presetID or state.GetIncomingActionSoundPreset()
    end
    if source == "incoming" or source == "feedback" then
        local service, settings = addon.GameMasterService, addon.GameMasterSettings
        local turn = service and service.GetTurnState and service.GetTurnState()
         
         
        if turn and turn.active and turn.isNext and not turn.completed
            and settings and settings.ShouldPlayOwnTurnSound
            and settings.ShouldPlayOwnTurnSound() then return false end
    end
    local withOptions = type(C_Sound) == "table" and type(C_Sound.PlaySoundWithOptions) == "function"
    local playSound = type(C_Sound) == "table" and (withOptions and C_Sound.PlaySoundWithOptions or C_Sound.PlaySound)
    local channel
    if type(playSound) ~= "function" then playSound, channel = PlaySound, "Master" end
    local now = addon.Runtime.GetMonotonicTime()
    if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge
        then return false end
    if now < lastTurnAt or now < lastAlertAt or now < lastPreviewAt then
        lastTurnAt, lastAlertAt, lastPreviewAt = now, now, now
        return false
    end
    if source == "preview" then
        if now - lastAlertAt < cooldown or now - lastPreviewAt < 0.25 then return false end
        lastPreviewAt = now
    elseif source == "turn" then
        if now - lastTurnAt < cooldown then return false end
        lastTurnAt, lastAlertAt = now, now
    else
        if now - lastAlertAt < cooldown then return false end
        lastAlertAt = now
    end
     
     
    local selected = addon.Runtime.NormalizeSoundPreset(presetID or addon.GameMasterPlayerState.GetTurnSoundPreset()) or "ready"
    local kit
    for _, preset in ipairs(presets) do
        if preset.value == selected then kit = soundKit(preset); break end
    end
    kit = kit or tonumber(selected:match("^kit:(%d+)$")) or soundKit(presets[1])
    if type(playSound) ~= "function" then failedKit, failedSource = kit, source; return false end
    playing = true
    local records = collect()
    if #records >= 16 or (#records > 0 and not addon.GameMasterTurnSound.Stop()) then
        playing = false
        return false
    end
    listenForFinish()
    local attempt = { source = source, kit = kit }
    inFlight = attempt
     
     
     
    local ok, played, handle
    if withOptions then
        ok, played, handle = pcall(playSound, {
            soundKitID = kit, forceNoDuplicates = false, runFinishCallback = true,
        })
    else
        ok, played, handle = pcall(playSound, kit, channel, false, true)
    end
    inFlight = nil
    local active = false
    local pending = false
    if ok and positiveInteger(handle) then
        local previous = owned[handle]
        if previous then forget(previous) end
        local record = { handle = handle, source = source, kit = kit,
            pendingUntil = played == true and now + startGrace or nil }
        owned[handle] = record
        local native = observe(record)
         
         
        if native == nil then record.pendingUntil = nil end
        active = native == true or (native == nil and played == true)
        pending = record.pendingUntil ~= nil
        if attempt.cancelled then
            stopRecord(record)
            active, pending = false, false
        elseif owned[handle] == record then
            if pending then
                if type(C_Timer) == "table"
                    and not schedule(record, "startTimer", startGrace, function() observe(record) end) then
                    stopRecord(record)
                    active, pending = false, false
                end
            end
            if owned[handle] == record and (source == "preview" or selected:match("^kit:")) and type(C_Timer) == "table" then
                if not schedule(record, "timer", 5, function() stopRecord(record) end) then
                    stopRecord(record)
                    active, pending = false, false
                end
            end
        end
    end
    if active or pending then failedKit, failedSource = nil, nil else failedKit, failedSource = kit, source end
    playing = false
    return active
end
