local _, addon = ...

addon.GameMasterRoster = {}

local PROFILE_CACHE_TTL = 15
local rosterCache = {
    exact = {},
    fingerprint = nil,
    members = nil,
    profileExpiresAt = 0,
    short = {},
}
local invalidationInitialized = false
local lastCompleteMembers, lastGroupState, rosterAvailable = {}, false, true

local function accessible(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        if not ok or readable ~= true then return false end
    end
    return true
end

local function readEngine(callback, ...)
    if type(callback) ~= "function" then return nil, nil, false end
    local ok, first, second = pcall(callback, ...)
    if not ok or not accessible(first) or not accessible(second) then return nil, nil, false end
    return first, second, true
end

local function readBoolean(callback, ...)
    local value, _, ok = readEngine(callback, ...)
    if ok and type(value) == "boolean" then return value end
end

local function callBoolean(callback, ...)
    return readBoolean(callback, ...) == true
end

local function getHomeCategory()
    return _G.LE_PARTY_CATEGORY_HOME
end

local function isInGroup()
    local category = getHomeCategory()
    local grouped
    if category ~= nil then grouped = readBoolean(IsInGroup, category)
    else grouped = readBoolean(IsInGroup) end
    if grouped == nil then rosterAvailable = false; return lastGroupState end
    lastGroupState = grouped
    return grouped
end

local function isInRaid()
    local category = getHomeCategory()
    if category ~= nil and type(IsInRaid) == "function" then
        return readBoolean(IsInRaid, category)
    end
    return readBoolean(IsInRaid)
end

local function getCurrentRealm()
    local realm = readEngine(GetNormalizedRealmName)
    if type(realm) ~= "string" or realm == "" then
        realm = readEngine(GetRealmName)
    end
    if type(realm) == "string" then
        realm = realm:gsub("%s+", "")
    end
    return realm
end

local function getUnitPlayerID(unit)
    if type(unit) ~= "string" then return nil, false end
    if type(C_Secrets) == "table" and type(C_Secrets.ShouldUnitIdentityBeSecret) == "function"
        and readBoolean(C_Secrets.ShouldUnitIdentityBeSecret, unit) ~= false then return nil, false end
    if type(UnitExists) == "function" then
        local exists = readBoolean(UnitExists, unit)
        if exists == nil then return nil, false end
        if not exists then return nil, true end
    end

    local name
    local realm
    if type(UnitFullName) == "function" then
        local ok
        name, realm, ok = readEngine(UnitFullName, unit)
        if not ok then return nil, false end
    end
    if type(name) ~= "string" or name == "" then
        name = readEngine(GetUnitName, unit, true)
        if type(name) == "string" and name:find("-", 1, true) then
            return name, true
        end
    end
    if type(name) ~= "string" or name == "" then
        return nil, false
    end
    if type(realm) ~= "string" or realm == "" then
        realm = getCurrentRealm()
    end
    return type(realm) == "string" and realm ~= "" and (name .. "-" .. realm) or name, true
end

local function cleanProfileText(value)
    if type(value) ~= "string" then
        return nil
    end
    local text = value
        :gsub("|", "")
        :gsub("[%c]", " ")
        :match("^%s*(.-)%s*$")
    if text == ""
        or #text > addon.Constants.GAMEMASTER_MAX_RP_NAME_LENGTH
    then
        return nil
    end
    return text
end

local function createMember(unit, playerID, gameName, isLeader, online)
    playerID = playerID or getUnitPlayerID(unit)
    local playerKey = addon.Runtime.NormalizePlayerID(playerID)
    if not playerKey then
        return nil
    end

    gameName = gameName
        or readEngine(UnitName, unit)
        or playerID
    local ok, profile = pcall(addon.TRP3Bridge.GetRoleplayProfileInfo, playerID)
    if not ok or type(profile) ~= "table" then profile = {} end
    local rpName = cleanProfileText(profile.rpName) or gameName
    local profileColor = type(profile.color) == "string"
        and profile.color:gsub("#", "")
        or nil
    if not profileColor
        or not profileColor:match("^%x%x%x%x%x%x$")
    then
        profileColor = nil
    end
    local profileIcon = cleanProfileText(profile.icon)

    return {
        firstName = cleanProfileText(profile.firstName),
        gameName = gameName,
        isLeader = isLeader == true,
        lastName = cleanProfileText(profile.lastName),
        online = online ~= false,
        playerID = playerID,
        playerKey = playerKey,
        profileColor = profileColor,
        profileIcon = profileIcon,
        rpName = rpName,
        title = cleanProfileText(profile.title),
        unit = unit,
    }
end

function addon.GameMasterRoster.IsInGroup()
    return isInGroup()
end

function addon.GameMasterRoster.GetChatChannel()
    if not isInGroup() then
        return nil
    end
    local raid = isInRaid()
    if raid == nil then return nil end
    if raid then
        return "RAID"
    end
    return "PARTY"
end

function addon.GameMasterRoster.IsLocalLeader()
    return isInGroup() and callBoolean(UnitIsGroupLeader, "player", getHomeCategory())
end

function addon.GameMasterRoster.GetLocalPlayerID()
    local api = _G.TRP3_API
    local playerID = type(api) == "table"
        and type(api.globals) == "table"
        and api.globals.player_id
        or nil
    return type(playerID) == "string" and playerID ~= ""
        and playerID
        or getUnitPlayerID("player")
end

local function getPlayerLookupKey(playerID)
    local _, fullKey = addon.Runtime.NormalizeFullPlayerID(playerID)
    return fullKey or addon.Runtime.NormalizePlayerID(playerID)
end

local function getMonotonicTime()
    if addon.Runtime
        and type(addon.Runtime.GetMonotonicTime) == "function"
    then
        return tonumber(addon.Runtime.GetMonotonicTime()) or 0
    end
    return type(GetTime) == "function" and (tonumber(GetTime()) or 0) or 0
end

local function invalidateRosterCache()
    rosterCache.exact = {}
    rosterCache.fingerprint = nil
    rosterCache.members = nil
    rosterCache.profileExpiresAt = 0
    rosterCache.short = {}
end

addon.GameMasterRoster.InvalidateCache = invalidateRosterCache

local function initializeInvalidation()
    if invalidationInitialized then
        return
    end
    invalidationInitialized = true

    if type(CreateFrame) == "function" then
        local frame = CreateFrame("Frame")
        if frame
            and type(frame.RegisterEvent) == "function"
            and type(frame.SetScript) == "function"
        then
            frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            frame:RegisterEvent("PARTY_LEADER_CHANGED")
            frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            frame:RegisterEvent("UNIT_CONNECTION")
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnEvent", invalidateRosterCache)
        end
    end

    local api = _G.TRP3_API
    local trpAddon = _G.TRP3_Addon
    local events = type(trpAddon) == "table" and trpAddon.Events or nil
    if type(api) == "table"
        and type(api.RegisterCallback) == "function"
        and type(trpAddon) == "table"
        and type(events) == "table"
    then
        for _, eventName in ipairs({
            events.REGISTER_DATA_UPDATED,
            events.REGISTER_PROFILES_LOADED,
            events.REGISTER_PROFILE_DELETED,
        }) do
            if type(eventName) == "string" then
                pcall(
                    api.RegisterCallback,
                    trpAddon,
                    eventName,
                    invalidateRosterCache,
                    addon.GameMasterRoster
                )
            end
        end
    end
end

local function collectRosterState()
    rosterAvailable = true
    local grouped = isInGroup()
    if not rosterAvailable then return nil, nil, false end
    if not grouped then return nil, "solo", true end

     
     
    local instanceCategory = _G.LE_PARTY_CATEGORY_INSTANCE
    if instanceCategory ~= nil then
        local instanceGroup = readBoolean(IsInGroup, instanceCategory)
        if instanceGroup ~= false then return nil, nil, false end
    end

    local units = {}
    local raid = isInRaid()
    if raid == nil then return nil, nil, false end
    local function countMembers(callback, maximum)
        local count = readEngine(callback, getHomeCategory())
        if type(count) ~= "number" or count ~= count or count < 0 or count > maximum or count % 1 ~= 0 then return nil end
        return count
    end
    if raid then
        local count = countMembers(GetNumGroupMembers, 40)
        if not count or count == 0 then return nil, nil, false end
        for index = 1, count do
            units[#units + 1] = "raid" .. index
        end
    else
        units[1] = "player"
        local count
        if type(GetNumSubgroupMembers) == "function" then count = countMembers(GetNumSubgroupMembers, 4)
        else
            local total = countMembers(GetNumGroupMembers, 5)
            count = total and math.max(0, total - 1)
        end
        if not count then return nil, nil, false end
        for index = 1, count do
            units[#units + 1] = "party" .. index
        end
    end

    local state = {}
    local fingerprint = { raid and "raid" or "party" }
    for _, unit in ipairs(units) do
        local playerID, available = getUnitPlayerID(unit)
        if not available or not playerID then return nil, nil, false end
        local playerKey = addon.Runtime.NormalizePlayerID(playerID)
        if playerKey then
            local leader = readBoolean(UnitIsGroupLeader, unit, getHomeCategory())
            local online = type(UnitIsConnected) ~= "function" or readBoolean(UnitIsConnected, unit)
            if leader == nil or online == nil then return nil, nil, false end
            state[#state + 1] = {
                gameName = readEngine(UnitName, unit) or playerID,
                isLeader = leader,
                online = online,
                playerID = playerID,
                playerKey = playerKey,
                unit = unit,
            }
            fingerprint[#fingerprint + 1] = table.concat({
                playerKey,
                leader and "1" or "0",
                online and "1" or "0",
            }, ":")
        end
    end
    if #state < 2 then return nil, nil, false end
    return state, table.concat(fingerprint, "|"), true
end

local function rebuildLookupMaps(members)
    local exact = {}
    local short = {}
    for _, member in ipairs(members) do
        local key = getPlayerLookupKey(member.playerID or member.playerKey)
        if key then
            exact[key] = member
            local name = key:match("^([^-]+)")
            if name then
                short[name] = short[name] == nil and member or false
            end
        end
    end
    rosterCache.exact = exact
    rosterCache.short = short
end

function addon.GameMasterRoster.GetMembers()
    initializeInvalidation()
    local state, fingerprint, available = collectRosterState()
    rosterAvailable = available == true
     
    if not rosterAvailable then return lastCompleteMembers end
    if not state then
        lastCompleteMembers = {}
        invalidateRosterCache()
        return {}
    end
    local now = getMonotonicTime()
    if rosterCache.members
        and rosterCache.fingerprint == fingerprint
        and now < rosterCache.profileExpiresAt
    then
        return rosterCache.members
    end

    local members = {}
    local seen = {}
    for _, entry in ipairs(state) do
        local member = createMember(
            entry.unit,
            entry.playerID,
            entry.gameName,
            entry.isLeader,
            entry.online
        )
        if member and not seen[member.playerKey] then
            seen[member.playerKey] = true
            members[#members + 1] = member
        end
    end
    rosterCache.fingerprint = fingerprint
    rosterCache.members = members
    lastCompleteMembers = members
    rosterCache.profileExpiresAt = now + PROFILE_CACHE_TTL
    rebuildLookupMaps(members)
    return members
end

function addon.GameMasterRoster.IsAvailable()
    return rosterAvailable
end

local function playerIDsMatch(first, second)
    local firstKey = getPlayerLookupKey(first)
    local secondKey = getPlayerLookupKey(second)
    if not firstKey or not secondKey then
        return false
    end
    if firstKey == secondKey then
        return true
    end
    local firstName = firstKey:match("^([^-]+)")
    local secondName = secondKey:match("^([^-]+)")
    return firstName ~= nil
        and firstName == secondName
        and (not firstKey:find("-", 1, true)
            or not secondKey:find("-", 1, true))
end

addon.GameMasterRoster.PlayerIDsMatch = playerIDsMatch

function addon.GameMasterRoster.FindMember(playerID)
    local playerKey = getPlayerLookupKey(playerID)
    if not playerKey then
        return nil
    end
    local members = addon.GameMasterRoster.GetMembers()
    if members == rosterCache.members then
        local exact = rosterCache.exact[playerKey]
        if exact then
            return exact
        end
        if not playerKey:find("-", 1, true) then
            return rosterCache.short[playerKey] or nil
        end
        return nil
    end
    for _, member in ipairs(members) do
        local memberID = member.playerID or member.playerKey
        if getPlayerLookupKey(memberID) == playerKey then
            return member
        end
    end

    local match
    for _, member in ipairs(members) do
        local memberID = member.playerID or member.playerKey
        if playerIDsMatch(playerID, memberID) then
            if match then
                return nil
            end
            match = member
        end
    end
    return match
end

function addon.GameMasterRoster.IsMember(playerID)
    local member = addon.GameMasterRoster.FindMember(playerID)
    return rosterAvailable and member ~= nil
end

function addon.GameMasterRoster.IsLeader(playerID)
    local member = addon.GameMasterRoster.FindMember(playerID)
    return rosterAvailable and member ~= nil and member.isLeader == true
end

function addon.GameMasterRoster.GetLeader()
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.isLeader then
            return member
        end
    end
    return nil
end

 
 
local function companionValueAccessible(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok or secret ~= false then return false end
    if type(canaccessvalue) == "function" then
        local accessible
        ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    end
    return true
end

local function companionCall(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, first, second = pcall(callback, ...)
    if not ok or not companionValueAccessible(first) or not companionValueAccessible(second) then return nil end
    return first, second
end

local function companionText(value, maximum)
    if not companionValueAccessible(value) or type(value) ~= "string" then return nil end
    if value == "" or #value > maximum or value:find("[%c|]") then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil
end

local function companionIdentityVisible(unit)
    if type(C_Secrets) == "table" and type(C_Secrets.ShouldUnitIdentityBeSecret) == "function"
        and companionCall(C_Secrets.ShouldUnitIdentityBeSecret, unit) ~= false then return false end
    return companionCall(UnitExists, unit) == true
end

local function companionOwnerKey(unit)
    if not companionIdentityVisible(unit) or companionCall(UnitIsPlayer, unit) ~= true
        or companionCall(UnitIsConnected, unit) ~= true then return nil end
    local name, realm = companionCall(UnitFullName, unit)
    name = companionText(name, 120)
    if not name or name:find("[%s:%-]") then return nil end
    if realm == nil or realm == "" then
        realm = companionCall(GetNormalizedRealmName)
    end
    realm = companionText(realm, 120)
    if not realm then return nil end
    local _, key = addon.Runtime.NormalizeFullPlayerID(name .. "-" .. realm)
    return key
end

local function companionGUID(value)
    local guid = companionText(value, 128)
    if guid and guid:match("^%a+%-%x[%x%-]*$") then return guid end
end

local function journalCompanion()
    local journal = C_PetJournal
    if type(journal) ~= "table" or type(journal.GetPetInfoByPetID) ~= "function" then return nil end
    local guid = companionGUID(companionCall(journal.GetSummonedPetGUID))
    local owner = guid and companionOwnerKey("player")
    if not owner then return nil end
    local ok, species, customName, _, _, _, _, _, speciesName, icon = pcall(journal.GetPetInfoByPetID, guid)
    if not ok or not companionValueAccessible(species) or type(species) ~= "number" or species <= 0
        or species > 2147483647 or species % 1 ~= 0
        or not companionValueAccessible(customName) or not companionValueAccessible(speciesName) then return nil end
    local name = companionText(customName, 120) or companionText(speciesName, 120)
    if not name or companionGUID(companionCall(journal.GetSummonedPetGUID)) ~= guid
        or companionOwnerKey("player") ~= owner then return nil end
    if not companionValueAccessible(icon) or type(icon) ~= "number" or icon <= 0
        or icon > 2147483647 or icon % 1 ~= 0 then icon = nil end
    return { guid = guid, name = name, ownerPlayerKey = owner, icon = icon }
end

function addon.GameMasterRoster.GetCompanions(localOnly)
    local candidates, seen = {}, {}
    local function add(unit, ownerUnit)
        if not companionIdentityVisible(unit) or companionCall(UnitIsPlayer, unit) ~= false
            or companionCall(UnitIsDeadOrGhost, unit) ~= false then return end
        local guid = companionGUID(companionCall(UnitGUID, unit))
        if not guid or seen[guid] then return end
        local name = companionText(companionCall(UnitName, unit), 120)
        local ownerPlayerKey = companionOwnerKey(ownerUnit)
        if not name or not ownerPlayerKey then return end
         
        if companionGUID(companionCall(UnitGUID, unit)) ~= guid
            or companionOwnerKey(ownerUnit) ~= ownerPlayerKey then return end
        seen[guid] = true
        candidates[#candidates + 1] = {
            name = name, ownerPlayerKey = ownerPlayerKey, unit = unit, guid = guid,
        }
        return true
    end

    add("pet", "player")
     
    local companion = journalCompanion()
    if companion then
        if not seen[companion.guid] then
            seen[companion.guid] = true
            candidates[#candidates + 1] = companion
        end
    else
        add("minipet", "player")
    end
    if localOnly then return candidates end
    local instanceCategory = _G.LE_PARTY_CATEGORY_INSTANCE
    if instanceCategory ~= nil and companionCall(IsInGroup, instanceCategory) ~= false then return candidates end
    local homeCategory = getHomeCategory()
    local raid = companionCall(IsInRaid, homeCategory)
    if raid == true then
        for index = 1, 40 do add("raidpet" .. index, "raid" .. index) end
    elseif raid == false and companionCall(IsInGroup, homeCategory) == true then
        for index = 1, 4 do add("partypet" .. index, "party" .. index) end
    end
    return candidates
end

function addon.GameMasterRoster.GetLocalCompanions()
    return addon.GameMasterRoster.GetCompanions(true)
end

 
function addon.GameMasterRoster.ValidateCompanionReports(entries, ownerKey)
    if not companionValueAccessible(entries) or type(entries) ~= "table"
        or not companionText(ownerKey, 241) then return nil end
    local count = 0
    for key in pairs(entries) do
        if not companionValueAccessible(key) or type(key) ~= "number"
            or key % 1 ~= 0 or key < 1 or key > 2 then return nil end
        count = count + 1
    end
    local result, seen = {}, {}
    for index = 1, count do
        local entry = entries[index]
        if not companionValueAccessible(entry) or type(entry) ~= "table" then return nil end
        for key in pairs(entry) do
            if not companionValueAccessible(key) or (key ~= "guid" and key ~= "name" and key ~= "icon") then return nil end
        end
        local guid, name = companionGUID(entry.guid), companionText(entry.name, 120)
        if not guid or not (guid:match("^Pet%-") or guid:match("^Creature%-") or guid:match("^BattlePet%-"))
            or not name or seen[guid] or not companionValueAccessible(entry.icon) then return nil end
        local icon = entry.icon
        if icon ~= nil and (type(icon) ~= "number" or icon < 1 or icon > 2147483647 or icon % 1 ~= 0) then return nil end
        seen[guid] = true
        result[index] = { guid = guid, name = name, icon = icon, ownerPlayerKey = ownerKey, ownerReported = true }
    end
    return result
end

function addon.GameMasterRoster.FindCompanion(guid)
    guid = companionGUID(guid)
    if not guid then return nil end
    for _, candidate in ipairs(addon.GameMasterRoster.GetCompanions()) do
        if candidate.guid == guid then return candidate end
    end
    return nil
end

local worldMarkers = {
    { index = 1, labelKey = "GAMEMASTER_MARKER_SQUARE", raidIcon = 6 },
    { index = 2, labelKey = "GAMEMASTER_MARKER_TRIANGLE", raidIcon = 4 },
    { index = 3, labelKey = "GAMEMASTER_MARKER_DIAMOND", raidIcon = 3 },
    { index = 4, labelKey = "GAMEMASTER_MARKER_CROSS", raidIcon = 7 },
    { index = 5, labelKey = "GAMEMASTER_MARKER_STAR", raidIcon = 1 },
    { index = 6, labelKey = "GAMEMASTER_MARKER_CIRCLE", raidIcon = 2 },
    { index = 7, labelKey = "GAMEMASTER_MARKER_MOON", raidIcon = 5 },
    { index = 8, labelKey = "GAMEMASTER_MARKER_SKULL", raidIcon = 8 },
}

local function getWorldMarker(index)
    if type(index) ~= "number" then
        return nil
    end
    for _, marker in ipairs(worldMarkers) do
        if marker.index == index then
            return marker
        end
    end
    return nil
end

function addon.GameMasterRoster.GetWorldMarker(index)
    local definition = getWorldMarker(index)
    if not definition then
        return nil
    end

    local metadata = type(addon.NPCMarkers) == "table"
        and type(addon.NPCMarkers.GetMetadata) == "function"
        and addon.NPCMarkers.GetMetadata(index)
        or nil
    local name = type(metadata) == "table" and metadata.name or nil
    local color = type(metadata) == "table" and metadata.color or nil
    local health = type(metadata) == "table" and metadata.health or nil
    local displayName = name or addon.L(definition.labelKey)
    if type(color) == "string" and color:match("^%x%x%x%x%x%x$") then
        displayName = string.format("|cff%s%s|r", color, displayName)
    else
        color = nil
    end
    if type(health) == "number" then
        displayName = string.format("%s |cffb8b8b8(%d%%)|r", displayName, health)
    end

    return {
        attitude = type(metadata) == "table" and metadata.attitude or nil,
        color = color,
        health = health,
        index = definition.index,
        label = string.format(
            "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s",
            definition.raidIcon,
            displayName
        ),
        name = name,
        raidIcon = definition.raidIcon,
    }
end

function addon.GameMasterRoster.GetWorldMarkerLabel(index)
    local marker = addon.GameMasterRoster.GetWorldMarker(index)
    if not marker then
        return addon.L("GAMEMASTER_NO_TARGET")
    end
    return marker.label
end

local function isWorldMarkerActive(index)
    if type(IsRaidMarkerActive) ~= "function" then
        return false
    end
     
     
    local success, active = pcall(function()
        return IsRaidMarkerActive(index) == true
    end)
    return success and active or false
end

function addon.GameMasterRoster.GetActiveWorldMarkers()
    local activeMarkers = {}
    for _, marker in ipairs(worldMarkers) do
        if isWorldMarkerActive(marker.index) then
            activeMarkers[#activeMarkers + 1] =
                addon.GameMasterRoster.GetWorldMarker(marker.index)
        end
    end
    return activeMarkers
end
