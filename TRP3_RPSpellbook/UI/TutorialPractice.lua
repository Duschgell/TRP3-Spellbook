local _, addon = ...
local practice = {}
addon.TutorialPractice = practice
local state, suspended, navigationSuspended
local modules = {
    control = "GameMasterWindow", overview = "GameMasterSharedActions",
    book = "GameMasterCompactSpellbook", action = "GameMasterActionStatus",
    dialog = "GameMasterActionDialog", scene = "GameMasterSceneSettingsDialog",
    npc = "GameMasterNPCDialog", largeBook = "SpellbookWindow",
}
local serial = 0
local listening = false

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local replayKeys = { "role", "round", "roundStatus", "actions", "completed", "created", "finished",
    "initialOrder", "initialVisibility", "visibilityChanges", "rosterKey", "markerActorID",
    "readSpell", "minimized", "restored", "mocksEnabled", "allowFinish" }

local function rememberRound()
    if not state then return end
    local round = addon.GameMasterService.GetActiveRound()
    if round then state.round, state.roundStatus = round.number, round.status end
end

local function frame(key)
    local module = addon[modules[key]]
    return module and module.GetTutorialContext and module.GetTutorialContext()
end

local function open(key)
    local module = addon[modules[key]]
    if module and module.Open then return module.Open(true) end
end

local function makeBook()
    serial = serial + 1
    local spells, ids = {}, {}
    for i, id in ipairs({ "spark", "shield", "ritual", "heal" }) do
        local spell = i == 1 and addon.TutorialExamples.ForPlayer() or addon.TutorialExamples.ForPractice(id)
        spell.id, spell.revision = "tutorial_" .. id, 1
        spell.description = addon.L("TUTORIAL_PRACTICE_" .. id:upper())
        spells[spell.id], ids[i] = spell, spell.id
    end
    return { id = "tutorial_book_" .. serial, profileKey = "tutorial", revision = 1,
        spells = spells, favorites = {}, tabOrder = { "tutorial" },
        tabs = { tutorial = { id = "tutorial", name = addon.L("TUTORIAL_TITLE"), spellIds = ids } } }
end

