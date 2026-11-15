local _, addon = ...

addon.VersionCheck = {}
local check = addon.VersionCheck
local constants = addon.Constants
local peers, peerCount = {}, 0
local announced = addon.Cache.NewBounded(constants.VERSION_CHECK_HISTORY_LIMIT)
local initialized, scheduled, sessionNotified, enteredWorld, readyAt, dialog
local worldEntry, worldHandled
local LINK_PREFIX = "addon:rpspellbook:version:"
local previewOwner
local installedScheduled
local HISTORY_REQUEST, HISTORY_RESPONSE = "release_history_request", "release_history_response"
local HISTORY_TIMEOUT = 30
local HISTORY_MAX_PEERS = 5
local pendingHistory, historySerial, nextHistoryReply = nil, 0, 0
local historyReplies = addon.Cache.NewBounded(constants.COMMUNICATION_MAX_PEERS)

local function parse(value)
    if type(value) ~= "string" or #value > constants.VERSION_CHECK_MAX_VERSION_BYTES then return end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then major, minor = value:match("^(%d+)%.(%d+)$"); patch = "0" end
    if not major then return end
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    if major > 999999 or minor > 999999 or patch > 999999 then return end
    return { major, minor, patch }, string.format("%d.%d.%d", major, minor, patch)
end

function check.GetCurrentVersion()
    local _, version = parse(constants.ADDON_VERSION)
    return version
end

function check.GetCurrentLink()
    local version = check.GetCurrentVersion()
    return version and LINK_PREFIX .. version or nil
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

local function localNotes()
    local parts, version = parse(constants.ADDON_VERSION)
    if not parts then return end
    return addon.ReleaseNotes.Get(constants.ADDON_VERSION) or addon.ReleaseNotes.Get(version)
        or (parts[3] == 0 and addon.ReleaseNotes.Get(string.format("%d.%d", parts[1], parts[2]))) or nil
end

local function linkNotes(version)
    if version == check.GetCurrentVersion() then return localNotes(), true end
    local entry = announced:Get(version)
    if entry then return confirmedNotes(entry), true end
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

