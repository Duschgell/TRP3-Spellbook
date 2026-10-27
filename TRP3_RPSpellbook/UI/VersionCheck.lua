local _, addon = ...

addon.VersionCheck = {}
local check = addon.VersionCheck
local constants = addon.Constants
local peers, peerCount = {}, 0
local announced = addon.Cache.NewBounded(constants.VERSION_CHECK_HISTORY_LIMIT)
local initialized, scheduled, sessionNotified, enteredWorld, readyAt, dialog
local worldEntry, worldHandled
local LINK_PREFIX = "addon:rpspellbook:version:"

local function parse(value)
    if type(value) ~= "string" or #value > constants.VERSION_CHECK_MAX_VERSION_BYTES then return end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then major, minor = value:match("^(%d+)%.(%d+)$"); patch = "0" end
    if not major then return end
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    if major > 999999 or minor > 999999 or patch > 999999 then return end
    return { major, minor, patch }, string.format("%d.%d.%d", major, minor, patch)
end

local function higher(left, right)
    if not left or not right then return false end
    for index = 1, 3 do
        if left[index] ~= right[index] then return left[index] > right[index] end
    end
    return false
end

local function savedSettings()
    local root = addon.Database.GetDB()
    return type(root) == "table" and type(root.settings) == "table" and root.settings or nil
end

local function requiredReports()
    local value = constants.VERSION_CHECK_REQUIRED_REPORTS
    if type(value) ~= "number" or value ~= math.floor(value)
        or value < 2 or value > constants.COMMUNICATION_MAX_PEERS then return math.huge end
    return value
end

local function confirmedNotes(entry)
    local count = type(entry) == "table" and entry.confirmations
    if type(count) ~= "number" or count ~= math.floor(count) or count < requiredReports()
        or count > constants.COMMUNICATION_MAX_PEERS then return nil, 0 end
    local notes = addon.ReleaseNotes.Copy(entry.notes)
    return notes, notes and count or 0
end

local function rememberNotice(candidate)
    local entry = { version = candidate.version, notes = addon.ReleaseNotes.Copy(candidate.notes),
        confirmations = candidate.confirmations or 0 }
    announced:Set(entry.version, { notes = addon.ReleaseNotes.Copy(entry.notes), confirmations = entry.confirmations })
    local settings = savedSettings()
    if not settings then return end
    local previous, retained = settings.versionCheckNotes, { entry }
    for index = 1, constants.VERSION_CHECK_HISTORY_LIMIT do
        local item = type(previous) == "table" and previous[index]
        local _, version = parse(type(item) == "table" and item.version)
        if version and version ~= entry.version and #retained < constants.VERSION_CHECK_HISTORY_LIMIT then
            local notes, confirmations = confirmedNotes(item)
            retained[#retained + 1] = { version = version, notes = notes, confirmations = confirmations }
        end
    end
    settings.versionCheckNotes = retained
end

local function showNotes(version, notes)
    if not dialog then
        local factory, theme = addon.UIFactory, addon.Theme
        dialog = factory.CreateDialog("", 480, 340)
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -52)
        scroll:SetPoint("BOTTOMRIGHT", -40, 56)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(420)
        local text = factory.CreateLabel(child, theme.Fonts.body, "", theme.Colors.text)
        text:SetPoint("TOPLEFT")
        text:SetWidth(420)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetWordWrap(true)
        scroll:SetScrollChild(child)
        local close = factory.CreateButton(dialog, addon.L("CLOSE"), 110)
        close:SetPoint("BOTTOMRIGHT", -20, 16)
        close:SetScript("OnClick", function() dialog:Hide() end)
        dialog.text, dialog.content, dialog.scroll = text, child, scroll
    end
    dialog.title:SetText(addon.L("UPDATE_NOTES_TITLE", version))
    dialog.text:SetText(addon.ReleaseNotes.GetText(notes) or addon.L("UPDATE_NOTES_EMPTY"))
    dialog.content:SetHeight(math.max(1, dialog.text:GetStringHeight()))
    dialog.scroll:SetVerticalScroll(0)
    dialog:Show()
    addon.UIFactory.BringToFront(dialog)
end

