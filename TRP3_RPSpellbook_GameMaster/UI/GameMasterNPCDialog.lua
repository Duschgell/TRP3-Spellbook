local _, addon = ...
addon = addon.Shared or addon

addon.GameMasterNPCDialog = {}
local api = addon.GameMasterNPCDialog
local dialog
function api.GetTutorialContext() return dialog end
local refresh
local MAX_NPCS = addon.Constants.GAMEMASTER_MAX_NPCS or 20

local function setError(message)
    dialog.error:SetText(message or "")
end

local function getSession()
    local active = addon.GameMasterService.GetActiveSession()
    if active and active.id == dialog.sessionID then return active end
    return addon.GameMasterStore.GetSession(dialog.sessionID)
end

local function editable()
    return dialog and (dialog.draft ~= nil and addon.GameMasterService.CanControl()
        or dialog.draft == nil and addon.GameMasterService.IsPrimaryGameMaster())
end

local function getActor()
    if dialog.draft or not dialog.actorID then return nil end
    return addon.GameMasterService.GetNPCActor(dialog.actorID, dialog.sessionID)
end

local function mutate(method, ...)
    if not editable() then return false end
    local result, err = addon.GameMasterService[method](...)
    refresh()
    setError(not result and (err or addon.L("GAMEMASTER_NPC_UNAVAILABLE")) or nil)
    return result
end

local function markerOptions()
    local result = { { label = addon.L("GAMEMASTER_NPC_NO_MARKER"), value = 0 } }
    for index = 1, 8 do
        result[#result + 1] = {
            label = addon.GameMasterRoster.GetWorldMarkerLabel(index), value = index,
        }
    end
    return result
end

 
function api.GetRosterEntries(session, round, primary)
    local result = {}
    if not primary then
        local service = addon.GameMasterService
        local current = service.GetActiveRound()
        if not round or not current or round.id ~= current.id then return result end
        for _, entry in ipairs(type(service.GetSharedActions) == "function" and service.GetSharedActions() or {}) do
            if (entry.kind == "npc" or entry.actorKind == "npc") and type(entry.npcProfile) == "table" then
                local actor = {}
                for key, value in pairs(entry.npcProfile) do actor[key] = value end
                actor.id, actor.kind, actor.released = entry.playerKey or entry.playerID, "npc", true
                actor.active, actor.markerIndex = entry.active == true, entry.markerIndex
                actor.side, actor.ownerPlayerKey = entry.side, entry.ownerPlayerKey
                result[#result + 1] = { id = actor.id, actor = actor, submission = entry,
                    active = entry.active == true, completed = entry.completed == true }
            end
        end
        return result
    end
    local actionRound = addon.GameMasterVisibility.GetNPCActionRound(session, round)
    for _, id in ipairs(session and session.npcOrder or {}) do
        local actor = session.npcActors and session.npcActors[id]
        if actor and (primary or actor.released == true) then
            local actorRound = actor.side == "players" and round or actionRound
            result[#result + 1] = {
                id = id, actor = actor,
                submission = actorRound and actorRound.npcSubmissions and actorRound.npcSubmissions[id],
                active = addon.GameMasterNPCActors.IsTurnActive(session, round, id),
                completed = addon.GameMasterNPCActors and addon.GameMasterNPCActors.IsCompleted
                    and addon.GameMasterNPCActors.IsCompleted(session, actorRound, actor)
                    or actor.side ~= "players" and actorRound and actorRound.npcCompletedTurns
                        and actorRound.npcCompletedTurns[id] == true or false,
            }
        end
    end
    return result
end

local function layout()
    if not dialog then return end
    local width = math.max(480, dialog:GetWidth())
    dialog.picker:SetWidth(width - 150)
    dialog.spell:SetWidth(width - 154)
    dialog.list:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, dialog.draft and 52 or 272)
    dialog.content:SetWidth(math.max(1, width - 36))
    for _, row in ipairs(dialog.rows) do row:SetWidth(math.max(1, width - 36)) end
    addon.GameMasterWidgets.ClampScroll(dialog.list, dialog.content:GetHeight())
