local _, addon = ...

addon.PlayerTooltip = {
    initialized = false,
}

local constants = addon.Constants
local queries = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)
local peerListenerRegistered = false
local refreshScheduled = false

local function isTooltip(value)
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

local function getPlayerID()
    local api = _G.TRP3_API
    return type(api) == "table"
        and type(api.globals) == "table"
        and api.globals.player_id
        or nil
end

local function isSelf(playerID)
    local target = addon.Runtime.NormalizePlayerID(playerID)
    local player = addon.Runtime.NormalizePlayerID(getPlayerID())
    return target ~= nil and target == player
end

local function sanitizeVersion(version)
    if type(version) ~= "string"
        or version == ""
        or #version > constants.PLAYER_TOOLTIP_VERSION_MAX_LENGTH
        or version:find("[%c|]")
        or version:find("[^%w._-]")
    then
        return nil
    end
    return version
end

local function getVersion(playerID)
    if isSelf(playerID) then
        return constants.ADDON_VERSION
    end

    local peer = addon.Communication.GetPeer(playerID)
    return peer and sanitizeVersion(peer.addonVersion) or nil
end

local function getColor()
    local api = _G.TRP3_API
    local configuration = type(api) == "table" and api.configuration or nil
    local getValue = type(configuration) == "table" and configuration.getValue or nil
    local createColor = type(api) == "table" and api.CreateColorFromHexString or nil
    if type(getValue) ~= "function" or type(createColor) ~= "function" then
        return 1, 1, 1
    end

    local valueSuccess, colorValue = pcall(getValue, "tooltip_main_color")
    if not valueSuccess or type(colorValue) ~= "string" then
        return 1, 1, 1
    end

    local colorSuccess, color = pcall(createColor, colorValue)
    if not colorSuccess or type(color) ~= "table" then
        return 1, 1, 1
    end
    return tonumber(color.r) or 1, tonumber(color.g) or 1, tonumber(color.b) or 1
end

local function getRightLine(tooltip, index)
    local directLine = tooltip["TextRight" .. index]
    if directLine then
        return directLine
    end

    local tooltipName = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if type(tooltipName) ~= "string" or tooltipName == "" then
        return nil
    end
    return _G[tooltipName .. "TextRight" .. index]
end

local function getLeftLine(tooltip, index)
    local directLine = tooltip["TextLeft" .. index]
    if directLine then
        return directLine
    end
    local tooltipName = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if type(tooltipName) ~= "string" or tooltipName == "" then
        return nil
    end
    return _G[tooltipName .. "TextLeft" .. index]
end

local function getLineText(line)
    if not line or type(line.GetText) ~= "function" then
        return nil
    end

    local success, text = pcall(line.GetText, line)
    if not success then
        return nil
    end
    if type(_G.canaccessvalue) == "function" and not _G.canaccessvalue(text) then
        return nil
    end
    return type(text) == "string" and text or nil
end

local function formatVersion(version)
    version = sanitizeVersion(version)
    if not version then
        return nil
    end
    return constants.PLAYER_TOOLTIP_LABEL .. " v" .. version
end