local function updateNotesText(version, notes, history, resetScroll)
    local sections = {}
    for _, entry in ipairs(history or {}) do
        local text = addon.ReleaseNotes.GetText(entry.notes)
        if text then sections[#sections + 1] = "|cffffd100v" .. entry.version .. "|r\n" .. text end
    end
    dialog.version = version
    dialog.title:SetText(addon.L("UPDATE_NOTES_TITLE", version))
    if #sections == 0 then sections[1] = addon.ReleaseNotes.GetText(notes) or addon.L("UPDATE_NOTES_EMPTY") end
    local height = 0
    for index, section in ipairs(sections) do
        local label = dialog.sections[index]
        if not label then
            label = addon.UIFactory.CreateLabel(dialog.content, addon.Theme.Fonts.body, "", addon.Theme.Colors.text)
            label:SetWidth(420)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("TOP")
            label:SetWordWrap(true)
            dialog.sections[index] = label
        end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", dialog.content, "TOPLEFT", 0, -height)
        label:SetText(section .. (index < #sections and "\n\n|cff80705a----------------|r\n " or ""))
        label:Show()
        height = height + label:GetStringHeight()
    end
    for index = #sections + 1, #dialog.sections do dialog.sections[index]:Hide() end
    dialog.content:SetHeight(math.max(1, height))
    if resetScroll then dialog.scroll:SetVerticalScroll(0) end
end

local function showNotes(version, notes, history)
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
        local function updateScrolling()
            local overflow = child:GetHeight() > scroll:GetHeight()
            scroll.ScrollBar:SetShown(overflow)
            scroll:EnableMouseWheel(overflow)
            if not overflow then scroll:SetVerticalScroll(0) end
        end
        scroll:HookScript("OnScrollRangeChanged", updateScrolling)
        scroll:HookScript("OnSizeChanged", updateScrolling)
        scroll:HookScript("OnShow", updateScrolling)
        dialog.updateScrolling = updateScrolling
        local close = factory.CreateButton(dialog, addon.L("CLOSE"), 110)
        close:SetPoint("BOTTOMRIGHT", -20, 16)
        close:SetScript("OnClick", function() dialog:Hide() end)
        dialog.text, dialog.content, dialog.scroll = text, child, scroll
        dialog.sections = { text }
    end
    updateNotesText(version, notes, history, true)
    dialog:Show()
    dialog.updateScrolling()
    addon.UIFactory.BringToFront(dialog)
end

local function requestHistory(version, entry)
    local current, after = parse(constants.ADDON_VERSION)
    local target = parse(version)
    local count = requiredReports()
    local notes = confirmedNotes(entry)
    if not notes or (entry.historyConfirmations or 0) >= count or not higher(target, current) or count > HISTORY_MAX_PEERS then return end
    local now = addon.Runtime.GetMonotonicTime()
    if pendingHistory and now < pendingHistory.expires then return end
    local recipients, waiting = {}, {}
    for id, candidate in pairs(peers) do
        local peer = addon.Communication.GetPeer(candidate.playerID)
        local _, peerVersion = parse(peer and peer.addonVersion)
        if peerVersion == version and addon.ReleaseNotes.Same(notes, peer.releaseNotes)
            and addon.Communication.HasCapability(candidate.playerID, constants.VERSION_CHECK_HISTORY_CAPABILITY) then
            recipients[#recipients + 1], waiting[id] = peer.playerID, true
            if #recipients == count then break end
        end
    end
    if #recipients < count then return end
    historySerial = historySerial % 999999 + 1
    local id = string.format("%.0f-%d", math.floor(now * 1000), historySerial)
    pendingHistory = { id = id, version = version, entry = entry, after = after, waiting = waiting,
        expires = now + HISTORY_TIMEOUT, required = count, matches = 0 }
    for _, recipient in ipairs(recipients) do
        addon.Communication.Send(recipient, HISTORY_REQUEST, { id = id, version = version, after = after }, "LOW")
    end
end

local function handleHistoryRequest(payload, sender)
    if type(payload) ~= "table" or not addon.Runtime.IsSafeIdentifier(payload.id, 64) then return end
    local current, version = parse(constants.ADDON_VERSION)
    local after, canonical = parse(payload.after)
    if payload.version ~= version or canonical ~= payload.after or not higher(current, after)
        or not addon.Communication.HasCapability(sender, constants.VERSION_CHECK_HISTORY_CAPABILITY) then return end
    local key = addon.Runtime.NormalizePlayerID(sender)
    local now = addon.Runtime.GetMonotonicTime()
    if now < nextHistoryReply or now < (historyReplies:Get(key) or 0) then return end

    local versions, seen = {}, {}
    for _, name in ipairs(addon.ReleaseNotes.GetVersions()) do
        local parts, normalized = parse(name)
        if parts and not higher(parts, current) and not seen[normalized] then
            versions[#versions + 1] = { name = name, version = normalized, parts = parts }
            seen[normalized] = true
        end
    end
    table.sort(versions, function(left, right) return higher(left.parts, right.parts) end)
    local history = {}
    for index = 1, math.min(#versions, constants.VERSION_CHECK_RELEASE_LIMIT) do
        local release = versions[index]
        if not higher(release.parts, after) then break end
        local notes = addon.ReleaseNotes.Get(release.name)
        if notes then history[#history + 1] = { version = release.version, notes = notes } end
    end
    if not history[1] or history[1].version ~= version then return end
    nextHistoryReply = now + 2
    historyReplies:Set(key, now + HISTORY_TIMEOUT)
    addon.Communication.Send(sender, HISTORY_RESPONSE, { id = payload.id, history = history }, "LOW")
end

local function handleHistoryResponse(payload, sender)
    local pending = pendingHistory
    local _, key = addon.Runtime.NormalizeFullPlayerID(sender)
    if not pending or pending.done or not pending.waiting[key] or type(payload) ~= "table" or payload.id ~= pending.id
        or addon.Runtime.GetMonotonicTime() >= pending.expires or announced:Get(pending.version) ~= pending.entry then return end
    local count = addon.Runtime.GetBoundedArrayLength(payload.history, constants.VERSION_CHECK_RELEASE_LIMIT)
    if not count or count == 0 then return end

    local previous, after = nil, parse(pending.after)
    local history = {}
    for index = 1, count do
        local item = payload.history[index]
        if type(item) ~= "table" then return end
        local parts, version = parse(item.version)
        local notes = addon.ReleaseNotes.Copy(item.notes)
        if version ~= item.version or not higher(parts, after) or not notes
            or (index == 1 and version ~= pending.version) or (previous and not higher(previous, parts)) then return end
        previous = parts
        history[index] = { version = version, notes = notes }
    end
    local latest = confirmedNotes(pending.entry)
    if not latest or not addon.ReleaseNotes.Same(latest, history[1].notes) then return end
    pending.waiting[key] = nil
    if pending.history then
        if #pending.history ~= #history then pending.done = true; return end
        for index, item in ipairs(history) do
            local other = pending.history[index]
            if item.version ~= other.version or not addon.ReleaseNotes.Same(item.notes, other.notes) then
                pending.done = true
                return
            end
        end
    else
        pending.history = history
    end
    pending.matches = pending.matches + 1
    if pending.matches < pending.required or pending.matches < requiredReports() then return end
    pending.done = true
    pending.entry.history, pending.entry.historyConfirmations = history, pending.matches
    if dialog and dialog.version == pending.version and dialog:IsShown() then
        updateNotesText(pending.version, latest, history, false)
        dialog.updateScrolling()
    end
end

function check.PreviewLink(owner, link)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return false end
    if #link > #LINK_PREFIX + constants.VERSION_CHECK_MAX_VERSION_BYTES then return true end
    local version = link:sub(#LINK_PREFIX + 1)
    local notes, known = linkNotes(version)
    if known and GameTooltip then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:SetText(addon.L("UPDATE_NOTES_TITLE", version), 1, 0.82, 0)
        GameTooltip:AddLine(addon.ReleaseNotes.GetText(notes) or addon.L("UPDATE_NOTES_EMPTY"), 1, 1, 1, true)
        GameTooltip:Show()
        previewOwner = owner
    end
    return true
end

function check.HideLinkPreview(owner)
    if previewOwner ~= owner then return end
    if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    previewOwner = nil
end

function check.HandleLink(link, button)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return false end
    if #link > #LINK_PREFIX + constants.VERSION_CHECK_MAX_VERSION_BYTES then return true end
    if button and button ~= "LeftButton" or IsModifiedClick and IsModifiedClick() then return true end
    local version = link:sub(#LINK_PREFIX + 1)
    local notes, known = linkNotes(version)
    if known then
        local entry = version ~= check.GetCurrentVersion() and announced:Get(version) or nil
        local history = notes and entry and (entry.historyConfirmations or 0) >= requiredReports() and entry.history
        showNotes(version, notes, history or nil)
        if entry then requestHistory(version, entry) end
    end
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
    local link = "|cffffff00|H" .. LINK_PREFIX .. candidate.version .. "|h[" .. candidate.version .. "]|h|r"
    addon.Logger.Info(addon.L("UPDATE_AVAILABLE", link))
end

schedule = function()
    if scheduled or sessionNotified or not addon.SpellCreationSettings.ShouldNotifyUpdates() then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        scheduled = true
        C_Timer.After(math.max(0, readyAt - addon.Runtime.GetMonotonicTime()), notify)
    end
end

local function onPeer(peer)
    if type(peer) ~= "table" then return end
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
    peers[id] = { playerID = peer.playerID, parts = parts, version = version, seen = addon.Runtime.GetMonotonicTime(),
        notes = notes, notesKey = addon.ReleaseNotes.Key(notes) }
    if not (sessionNotified and worldHandled) and bestCandidate() then schedule() end
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

local function installedCandidate()
    if not worldHandled then return end
    local settings = savedSettings()
    if not settings then return end
    local current, version = parse(constants.ADDON_VERSION)
    local previous = parse(settings.versionCheckInstalledNotified)
    if not current or previous and not higher(current, previous) then return end
    if not localNotes() then return end
    return settings, version
end

local function scheduleInstalled()
    if installedScheduled or not installedCandidate() then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    installedScheduled = true
    C_Timer.After(math.max(0, worldEntry.at + constants.VERSION_CHECK_LOGIN_DELAY
        - addon.Runtime.GetMonotonicTime()), function()
        installedScheduled = false
        if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
        local settings, version = installedCandidate()
        if not settings then return end
        settings.versionCheckInstalledNotified = version
        local link = "|cffffff00|H" .. LINK_PREFIX .. version .. "|h[v" .. version .. "]|h|r"
        addon.Logger.Info(addon.L("UPDATE_INSTALLED", link))
    end)
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
    addon.Communication.RegisterHandler(HISTORY_REQUEST, handleHistoryRequest)
    addon.Communication.RegisterHandler(HISTORY_RESPONSE, handleHistoryResponse)
    addon.SpellCreationSettings.RegisterListener(function() if bestCandidate() then schedule() end end)
    scheduleInstalled()
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
    scheduleInstalled()
    if bestCandidate() then schedule() end
end)