end

local function refreshDetails()
    local actor = getActor()
    dialog.details:SetShown(not dialog.draft and actor ~= nil)
    if not actor then return end
    dialog.selectedName:SetText(actor.name)
    addon.UIFactory.SetFontColor(dialog.selectedName, actor.nameColor, addon.Theme.Colors.text)
    dialog.release:SetText(addon.L(actor.released and "GAMEMASTER_NPC_HIDE" or "GAMEMASTER_NPC_RELEASE"))
    dialog.release:SetEnabled(editable())
    dialog.marker:SetOptions(markerOptions(), actor.markerIndex or 0)
    dialog.marker:SetValue(actor.markerIndex or 0, true)
    dialog.marker:SetEnabled(editable())
    local session = getSession()
    dialog.side:SetOptions({ { label = addon.L("GAMEMASTER_NPC_ALLY"), value = "players" },
        { label = addon.L("GAMEMASTER_NPC_ENEMY"), value = "enemies" } }, actor.side or "enemies")
    local owners = {}
    local seenOwners, ownerNames = {}, {}
    local function addOwner(key, participant)
        if not key or seenOwners[key] then return end
        participant = participant or {}
        local name = participant.rpName or participant.playerID or key
        seenOwners[key], ownerNames[key] = true, name
        owners[#owners + 1] = { value = key, label = addon.L("GAMEMASTER_NPC_OWNER") .. ": " .. name }
    end
    for _, key in ipairs(session and session.participantOrder or {}) do
        addOwner(key, session.participants[key])
    end
    if session then addOwner(session.ownerKey, session.participants and session.participants[session.ownerKey]) end
     
    if session and not session.currentRoundID then
        for _, member in ipairs(addon.GameMasterRoster.GetMembers and addon.GameMasterRoster.GetMembers() or {}) do
            addOwner(member.playerKey, member)
        end
    end
    dialog.owner:SetOptions(owners, actor.ownerPlayerKey or session and session.ownerKey)
    dialog.owner:SetEnabled(editable() and actor.side == "players")
    local companions = { { label = addon.L(actor.companionGUID and "GAMEMASTER_NPC_UNBIND_COMPANION"
        or "GAMEMASTER_NPC_COMPANION"), value = "none" } }
    local foundBinding, available = false, false
    local candidates = addon.GameMasterService.GetNPCCompanions
        and addon.GameMasterService.GetNPCCompanions(dialog.sessionID)
        or addon.GameMasterRoster.GetCompanions and addon.GameMasterRoster.GetCompanions() or {}
    for _, candidate in ipairs(candidates) do
        companions[#companions + 1] = { label = candidate.name .. " ("
            .. (ownerNames[candidate.ownerPlayerKey] or candidate.ownerPlayerKey) .. ")", value = candidate.guid }
        available = true
        if candidate.guid == actor.companionGUID then foundBinding = true end
    end
    if actor.companionGUID and not foundBinding then
        companions[#companions + 1] = { label = actor.name .. " ("
            .. addon.L("GAMEMASTER_NPC_NO_COMPANION") .. ")", value = actor.companionGUID }
    end
    dialog.companion:SetOptions(companions, actor.companionGUID or "none")
    dialog.companion:SetEnabled(editable() and (available or actor.companionGUID ~= nil))
    local options = {}
    for _, spell in ipairs(actor.spells or {}) do
        options[#options + 1] = { label = spell.name, value = spell.id, icon = spell.icon, color = spell.nameColor }
    end
    local selected = dialog.spell:GetValue()
    dialog.spell:SetOptions(options, selected)
    local context = addon.GameMasterService.GetNPCSubmissionContext(actor.id)
    local sameSession = context and context.sessionID == dialog.sessionID
    dialog.cast:SetEnabled(editable() and sameSession and #options > 0
        and addon.GameMasterService.CanSubmitNPC(actor.id))
    local round = addon.GameMasterService.GetActiveRound()
    local session = getSession()
    local independent = session and addon.GameMasterNPCActors.HasIndependentTurn(session, actor)
    local completed = session and addon.GameMasterNPCActors.IsCompleted(session, round, actor)
    dialog.complete:SetText(addon.L(completed
        and "GAMEMASTER_NPC_TURN_UNDO" or "GAMEMASTER_NPC_TURN_DONE"))
    dialog.complete:SetEnabled(editable() and session and session.id == dialog.sessionID
        and independent and addon.GameMasterNPCActors.IsTurnActive(session, round, actor.id))
    dialog.completed = completed == true
    dialog.remove:SetEnabled(editable() and session ~= nil and session.currentRoundID == nil)
    dialog.state:SetText(addon.L(actor.side == "players" and not independent and "GAMEMASTER_NPC_LINKED_TURN" or sameSession and "GAMEMASTER_NPC_CONTROL_HINT"
        or "GAMEMASTER_NPC_ENEMY_ONLY"))
end

refresh = function()
    if not dialog or not dialog:IsShown() or dialog.refreshing then return end
    if not editable() then dialog:Hide(); return end
    dialog.refreshing = true
    local archive = addon.NPCArchive
    local identities = archive and type(archive.List) == "function" and archive.List() or {}
    local options, byID = {}, {}
    for _, npc in ipairs(identities) do
        options[#options + 1] = { label = npc.name, value = npc.id, icon = npc.icon,
            creatureID = npc.id, color = npc.nameColor }
        byID[npc.id] = npc
    end
    dialog.picker:SetOptions(options, dialog.picker:GetValue())
    local actors = {}
    if dialog.draft then
        for index, templateID in ipairs(dialog.draft) do
            local profile = byID[templateID] or { name = addon.L("GAMEMASTER_NPC_MISSING") }
            actors[index] = { id = index, name = profile.name, icon = profile.icon, templateID = templateID,
                nameColor = profile.nameColor, released = false }
        end
    else
        local session = getSession()
        if not session then dialog.refreshing = nil; dialog:Hide(); return end
        actors = addon.GameMasterService.ListNPCs(dialog.sessionID) or {}
    end
    local selectedExists = false
    for _, actor in ipairs(actors) do if actor.id == dialog.actorID then selectedExists = true end end
    if not selectedExists then dialog.actorID = actors[1] and actors[1].id or nil end
    dialog.add:SetEnabled(#options > 0 and #actors < MAX_NPCS)
    dialog.help:SetText(addon.L(#options == 0 and "GAMEMASTER_NPC_ARCHIVE_EMPTY"
        or (dialog.draft and "GAMEMASTER_NPC_DRAFT_HINT" or "GAMEMASTER_NPC_REGISTER_HINT")))
    for index, row in ipairs(dialog.rows) do
        local actor = actors[index]
        row.actor = actor
        row:SetShown(actor ~= nil)
        if actor then
            row.label:SetText(tostring(index) .. ". " .. actor.name)
            addon.UIFactory.SetFontColor(row.label, actor.nameColor, addon.Theme.Colors.text)
            addon.UIFactory.SetIconTexture(row.icon, actor.icon, addon.Constants.DEFAULT_BOOK_ICON)
            addon.UIFactory.SetNPCPortrait(row, row.icon, actor.templateID, actor.icon, 20)
            row.status:SetText(addon.L(actor.released and "GAMEMASTER_NPC_VISIBLE" or "GAMEMASTER_NPC_HIDDEN"))
            row:SetAlpha((actor.released or dialog.draft) and 1 or 0.55)
            row:LockHighlight()
            if actor.id ~= dialog.actorID then row:UnlockHighlight() end
        end
    end
    dialog.content:SetHeight(math.max(1, #actors * 30))
    dialog.undo:SetShown(dialog.draft ~= nil)
    dialog.undo:SetEnabled(dialog.draft ~= nil and #actors > 0)
    refreshDetails()
    layout()
    dialog.list:UpdateScrollChildRect()
    dialog.refreshing = nil
end

local function createDialog()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(addon.L("GAMEMASTER_NPC_TITLE"), 600, 500)
    frame:SetResizable(true)
    if type(frame.SetResizeBounds) == "function" then frame:SetResizeBounds(480, 400, 1000, 900) end
    local picker = addon.GameMasterWidgets.CreateSelector(frame, 450, addon.L("GAMEMASTER_NPC_SELECT"))
    picker:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -43)
    local add = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_NPC_ADD"), 110)
    add:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -43)
    local help = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.textMuted)
    help:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -7)
    help:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    help:SetHeight(28)
    help:SetWordWrap(true)
    local list = addon.GameMasterWidgets.CreateScrollViewport(frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -105)
    local content = CreateFrame("Frame", nil, list)
    content:SetSize(560, 1)
    list:SetScrollChild(content)
    local rows = {}
    for index = 1, MAX_NPCS do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(560, 28)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 30))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.label = addon.UIFactory.CreateLabel(row, theme.Fonts.body, "", theme.Colors.text)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -92, 0)
        row.label:SetWordWrap(false)
        row.status = addon.UIFactory.CreateLabel(row, theme.Fonts.small, "", theme.Colors.textMuted)
        row.status:SetPoint("RIGHT", row, "RIGHT", -3, 0)
        row.status:SetWidth(85)
        row.status:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.actor then frame.actorID = self.actor.id; refresh(); setError(nil) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.actor then addon.GameMasterNPCTooltip.Show(self, self.actor) end
        end)
        row:SetScript("OnLeave", function(self) addon.GameMasterNPCTooltip.Hide(self) end)
        rows[index] = row
    end
    local details = CreateFrame("Frame", nil, frame)
    details:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 48)
    details:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 48)
    details:SetHeight(212)
    local selectedName = addon.UIFactory.CreateLabel(details, theme.Fonts.body, "", theme.Colors.text)
    selectedName:SetPoint("TOPLEFT", details, "TOPLEFT", 0, 0)
    selectedName:SetPoint("RIGHT", details, "RIGHT", 0, 0)
    selectedName:SetWordWrap(false)
    local release = addon.UIFactory.CreateButton(details, "", 126)
    release:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -23)
    local marker = addon.GameMasterWidgets.CreateSelector(details, 170)
    marker:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, -23)
    local spell = addon.GameMasterWidgets.CreateSelector(details, 446, addon.L("GAMEMASTER_NPC_ABILITY"))
    spell:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -51)
    local cast = addon.UIFactory.CreateButton(details, addon.L("GAMEMASTER_NPC_CAST"), 112)
    cast:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, -51)
    local complete = addon.UIFactory.CreateButton(details, "", 176)
    complete:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -79)
    local remove = addon.UIFactory.CreateButton(details, addon.L("GAMEMASTER_NPC_REMOVE"), 112)
    remove:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, -79)
    local state = addon.UIFactory.CreateLabel(details, theme.Fonts.small, "", theme.Colors.textMuted)
    state:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -106)
    state:SetPoint("RIGHT", details, "RIGHT", 0, 0)
    state:SetWordWrap(true)
    local side = addon.GameMasterWidgets.CreateSelector(details, 180)
    side:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -51)
    local owner = addon.GameMasterWidgets.CreateSelector(details, 310)
    owner:SetPoint("LEFT", side, "RIGHT", 8, 0)
    owner:SetPoint("RIGHT", details, "RIGHT", 0, 0)
    local companion = addon.GameMasterWidgets.CreateSelector(details, 440)
    companion:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -79)
    companion:SetPoint("RIGHT", details, "RIGHT", 0, 0)
    spell:ClearAllPoints(); spell:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -107)
    cast:ClearAllPoints(); cast:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, -107)
    complete:ClearAllPoints(); complete:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -135)
    remove:ClearAllPoints(); remove:SetPoint("TOPRIGHT", details, "TOPRIGHT", 0, -135)
    state:ClearAllPoints(); state:SetPoint("TOPLEFT", details, "TOPLEFT", 0, -162)
    state:SetPoint("RIGHT", details, "RIGHT", 0, 0)
    local close = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_NPC_CLOSE"), 90)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 15)
    close:SetScript("OnClick", function() frame:Hide() end)
    local undo = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_NPC_REMOVE"), 112)
    undo:SetPoint("RIGHT", close, "LEFT", -8, 0)
    local errorLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.error)
    errorLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 18)
    errorLabel:SetPoint("RIGHT", undo, "LEFT", -8, 0)
    errorLabel:SetWordWrap(true)
    errorLabel:SetHeight(28)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(14, 14)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    frame:SetScript("OnSizeChanged", layout)
    for _, event in ipairs({ "UNIT_PET", "COMPANION_UPDATE", "PET_JOURNAL_LIST_UPDATE", "GROUP_ROSTER_UPDATE" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function()
        if frame:IsShown() and not frame.draft then refresh() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        if frame.draft or not frame:IsShown() then return end
        frame.companionElapsed = (frame.companionElapsed or 0) + elapsed
        if frame.companionElapsed < 5 then return end
        frame.companionElapsed = 0
        if addon.GameMasterService.RequestNPCCompanions then
            addon.GameMasterService.RequestNPCCompanions(frame.sessionID)
        end
        refresh()
    end)
    frame:HookScript("OnHide", function()
        frame:StopMovingOrSizing()
        addon.GameMasterNPCTooltip.Hide()
    end)
    frame.picker, frame.add, frame.help = picker, add, help
    frame.list, frame.content, frame.rows = list, content, rows
    frame.details, frame.selectedName, frame.release, frame.marker = details, selectedName, release, marker
    frame.side, frame.owner, frame.companion = side, owner, companion
    side:SetOnValueChanged(function(value)
        if frame.refreshing then return end
        local actor, session = getActor(), getSession()
        if actor and session then mutate("SetNPCController", actor.id, value,
            value == "enemies" and session.ownerKey or actor.ownerPlayerKey or session.ownerKey, frame.sessionID) end
    end)
    owner:SetOnValueChanged(function(value)
        if frame.refreshing then return end
        local actor = getActor()
        if actor then mutate("SetNPCController", actor.id, actor.side or "enemies", value, frame.sessionID) end
    end)
    companion:SetOnValueChanged(function(value)
        if frame.refreshing then return end
        local actor = getActor()
        if actor and value == "none" and actor.companionGUID then
            mutate("AssignNPCCompanion", actor.id, nil, frame.sessionID)
        elseif actor and value ~= "none" and value ~= actor.companionGUID then
            mutate("AssignNPCCompanion", actor.id, value, frame.sessionID)
        elseif actor then
            refresh()
        end
    end)
    frame.spell, frame.cast, frame.complete, frame.remove = spell, cast, complete, remove
    frame.undo, frame.error, frame.state = undo, errorLabel, state
    add:SetScript("OnClick", function()
        if not editable() or not picker:GetValue() then return end
        if frame.draft then
            if #frame.draft >= MAX_NPCS then return end
            frame.draft[#frame.draft + 1] = picker:GetValue()
            frame.actorID = #frame.draft
            if frame.onDraftChanged then frame.onDraftChanged() end
            refresh()
        else
            local actor, err = addon.GameMasterService.AddNPCToSession(picker:GetValue(), frame.sessionID)
            if not actor then setError(err or addon.L("GAMEMASTER_NPC_UNAVAILABLE")); return end
            frame.actorID = actor.id
            refresh()
        end
        setError(nil)
    end)
    undo:SetScript("OnClick", function()
        if frame.draft and frame.actorID then
            table.remove(frame.draft, frame.actorID)
            if frame.onDraftChanged then frame.onDraftChanged() end
            refresh()
        end
    end)
    release:SetScript("OnClick", function()
        local actor = getActor()
        if actor then mutate("SetNPCReleased", actor.id, not actor.released, frame.sessionID) end
    end)
    marker:SetOnValueChanged(function(index)
        if frame.refreshing then return end
        local actor = getActor()
        if actor then mutate("SetNPCMarker", actor.id, index ~= 0 and index or nil, frame.sessionID) end
    end)
    cast:SetScript("OnClick", function()
        local actor = getActor()
        if not editable() or not actor then return end
        for _, ability in ipairs(actor.spells or {}) do
            if ability.id == spell:GetValue() then
                local opened = addon.GameMasterActionDialog.Open(ability,
                    { npcActorID = actor.id, npcSessionID = frame.sessionID })
                if not opened then setError(addon.L("GAMEMASTER_NPC_ENEMY_ONLY")) end
                return
            end
        end
    end)
    complete:SetScript("OnClick", function()
        local actor = getActor()
        local context = actor and addon.GameMasterService.GetNPCSubmissionContext(actor.id)
        if context and context.sessionID == frame.sessionID then
            mutate("SetNPCTurnCompleted", actor.id, not frame.completed)
        else
            setError(addon.L("GAMEMASTER_NPC_CONTEXT_CHANGED"))
        end
    end)
    remove:SetScript("OnClick", function()
        local actor = getActor()
        if not actor or not editable() then return end
        local actorID, sessionID, revision, guid = actor.id, frame.sessionID, actor.revision, actor.companionGUID
        addon.UIFactory.ShowConfirmation(addon.L("GAMEMASTER_NPC_REMOVE"),
            addon.L("GAMEMASTER_NPC_REMOVE_CONFIRM", actor.name), function()
                local current = addon.GameMasterService.GetNPCActor(actorID, sessionID)
                if dialog:IsShown() and dialog.sessionID == sessionID and not dialog.draft
                    and current and current.revision == revision and current.companionGUID == guid then
                    mutate("RemoveNPC", actorID, sessionID)
                end
            end)
    end)
    return frame
end

function api.Open(sessionID, actorID)
    local service = addon.GameMasterService
    if not service.IsPrimaryGameMaster() or type(service.ListNPCs) ~= "function" then return false end
    local session = service.GetActiveSession()
    sessionID = sessionID or (session and session.id)
    if not sessionID then return false end
    dialog = dialog or createDialog()
    dialog.draft, dialog.onDraftChanged = nil, nil
    dialog.sessionID, dialog.actorID = sessionID, actorID
    dialog.companionElapsed = 0
    if service.RequestNPCCompanions then service.RequestNPCCompanions(sessionID) end
    dialog:Show()
    refresh()
    setError(nil)
    addon.UIFactory.BringToFront(dialog)
    return true
end

function api.OpenDraft(ids, onChanged)
    if type(ids) ~= "table" or not addon.GameMasterService.CanControl() then return false end
    dialog = dialog or createDialog()
    dialog.sessionID, dialog.actorID = nil, nil
    dialog.draft, dialog.onDraftChanged = ids, onChanged
    dialog:Show()
    refresh()
    setError(nil)
    addon.UIFactory.BringToFront(dialog)
    return true
end

function api.HideDraft(ids)
    if dialog and dialog.draft == ids then dialog:Hide() end
end

local refreshReasons = {
    npcs = true, companions = true, submission = true, phase = true, round = true,
    started = true, stopped = true, suspended = true, recoveryDiscarded = true, assistants = true,
}
local refreshPending = false
addon.GameMasterService.RegisterListener(function(reason)
    if not refreshReasons[reason] or not dialog or not dialog:IsShown() or dialog.draft or refreshPending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        refreshPending = true
        C_Timer.After(0, function()
            refreshPending = false
            if dialog and dialog:IsShown() and not dialog.draft then refresh() end
        end)
    else
        refresh()
    end
end)