local function findVersionLine(tooltip)
    if type(tooltip.NumLines) ~= "function" then
        return nil, nil
    end

    local prefix = constants.PLAYER_TOOLTIP_LABEL .. " v"
    for index = 1, tooltip:NumLines() do
        local line = getRightLine(tooltip, index)
        local text = getLineText(line)
        if text and text:sub(1, #prefix) == prefix then
            return line, index
        end
    end
    return nil, nil
end

local function getBuffRemaining(entry)
    local remote = addon.GameMasterService.GetRemoteSession()
    local round = addon.GameMasterService.GetActiveRound()
    local roundNumber = round and round.number
        or (remote and remote.roundNumber)
        or 0
    if entry.spell and entry.spell.effects and entry.spell.effects.durationRounds == 0 then
        return addon.Constants.EFFECT_DURATION_INFINITY
    end
    if entry.expiresRound then
        return addon.L(
            "GAMEMASTER_BUFF_REMAINING_ROUNDS",
            math.max(0, entry.expiresRound - roundNumber)
        )
    end
    if entry.expiresAt then
        local seconds = math.max(0, entry.expiresAt - addon.Runtime.GetTimestamp())
        local formatted = type(_G.SecondsToTime) == "function"
            and _G.SecondsToTime(seconds)
            or (tostring(math.ceil(seconds)) .. "s")
        return addon.L("GAMEMASTER_BUFF_REMAINING_TIME", formatted)
    end
    return ""
end

local function findBuffLine(tooltip)
    if type(tooltip.NumLines) ~= "function" then
        return nil
    end
    local cachedIndex = tonumber(tooltip.spellbookBuffLineIndex)
    if cachedIndex and cachedIndex >= 1 and cachedIndex <= tooltip:NumLines() then
        return getLeftLine(tooltip, cachedIndex), cachedIndex
    end
    local prefix = addon.L("GAMEMASTER_TOOLTIP_BUFFS") .. ":"
    for index = 1, tooltip:NumLines() do
        local line = getLeftLine(tooltip, index)
        local text = getLineText(line)
        if text and text:sub(1, #prefix) == prefix then
            return line, index
        end
    end
    return nil
end

local function formatBuffLine(playerID)
    if not addon.GameMasterService
        or type(addon.GameMasterService.GetActiveBuffsForPlayer) ~= "function"
    then
        return nil
    end
    local parts = {}
    for _, entry in ipairs(
        addon.GameMasterService.GetActiveBuffsForPlayer(playerID)
    ) do
        local spell = entry.spell or {}
        local icon = addon.TRP3Bridge.ResolveIconTexture(
            (spell.icon ~= nil and spell.icon ~= "" and spell.icon)
                or addon.Constants.DEFAULT_BOOK_ICON
        )
        icon = icon and tostring(icon):gsub("[|:]", "") or ""
        local presentation = addon.SpellPresentation.GetEffectPresentation(spell)
        local effectLabel = presentation and presentation.label or nil
        if effectLabel and presentation.colors[1] then
            effectLabel = "|cff" .. presentation.colors[1] .. effectLabel .. "|r"
        end
        local remaining = getBuffRemaining(entry)
        local effectStatus = effectLabel and remaining ~= ""
            and (effectLabel .. ", " .. remaining)
            or effectLabel or remaining
        parts[#parts + 1] = string.format(
            "%s%s%s",
            icon ~= "" and ("|T" .. icon .. ":14:14|t ") or "",
            spell.name or addon.L("UNKNOWN_ABILITY"),
            effectStatus and (" (" .. effectStatus .. ")") or ""
        )
    end
    if #parts == 0 then
        return nil
    end
    return addon.L("GAMEMASTER_TOOLTIP_BUFFS") .. ": "
        .. table.concat(parts, "  ")
end

local function updateBuffLine(tooltip, playerID)
    local text = formatBuffLine(playerID)
    local existing, existingIndex = findBuffLine(tooltip)
    if existing then
        existing:SetText(text or "")
        tooltip.spellbookBuffLineIndex = existingIndex
        return text ~= nil
    end
    if not text or type(tooltip.AddLine) ~= "function" then
        return false
    end
    local red, green, blue = getColor()
    tooltip:AddLine(text, red, green, blue, true)
    tooltip.spellbookBuffLineIndex = tooltip:NumLines()
    return true
end

local function setVersionFont(tooltip)
    local line = getRightLine(tooltip, tooltip:NumLines())
    if not line or type(line.GetFont) ~= "function" or type(line.SetFont) ~= "function" then
        return
    end

    local font, _, flags = line:GetFont()
    if font then
        line:SetFont(font, 10, flags)
    end
end

local function forceLayout(tooltip)
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
    if type(tooltip.GetTop) == "function" then
        tooltip:GetTop()
    end
end

local function requestUnknownPeer(playerID)
    if isSelf(playerID) or not addon.Communication.enabled then
        return
    end

    local key = addon.Runtime.NormalizePlayerID(playerID)
    if not key then
        return
    end

    local now = addon.Runtime.GetMonotonicTime()
    local lastQuery = queries:Get(key)
    if lastQuery and now - lastQuery < constants.PLAYER_TOOLTIP_QUERY_COOLDOWN then
        return
    end
    queries:Set(key, now)
    addon.Communication.QueryPeer(playerID)
end

function addon.PlayerTooltip.Update(tooltip, playerID)
    if not isTooltip(tooltip) then
        return false
    end

    playerID = playerID or tooltip.target
    if addon.TimedEffects and addon.TimedEffects.RequestSnapshot and not isSelf(playerID)
        and addon.Communication.HasCapability(playerID, "aura-display-v1") then
        addon.TimedEffects.RequestSnapshot(playerID)
    end
    if addon.CurrentlyEffects and addon.CurrentlyEffects.ColorizeTooltip then
        addon.CurrentlyEffects.ColorizeTooltip(tooltip, playerID)
    end
    updateBuffLine(tooltip, playerID)
    local version = getVersion(playerID)
    local text = formatVersion(version)
    local existingLine, existingIndex = findVersionLine(tooltip)
    if existingLine and not text then
        existingLine:SetText("")
        requestUnknownPeer(playerID)
        forceLayout(tooltip)
        return false
    end

    if existingLine and existingIndex == tooltip:NumLines() then
        existingLine:SetText(text)
        forceLayout(tooltip)
        return true
    end

    if existingLine then
        existingLine:SetText("")
    end
    if not text then
        requestUnknownPeer(playerID)
        return false
    end
    if type(tooltip.AddDoubleLine) ~= "function" then
        return false
    end

    local red, green, blue = getColor()
    tooltip:AddDoubleLine(" ", text, 1, 1, 1, red, green, blue)
    setVersionFont(tooltip)
    forceLayout(tooltip)
    return true
end

local function getVisibleTooltip()
    local tooltip = _G.TRP3_CharacterTooltip
    if not isTooltip(tooltip) then
        return nil
    end
    if type(tooltip.IsShown) == "function" and not tooltip:IsShown() then
        return nil
    end
    return tooltip
end

local function refreshVisibleTooltip()
    refreshScheduled = false
    local tooltip = getVisibleTooltip()
    if tooltip then
        addon.PlayerTooltip.Update(tooltip, tooltip.target)
    end
end

local function scheduleVisibleRefresh()
    if refreshScheduled then
        return
    end
    refreshScheduled = true

    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, refreshVisibleTooltip)
    else
        refreshVisibleTooltip()
    end
end

local function updateVisibleTooltipForPeer(peer)
    local tooltip = getVisibleTooltip()
    if not tooltip then
        return
    end

    local target = addon.Runtime.NormalizePlayerID(tooltip.target)
    local player = peer and addon.Runtime.NormalizePlayerID(peer.playerID) or nil
    if target and target == player then
        scheduleVisibleRefresh()
    end
end

local function registerTRP3RefreshCallbacks()
    local api = _G.TRP3_API
    local trpAddon = _G.TRP3_Addon
    local events = type(trpAddon) == "table" and trpAddon.Events or nil
    if type(api) ~= "table"
        or type(api.RegisterCallback) ~= "function"
        or type(events) ~= "table"
    then
        return
    end

    local function onTRP3Refresh(_, targetID)
        local tooltip = getVisibleTooltip()
        if not tooltip then
            return
        end

        local target = addon.Runtime.NormalizePlayerID(tooltip.target)
        local refreshed = addon.Runtime.NormalizePlayerID(targetID)
        if not refreshed or target == refreshed then
            scheduleVisibleRefresh()
        end
    end

    local refreshEvents = {
        events.MOUSE_OVER_CHANGED,
        events.REGISTER_DATA_UPDATED,
        events.REGISTER_REQUEST_STATE_CHANGED,
    }
    for _, eventName in ipairs(refreshEvents) do
        if type(eventName) == "string" then
            pcall(api.RegisterCallback, trpAddon, eventName, onTRP3Refresh)
        end
    end

    if type(api.GameEvents) == "table" then
        pcall(api.RegisterCallback, api.GameEvents, "PLAYER_TARGET_CHANGED", function()
            scheduleVisibleRefresh()
        end)
    end
end

function addon.PlayerTooltip.Initialize()
    if addon.PlayerTooltip.initialized then
        return true
    end

    local tooltip = _G.TRP3_CharacterTooltip
    if not isTooltip(tooltip) or type(tooltip.HookScript) ~= "function" then
        return false, addon.L("TRP3_API_UNAVAILABLE", "character tooltip")
    end

    tooltip:HookScript("OnShow", function(self)
        addon.PlayerTooltip.Update(self, self.target)
        scheduleVisibleRefresh()
    end)
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self)
        self.spellbookBuffLineIndex = nil
        scheduleVisibleRefresh()
    end)

    if not peerListenerRegistered then
        local success = addon.Communication.RegisterPeerListener(updateVisibleTooltipForPeer)
        peerListenerRegistered = success == true
    end
    registerTRP3RefreshCallbacks()

    addon.PlayerTooltip.initialized = true
    scheduleVisibleRefresh()
    return true
end

if addon.GameMasterEffects
    and type(addon.GameMasterEffects.RegisterListener) == "function"
then
    addon.GameMasterEffects.RegisterListener(scheduleVisibleRefresh)
end
if addon.GameMasterService
    and type(addon.GameMasterService.RegisterListener) == "function"
then
    addon.GameMasterService.RegisterListener(scheduleVisibleRefresh)
end
if addon.TimedEffects and type(addon.TimedEffects.RegisterListener) == "function" then
    addon.TimedEffects.RegisterListener(scheduleVisibleRefresh)
end

addon.PlayerTooltip.FormatVersion = formatVersion