function check.HandleLink(link, button)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return false end
    if #link > #LINK_PREFIX + constants.VERSION_CHECK_MAX_VERSION_BYTES then return true end
    if button and button ~= "LeftButton" or IsModifiedClick and IsModifiedClick() then return true end
    local version = link:sub(#LINK_PREFIX + 1)
    local entry = announced:Get(version)
    if entry then showNotes(version, confirmedNotes(entry)) end
    return true
end

local function bestCandidate()
    local current = parse(addon.Constants.ADDON_VERSION)
    local settings = savedSettings()
    local _, last = parse(settings and settings.versionCheckLastNotified)
    local counts, best = {}, nil
    local required = requiredReports()
    local now = addon.Runtime.GetMonotonicTime()
    for id, peer in pairs(peers) do
        if now - peer.seen > addon.Constants.COMMUNICATION_PEER_TTL then
            peers[id], peerCount = nil, peerCount - 1
        elseif higher(peer.parts, current) and peer.version ~= last and not announced:Get(peer.version) then
            local candidate = counts[peer.version]
            if not candidate then
                candidate = { version = peer.version, parts = peer.parts, count = 0, variants = {} }
                counts[peer.version] = candidate
            end
            candidate.count = candidate.count + 1
            if peer.notesKey then
                local variant = candidate.variants[peer.notesKey]
                if not variant then
                    variant = { notes = peer.notes, count = 0 }
                    candidate.variants[peer.notesKey] = variant
                end
                variant.count = variant.count + 1
            end
        end
    end
    for _, candidate in pairs(counts) do
        if candidate.count >= required and (not best or higher(candidate.parts, best.parts)) then best = candidate end
    end
    if best then
        for _, variant in pairs(best.variants) do
            if variant.count >= required then
                if best.notes then best.notes, best.confirmations = nil, 0; break end
                best.notes, best.confirmations = variant.notes, variant.count
            end
        end
    end
    return best
end

local schedule
local function notify()
    scheduled = false
    if sessionNotified or not addon.SpellCreationSettings.ShouldNotifyUpdates() then return end
    if not worldHandled then return end
    if addon.Runtime.GetMonotonicTime() < readyAt then schedule(); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    local candidate = bestCandidate()
    if not candidate then return end
    sessionNotified = true
    local settings = savedSettings()
    if settings then
        settings.versionCheckSessionNotified = true
        settings.versionCheckLastNotified = candidate.version
    end
    rememberNotice(candidate)
    local link = "|cff33ff99|H" .. LINK_PREFIX .. candidate.version .. "|h[" .. candidate.version .. "]|h|r"
    addon.Logger.Info(addon.L("UPDATE_AVAILABLE", link))
    showNotes(candidate.version, candidate.notes)
end

schedule = function()
    if scheduled or sessionNotified or not addon.SpellCreationSettings.ShouldNotifyUpdates() then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        scheduled = true
        C_Timer.After(math.max(0, readyAt - addon.Runtime.GetMonotonicTime()), notify)
    end
end

local function onPeer(peer)
    if sessionNotified and worldHandled or type(peer) ~= "table" then return end
    local _, id = addon.Runtime.NormalizeFullPlayerID(peer.playerID)
    local api = _G.TRP3_API
    local _, own = addon.Runtime.NormalizeFullPlayerID(api and api.globals and api.globals.player_id)
    if not id or #id > 256 or id == own then return end
    local parts, version = parse(peer.addonVersion)
    if not parts then
        if peers[id] then peers[id], peerCount = nil, peerCount - 1 end
        return
    end
    bestCandidate()
    if not peers[id] then
        if peerCount >= addon.Constants.COMMUNICATION_MAX_PEERS then
            local oldest
            for key, value in pairs(peers) do
                if not oldest or value.seen < peers[oldest].seen then oldest = key end
            end
            peers[oldest], peerCount = nil, peerCount - 1
        end
        peerCount = peerCount + 1
    end
    local notes = addon.ReleaseNotes.Copy(peer.releaseNotes)
    peers[id] = { parts = parts, version = version, seen = addon.Runtime.GetMonotonicTime(),
        notes = notes, notesKey = addon.ReleaseNotes.Key(notes) }
    if bestCandidate() then schedule() end
end

local function applyWorldEntry()
    if not worldEntry or worldHandled then return end
    worldHandled = true
    if worldEntry.initialLogin then
        sessionNotified = false
        local settings = savedSettings()
        if settings then settings.versionCheckSessionNotified = nil end
    end
    if worldEntry.initialLogin or worldEntry.reload or not enteredWorld then
        readyAt = worldEntry.at + constants.VERSION_CHECK_LOGIN_DELAY
    end
    enteredWorld = true
end

function check.Initialize()
    if initialized then return end
    initialized = true
    readyAt = addon.Runtime.GetMonotonicTime() + constants.VERSION_CHECK_LOGIN_DELAY
    enteredWorld = type(IsLoggedIn) == "function" and IsLoggedIn()
    local settings = savedSettings()
    sessionNotified = settings and settings.versionCheckSessionNotified == true
    applyWorldEntry()
    local history = settings and settings.versionCheckNotes
    for index = 1, constants.VERSION_CHECK_HISTORY_LIMIT do
        local item = type(history) == "table" and history[index]
        local _, version = parse(type(item) == "table" and item.version)
        if version then
            local notes, confirmations = confirmedNotes(item)
            announced:Set(version, { notes = notes, confirmations = confirmations })
        end
    end
    addon.Communication.RegisterPeerListener(onPeer)
    addon.SpellCreationSettings.RegisterListener(function() if bestCandidate() then schedule() end end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, initialLogin, reload)
    if event == "PLAYER_ENTERING_WORLD" and not worldEntry then
        worldEntry = { initialLogin = initialLogin == true, reload = reload == true,
            at = addon.Runtime.GetMonotonicTime() }
    end
    if not initialized then return end
    applyWorldEntry()
    if bestCandidate() then schedule() end
end)