function practice.GetWindows()
    local result = {}
    if not state then return result end
    for key in pairs(modules) do
        local window = frame(key)
        if window and window:IsShown() then result[#result + 1] = window end
    end
    return result
end

function practice.Open(role)
    if state then return false end
    local service = addon.GameMasterService
    local previous = {}
    for key in pairs(modules) do
        local window = frame(key)
        previous[key] = window and window:IsShown() or false
    end
    addon.GameMasterCompactSpellbook.SetTutorialFilters(true)
    if not service.BeginTutorial(role, makeBook()) then
        addon.GameMasterCompactSpellbook.SetTutorialFilters(false)
        return false
    end
    state = { role = role, previous = previous, actions = {}, completed = {}, round = 1,
        created = role == "player", visibilityChanges = 0 }
    if not listening then
        service.RegisterListener(rememberRound)
        listening = true
    end
    addon.TRP3Bridge.CloseMainFrame()
    if role == "gm" then
        if not addon.GameMasterSceneSettingsDialog.OpenCreate(addon.L("TUTORIAL_SCENE_NAME"), nil,
            { enemyPhases = false, gmParticipates = true }) then
            practice.Close(); return false
        end
    else
        open("book"); open("overview"); open("action")
    end
    suspended, navigationSuspended = false, false
    return true
end

function practice.GetState()
    if not state then return nil end
    local service = addon.GameMasterService
    local tutorial = service.GetTutorialState()
    if not tutorial then return nil end
    local session, round = service.GetActiveSession(), service.GetActiveRound()
    rememberRound()
    state.created, state.finished = session ~= nil, tutorial.finished == true
    local scene = frame("scene")
    state.interrupted = state.finished and not state.allowFinish
        or (state.role == "gm" and not session and not state.finished and not (scene and scene:IsShown()))
    if session then
        state.session = session
        local order = table.concat(session.participantOrder, ":")
        state.initialOrder = state.initialOrder or order
        state.reordered = order ~= state.initialOrder
        local visibility = service.GetVisibility()
        state.initialVisibility = state.initialVisibility or visibility
        state.visibilityChanges = visibility ~= state.initialVisibility and 1 or state.visibilityChanges
    end
    if round then
        state.phase, state.locked = round.phase, round.status == "locked"
        state.round = round.number
        local context = service.GetSubmissionContext()
        local action = context and addon.GameMasterActionCollection.GetLatest(context.lastSubmission)
        if action then
            state.actions[round.number] = { spell = action.spell.id, preparing = action.action == "prepare",
                released = action.spell.id == "tutorial_ritual" and action.action ~= "prepare",
                hasTarget = type(action.targets) == "table" and #action.targets > 0 }
        end
        local actions = addon.GameMasterActionCollection.Get(context and context.lastSubmission)
        state.currentActions, state.actionCount = actions, #actions
        state.hasChannel, state.hasHealing, state.hasAOE = false, false, false
        for _, entry in ipairs(actions) do
            state.hasChannel = state.hasChannel or entry.action == "channel"
            state.hasHealing = state.hasHealing or entry.spell.effects and entry.spell.effects.healing == true
            state.hasAOE = state.hasAOE or #(entry.targets or {}) >= 2
        end
        state.completed[round.number] = service.GetTurnState().completed == true
        state.isNext = service.GetTurnState().isNext == true
        state.mocksDone = true
        for _, key in ipairs(session.participantOrder) do
            if key ~= session.ownerKey and addon.GameMasterStore.IsParticipantTurnActive(session, round, key)
                and not addon.GameMasterStore.IsTurnCompleted(round, key) then state.mocksDone = false end
        end
        state.buffCounts = { buff = 0, debuff = 0 }
        for _, effect in ipairs(service.GetActiveBuffsForPlayer(session.ownerID)) do
            local kind = effect.spell and effect.spell.effects and effect.spell.effects.debuff and "debuff" or "buff"
            state.buffCounts[kind] = state.buffCounts[kind] + 1
        end
    end
    local dialog, _, selected = addon.GameMasterActionDialog.GetTutorialContext()
    state.target = dialog and not dialog.npcActorID and selected and selected.id == "tutorial_spark"
        and addon.GameMasterActionDialog.GetTutorialTarget()
        or (state.actions[1] and state.actions[1].spell == "tutorial_spark" and state.actions[1].hasTarget and true or nil)
    local target = frame(state.role == "gm" and "control" or "overview")
    if target then
        local minimized = target.windowMinimized or target.appliedCollapsed
        if minimized then state.minimized = true
        elseif state.minimized then state.restored = true end
    end
    return state
end

function practice.GetFrame() return nil end

function practice.GetAnchor(key)
    if not state then return nil end
    local dialog = frame("dialog")
    local control = frame("control")
    if key == "large_spell" then
        local large = frame("largeBook")
        return large and large.panel and large.panel.spellSlots and large.panel.spellSlots[1]
    elseif key == "exclude" or key == "read_spell" or key == "played" or key == "buff" or key == "debuff" then
        local session = addon.GameMasterService.GetActiveSession()
        for _, row in ipairs(control and control.rows or {}) do
            if row:IsShown() then
                if key == "exclude" and row.playerKey == (state.rosterKey or session and session.participantOrder[1]) then
                    return row.activeToggle
                elseif key == "played" then return row.nameButton or row.name
                elseif key == "read_spell" and row.submission then
                    local button = row.actionList and row.actionList.views and row.actionList.views[1]
                    button = button and button.spell or row.spellButton
                    if button and button.HookScript and not button.tutorialReadHook then
                        button.tutorialReadHook = true
                        button:HookScript("OnEnter", function()
                            local run = addon.Onboarding and addon.Onboarding.GetActive()
                            local current = run and run.tour.steps[run.index]
                            if state and current and current.id == "read_spell" and row:IsVisible() and row.submission then
                                state.readSpell = true
                            end
                        end)
                    end
                    return button
                elseif (key == "buff" or key == "debuff") and row.playerKey == session.ownerKey then
                    for _, button in ipairs(row.buffButtons or {}) do
                        local effect = button.entry and button.entry.spell and button.entry.spell.effects
                        if effect and (effect.debuff and "debuff" or "buff") == key then return button end
                    end
                end
            end
        end
        return nil
    elseif key == "aoe" then
        if not dialog or not dialog:IsShown() then return practice.GetAnchor("spark") end
        if not dialog.aoeCheck:GetChecked() then return dialog.aoeCheck end
        local _, targets = addon.GameMasterActionDialog.GetTutorialContext()
        if targets and #targets >= 2 then return dialog.submitButton end
        return practice.GetAnchor("target")
    elseif key == "emote" then return dialog and dialog.emoteCheck
    elseif key == "action_kind" then return dialog and dialog.actionSelector
    elseif key == "multi" then return dialog and dialog:IsShown() and dialog.addActionButton or practice.GetAnchor("heal")
    elseif key == "buffs" then local action = frame("action"); return action and action.buffContainer or action
    elseif key == "incoming" then local action = frame("action"); return action and action.body or action
    elseif key == "lock" then return control and control.lockRound
    elseif key:sub(1, 4) == "npc_" then
        local npc = frame("npc")
        return npc and npc[key:sub(5)]
    end
    if key == "scene" then
        local scene = frame("scene")
        return scene and scene.saveButton
    elseif key == "target" then
        if not dialog or not dialog:IsShown() then return practice.GetAnchor("spark") end
        if dialog.targetTypeSelector:GetValue() ~= "player" then return dialog.targetTypeSelector end
        return dialog.aoeCheck:GetChecked() and dialog.addTarget or dialog.playerSelector
    elseif key == "cast" then
        return dialog and dialog:IsShown() and dialog.submitButton
            or practice.GetAnchor(state.round >= 2 and "ritual" or "spark")
    elseif key == "turn" then local action = frame("action"); return action and action.turnCompleted
    elseif key == "visibility" then return control and control.visibilityButton
    elseif key == "advance" or key == "finish" then
        return control and (key == "finish" and control.stopButton or control.startRound)
    elseif key == "order" then
        if control and addon.GameMasterStore.IsOrderLocked() then return control.orderLock end
        return control and control.rows and control.rows[2] and control.rows[2].moveUp
    elseif key == "spark" or key == "ritual" or key == "shield" or key == "heal" then
        local _, _, selected = addon.GameMasterActionDialog.GetTutorialContext()
        if key == "ritual" and dialog and dialog:IsShown() and selected and selected.id == "tutorial_ritual" then
            local action = state.round >= 2 and "cast" or "prepare"
            return dialog.actionSelector:GetValue() == action and dialog.submitButton or dialog.actionSelector
        end
        local book = frame("book")
        for _, row in ipairs(book and book.rows or {}) do
            if row.spell and row.spell.id == "tutorial_" .. key and row:IsVisible() then return row end
        end
        return nil
    end
    return frame(key)
end

local function targetVisible(target)
    if addon.TutorialView and addon.TutorialView.IsTargetVisible then return addon.TutorialView.IsTargetVisible(target) end
    return target ~= nil and target:IsVisible()
end

local function blocked(key, anchor, recover)
    return { blocked = true, key = key, anchor = anchor, recover = recover }
end

function practice.ResolveNavigation(key, context, current)
    if not state or not addon.GameMasterService.IsTutorialActive() then return blocked("TUTORIAL_PRACTICE_INTERRUPTED") end
    if type(key) ~= "string" then return blocked("TUTORIAL_FIND_CONTROL") end
    local spellKeys = { spark = true, ritual = true, heal = true, shield = true }
    local dialogKeys = { target = true, cast = true, emote = true, action_kind = true, multi = true, aoe = true }
    local expected = ({ prepare = "ritual", release = "ritual", channel = "spark", multi = "heal" })[current.id] or "spark"
    if dialogKeys[key] or spellKeys[key] then
        local dialog, _, selected = addon.GameMasterActionDialog.GetTutorialContext()
        if dialog and dialog:IsVisible() and (dialogKeys[key] or key == "ritual") then
            if not dialog.npcActorID and selected and selected.id == "tutorial_" .. expected then
                local target = practice.GetAnchor(key)
                if targetVisible(target) then return { anchor = target } end
            end
        elseif spellKeys[key] then
            local target = practice.GetAnchor(key)
            if targetVisible(target) then return { anchor = target } end
        end
        local navigation = practice.ResolveNavigation("book", context, current)
        if navigation.blocked then return navigation end
        local target = practice.GetAnchor(expected)
        if targetVisible(target) then return blocked("TUTORIAL_OPEN_PRACTICE_ABILITY", target) end
        local book, filters = addon.GameMasterCompactSpellbook.GetTutorialContext()
        if filters and filters.actorID then return blocked("TUTORIAL_PRACTICE_BOOK", book) end
        if book.searchBox and book.searchBox:GetText():match("%S") then
            return blocked("TUTORIAL_FIND_SEARCH", book.searchBox)
        end
        if filters and filters.favoritesOnly then return blocked("TUTORIAL_FIND_FAVORITES", book.favoriteFilter) end
        return blocked("TUTORIAL_FIND_PRACTICE_ENTRY", book.listViewport or book)
    end
    local moduleKey = ({ turn = "action", buffs = "action", incoming = "action", large_spell = "largeBook",
        exclude = "control", read_spell = "control", played = "control", buff = "control", debuff = "control",
        lock = "control", visibility = "control", advance = "control", finish = "control", order = "control" })[key]
        or (key:sub(1, 4) == "npc_" and "npc" or key)
    local window = frame(moduleKey)
    if not window or not window:IsVisible() then
        local recover
        if moduleKey == "book" or moduleKey == "overview" or moduleKey == "action" or moduleKey == "control" then
            recover = function() return open(moduleKey) end
        elseif moduleKey == "largeBook" then recover = practice.OpenLargeBook end
        if moduleKey == "npc" and window and not window.draft then
            local session = addon.GameMasterService.GetActiveSession()
            local actorID = context.actorID or state.markerActorID
            if window.sessionID == (session and session.id)
                and (key == "npc_add" and window.picker:GetValue() == context.npcID
                    or key ~= "npc_add" and actorID ~= nil and window.actorID == actorID) then
                recover = function()
                    local live = addon.GameMasterService.GetActiveSession()
                    if window.draft or window.sessionID ~= (live and live.id)
                        or key == "npc_add" and window.picker:GetValue() ~= context.npcID
                        or key ~= "npc_add" and window.actorID ~= actorID then return false end
                    window:Show(); return true
                end
            end
        end
        local navigation = blocked("TUTORIAL_WINDOW_CLOSED", nil, recover)
        navigation.pauseMocks = true
        return navigation
    end
    if moduleKey == "npc" then
        local session = addon.GameMasterService.GetActiveSession()
        local actorID = context.actorID or state.markerActorID
        if window.sessionID ~= (session and session.id) or (key ~= "npc_add" and window.actorID ~= actorID) then
            return blocked("TUTORIAL_SELECT_PRACTICE_NPC", window)
        end
        if key == "npc_add" and window.picker:GetValue() ~= context.npcID then
            return blocked("TUTORIAL_SELECT_PRACTICE_NPC", window.picker)
        end
        if key == "npc_cast" and window.spell:GetValue() ~= context.spellID then
            return blocked("TUTORIAL_FIND_NPC_ABILITY", window.spell)
        end
    elseif moduleKey == "book" then
        local _, filters = addon.GameMasterCompactSpellbook.GetTutorialContext()
        if filters and filters.actorID then return blocked("TUTORIAL_PRACTICE_BOOK", window) end
    elseif moduleKey == "largeBook" and (not window.panel
        or window.panel.spellbook ~= addon.GameMasterService.GetActionSpellbook()) then
        return blocked("TUTORIAL_PRACTICE_BOOK", window)
    end
    local collapsed = window.windowMinimized or window.appliedCollapsed
    if collapsed and current.id ~= "windows" then
        local toggle = window.minimizeButton or window.collapseButton or window.minimize
        local navigation = blocked("TUTORIAL_WINDOW_MINIMIZED", toggle,
            toggle and function() toggle:Click(); return true end)
        navigation.pauseMocks = true
        return navigation
    end
    local target = practice.GetAnchor(key)
    if targetVisible(target) then return { anchor = target } end
    return blocked("TUTORIAL_FIND_CONTROL", window.listViewport or window)
end

function practice.NextPlayerRound()
    if not state or state.role ~= "player" then return false end
    local service = addon.GameMasterService
    local round = service.GetActiveRound()
    if not round or not service.GetTurnState().completed or not practice.GetState().mocksDone then return false end
    if round.number >= 3 then service.Stop(); return true end
    if not service.StartRound() then return false end
    local dialog = frame("dialog")
    if dialog then dialog:Hide() end
    return true
end

function practice.Update()
    if not state then return end
    addon.GameMasterService.TickTutorial(suspended or navigationSuspended or not state.mocksEnabled)
end

function practice.SetNavigationBlocked(value) navigationSuspended = value == true end

function practice.SetMockFlow(enabled) if state then state.mocksEnabled = enabled == true end end
function practice.AllowFinish() if state then state.allowFinish = true end end
function practice.MarkRosterTarget()
    if not state then return false end
    local session = addon.GameMasterService.GetActiveSession()
    if not session then return false end
    state.rosterKey = nil
    for _, key in ipairs(session.participantOrder) do
        if key ~= session.ownerKey and key ~= session.tutorialBuffSourceKey and key ~= session.tutorialDebuffSourceKey then
            state.rosterKey = key
            return true
        end
    end
    return false
end
function practice.IsRosterExcluded()
    local session, round = addon.GameMasterService.GetActiveSession(), addon.GameMasterService.GetActiveRound()
    return state and session and round and not addon.GameMasterStore.IsParticipantActive(round, state.rosterKey)
end
function practice.OpenLargeBook()
    if not state then return false end
    local large = frame("largeBook")
    if not state.largeOpened and large and large:IsShown() then
        state.largePrevious = { book = large.panel.spellbook, label = large.panel.profileLabel,
            readOnly = large.panel.readOnly }
    end
    state.largeOpened = true
    addon.SpellbookWindow.Open(addon.GameMasterService.GetActionSpellbook(), addon.L("TUTORIAL_TITLE"), { readOnly = true })
    return true
end
function practice.CloseLargeBook()
    if not state or not state.largeOpened then return end
    if state.largePrevious then
        addon.SpellbookWindow.Open(state.largePrevious.book, state.largePrevious.label, { readOnly = state.largePrevious.readOnly })
    else addon.SpellbookWindow.Close() end
    state.largeOpened, state.largePrevious = nil, nil
end

function practice.BeginNPCScene()
    if state or not practice.Open("gm") then return false end
    local scene = frame("scene")
    if scene then scene:Hide() end
    local service = addon.GameMasterService
    if not service.CreateSession(addon.L("TUTORIAL_SCENE_NAME"), nil,
        { gmParticipates = true, enemyPhases = true, enemyFirst = true }) then practice.Close(); return false end
     
    for _ = 1, 5 do if not service.StartRound() then practice.Close(); return false end end
    open("control")
    return true
end

function practice.PlayerPerspective()
    if not state then return false end
    local npc = frame("npc")
    if npc then npc:Hide() end
    local dialog = frame("dialog")
    if dialog then dialog:Hide() end
    if not addon.GameMasterService.SetTutorialPerspective("player") then return false end
    state.role = "player"
    practice.ShowWindows()
    if type(UIFrameFadeIn) == "function" then
        state.fadingWindows = {}
        for _, key in ipairs({ "overview", "action", "book" }) do
            local window = frame(key)
            if window then
                local alpha = window:GetAlpha()
                state.fadingWindows[#state.fadingWindows + 1] = { window = window, alpha = alpha }
                UIFrameFadeIn(window, 0.4, 0, alpha)
            end
        end
    end
    return true
end

function practice.OpenMarkerExample()
    if not state then return false end
    local service = addon.GameMasterService
    local session = service.GetActiveSession()
    if not session then return false end
    if not state.markerActorID then
        local actor = addon.GameMasterNPCActors.Add(session, {
            name = addon.L("TUTORIAL_MARKER_NPC"), side = "players", ownerPlayerKey = session.ownerKey,
            spells = {},
        })
        if not actor then return false end
        state.markerActorID = actor.id
        service.SetNPCReleased(actor.id, true)
    end
    return addon.GameMasterNPCDialog.Open(session.id, state.markerActorID)
end

function practice.ShowWindows()
    if not state then return end
    open("overview"); open("action"); open("book")
    if state.role == "gm" then open("control") end
end

function practice.Restore()
    if state then practice.ShowWindows(); state.restored = true end
end

function practice.Capture()
    if not state then return nil end
    local service = addon.GameMasterService
    local tutorial = service.GetTutorialState()
    if not tutorial then return nil end
    local snapshot = { values = {}, previous = state.previous, windows = {},
        session = copy(service.GetActiveSession()), book = copy(tutorial.book),
        actorNames = copy(tutorial.actorNames), visibility = service.GetVisibility(),
        orderLocked = addon.GameMasterStore.IsOrderLocked(),
        playerState = copy(tutorial.playerState),
        preparation = copy(addon.GameMasterPlayerState.GetPreparation()) }
    for _, key in ipairs(replayKeys) do snapshot.values[key] = copy(state[key]) end
    for key in pairs(modules) do
        local window = frame(key)
        if window then snapshot.windows[key] = { shown = window:IsShown(),
            minimized = window.windowMinimized or window.appliedCollapsed or false } end
    end
    local dialog, targets, spell = addon.GameMasterActionDialog.GetTutorialContext()
    if dialog and dialog:IsShown() and spell and not dialog.npcActorID then
        snapshot.dialog = { spellID = spell.id, targets = copy(targets),
            action = dialog.actionSelector:GetValue(), targetType = dialog.targetTypeSelector:GetValue(),
            player = dialog.playerSelector:GetValue(), aoe = dialog.aoeCheck:GetChecked() }
    end
    local npc = frame("npc")
    if npc and npc:IsShown() then snapshot.npcActorID = npc.actorID end
    if snapshot.session then
        snapshot.mockDelay = math.max(2, (snapshot.session.tutorialDue or 0) - addon.Runtime.GetMonotonicTime())
    end
    return snapshot
end

function practice.Rewind(snapshot)
    local service = addon.GameMasterService
     
    if service.IsSessionActive() and not service.IsTutorialActive() then return false end
    practice.Close()
    if not snapshot then return true end
    if not practice.Open("gm" == snapshot.values.role and "gm" or "player") then return false end
    local tutorial = service.GetTutorialState()
    tutorial.book, tutorial.actorNames = copy(snapshot.book), copy(snapshot.actorNames)
    tutorial.playerState = copy(snapshot.playerState)
    if snapshot.session then
        if not service.GetActiveSession() and not service.CreateSession(snapshot.session.name,
            snapshot.session.access, { gmParticipates = snapshot.session.gmParticipates,
                enemyPhases = snapshot.session.enemyPhases, enemyFirst = snapshot.session.enemyFirst }) then
            practice.Close(); return false
        end
        local session = service.GetActiveSession()
        local id = session.id
        for key in pairs(session) do session[key] = nil end
        for key, value in pairs(copy(snapshot.session)) do session[key] = value end
         
        session.id, session.tutorialDue = id, addon.Runtime.GetMonotonicTime() + snapshot.mockDelay
        local preparation = copy(snapshot.preparation)
        if preparation then preparation.sessionID = id end
        addon.GameMasterPlayerState.SetPreparation(preparation)
        for _ = 1, 3 do
            if service.GetVisibility() == snapshot.visibility then break end
            service.CycleVisibility()
        end
        if not service.SetTutorialPerspective(snapshot.values.role) then practice.Close(); return false end
    end
    for _, key in ipairs(replayKeys) do state[key] = copy(snapshot.values[key]) end
    addon.GameMasterService.SetOrderLocked(snapshot.orderLocked)
    state.previous, suspended = snapshot.previous, false
    for key, saved in pairs(snapshot.windows) do
        local window = frame(key)
        if saved.shown and (key == "control" or key == "overview" or key == "book" or key == "action") then open(key) end
        if window then
            local minimized = window.windowMinimized or window.appliedCollapsed or false
            local toggle = window.minimizeButton or window.collapseButton or window.minimize
            if minimized ~= saved.minimized and toggle then toggle:Click() end
            window:SetShown(saved.shown)
        end
    end
    if snapshot.windows.npc and snapshot.windows.npc.shown and snapshot.session then
        addon.GameMasterNPCDialog.Open(service.GetActiveSession().id, snapshot.npcActorID)
    end
    if snapshot.windows.largeBook and snapshot.windows.largeBook.shown then practice.OpenLargeBook() end
    if snapshot.dialog then
        local saved = snapshot.dialog
        local spell = tutorial.book.spells[saved.spellID]
        if spell and addon.GameMasterActionDialog.Open(spell, { forcedAction = saved.action }) then
            local dialog = frame("dialog")
            dialog.targetTypeSelector:SetValue(saved.targetType)
            dialog.playerSelector:SetValue(saved.player)
            if saved.aoe then
                dialog.aoeCheck:SetChecked(true)
                local callback = dialog.aoeCheck.GetScript and dialog.aoeCheck:GetScript("OnClick")
                if callback then callback(dialog.aoeCheck) end
                for _, target in ipairs(saved.targets or {}) do
                    if target.kind == "player" then
                        dialog.playerSelector:SetValue(target.value)
                        dialog.addTarget:Click()
                    end
                end
            end
        end
    end
    return true
end

function practice.SetSuspended(value)
    if not state or suspended == value then return end
    suspended = value
    addon.GameMasterService.TickTutorial(true)
    if value then
        state.suspendedWindows = practice.GetWindows()
        for _, window in ipairs(state.suspendedWindows) do window:Hide() end
    else
        for _, window in ipairs(state.suspendedWindows or {}) do window:Show() end
        state.suspendedWindows = nil
    end
end

function practice.Close()
    if not state then return end
    practice.CloseLargeBook()
    local previous = state.previous
    for _, entry in ipairs(state.fadingWindows or {}) do
        if type(UIFrameFadeRemoveFrame) == "function" then UIFrameFadeRemoveFrame(entry.window) end
        entry.window:SetAlpha(entry.alpha)
    end
    state, suspended, navigationSuspended = nil, false, false
    addon.GameMasterService.EndTutorial()
    addon.GameMasterCompactSpellbook.SetTutorialFilters(false)
    for key in pairs(modules) do
        local window = frame(key)
        if window then
            window:SetShown(previous[key] == true)
        end
    end
end
