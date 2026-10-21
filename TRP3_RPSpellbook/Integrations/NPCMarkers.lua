local _, addon = ...

addon.NPCMarkers = {}

local attitudeColors = {
    [0] = "BF3821",  
    [1] = "CEBF00",  
    [2] = "42AB0F",  
    [3] = "808080",  
}

local function cleanName(value)
    if type(value) ~= "string" then
        return nil
    end
    local name = value
        :gsub("|", "")
        :gsub("[%c]", " ")
        :match("^%s*(.-)%s*$")
    if name == ""
        or #name > addon.Constants.GAMEMASTER_MAX_TARGET_LENGTH
    then
        return nil
    end
    return name
end

local function findNPCMarkerIndex(worldMarkerIndex)
    local npcm = _G.Npcm
    local markers = type(npcm) == "table" and npcm.markers or nil
    if type(markers) ~= "table" then
        return nil
    end
    for index, marker in ipairs(markers) do
        if type(marker) == "table"
            and tonumber(marker.wm) == worldMarkerIndex
        then
            return index
        end
    end
    return nil
end

function addon.NPCMarkers.GetMetadata(worldMarkerIndex)
    if type(worldMarkerIndex) ~= "number"
        or worldMarkerIndex < 1
        or worldMarkerIndex > 8
        or worldMarkerIndex ~= math.floor(worldMarkerIndex)
    then
        return nil
    end

    local markerIndex = findNPCMarkerIndex(worldMarkerIndex)
    local saved = _G.NPCM_SAVED
    local markers = type(saved) == "table" and saved.markers or nil
    local source = markerIndex and type(markers) == "table"
        and markers[markerIndex]
        or nil
    if type(source) ~= "table" then
        return nil
    end

    local attitude = tonumber(source.attitude)
    if not attitude
        or attitude < 0
        or attitude > 3
        or attitude ~= math.floor(attitude)
    then
        attitude = nil
    end
    local health = tonumber(source.hp)
    if health
        and health == health
        and health ~= math.huge
        and health ~= -math.huge
    then
        health = math.max(0, math.min(100, math.floor(health)))
    else
        health = nil
    end

    return {
        attitude = attitude,
        color = attitude and attitudeColors[attitude] or nil,
        health = health,
        name = cleanName(source.text),
        source = "NPCsMarkers",
    }
end

 
function addon.NPCMarkers.Assign(worldMarkerIndex, actor)
    local npcm, saved = _G.Npcm, _G.NPCM_SAVED
    local index = findNPCMarkerIndex(worldMarkerIndex)
    if not index or type(npcm.updateMarkerData) ~= "function"
        or type(saved) ~= "table" or type(saved.markers) ~= "table"
        or type(saved.markers[index]) ~= "table" then return nil end
    local name = type(actor) == "table" and cleanName(actor.name)
    if not name then return false end
    local attitudes = { friendly = 2, neutral = 1, hostile = 0 }
    local attitude = attitudes[actor.relationship] or 1
    local ok, err = pcall(function()
        npcm.updateMarkerData(index, "text", name)
        npcm.updateMarkerData(index, "attitude", attitude)
        local field = _G["npcm_frameBk_fLine_" .. index .. "_editBox"]
        if field and field.SetText then field:SetText(name) end
        if _G["npcm_frameBk_fLine_" .. index .. "_attitude_radBtnAttitude_0"]
            and type(npcm.allumeRadioBtnsAttitude) == "function" then
            npcm.allumeRadioBtnsAttitude(index, attitude, false)
        end
    end)
    return ok, not ok and tostring(err) or nil
end
