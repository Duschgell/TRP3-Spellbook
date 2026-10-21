local _, addon = ...
local onboarding = addon.Onboarding
local authored = {}
local function registerTour(id, tour)
    authored[id] = tour
    return onboarding.RegisterTour(id, tour)
end

local function step(id, key, options)
    local result = options or {}
    result.id, result.title, result.text = id, "TUTORIAL_" .. key .. "_TITLE", "TUTORIAL_" .. key .. "_TEXT"
    return result
end

local function panel() return addon.TRP3Integration.GetSpellbookPanel() end
local function scenePlayer(session, target)
    if not session or not target or target.kind ~= "player" then return false end
    local key = addon.Runtime.NormalizePlayerID(target.value)
    return key ~= nil and session.participants and session.participants[key] ~= nil
end
local function bindBook(context)
    local book = addon.Database.GetActiveSpellbook()
    if not book then return false end
    context.book, context.bookID = book, book.id
    return true
end
local function sameBook(context)
    local book = addon.Database.GetActiveSpellbook()
    return book ~= nil and book == context.book and book.id == context.bookID
end
local function openBook()
    return addon.TRP3Integration.Open()
end
local function editor(includeHidden)
    local frame, state = addon.SpellEditorWindow.GetTutorialContext()
    local run = onboarding.GetActive()
    if frame and (includeHidden or frame:IsVisible()) and state and run and run.id == "spellbook"
        and state.bookID == run.context.bookID
        and (not state.book or state.book == run.context.book)
        and ((not state.spellID and state.creationDraft == run.context.draft)
            or (state.spellID and state.spellID == run.context.spellID))
        and (not state.storage or state.storage == addon.Database) then return frame, state end
end
local function editorFree()
    local frame = addon.SpellEditorWindow.GetTutorialContext()
    if frame and frame:IsShown() then return false, addon.L("TUTORIAL_EDITOR_BUSY") end
    local layout = addon.GameMasterLayoutEditor and addon.GameMasterLayoutEditor.GetTutorialContext()
    if layout and layout:IsShown() then return false, addon.L("TUTORIAL_LAYOUT_BUSY") end
    return true
end
local function beginSpell()
    if editor() then return true end
    local owned, state = editor(true)
    if owned and addon.SpellEditorWindow.ResumeTutorialDraft then
        return addon.SpellEditorWindow.ResumeTutorialDraft(state.token, addon.Database, state.book)
    end
    local other, otherState = addon.SpellEditorWindow.GetTutorialContext()
    if other and otherState and otherState.token then return false, addon.L("TUTORIAL_OTHER_DRAFT") end
    local available, err = editorFree()
    if not available then return false, err end
    local run = onboarding.GetActive()
    if run and run.id == "spellbook" and run.context.spellID then
        addon.SpellEditorWindow.OpenEdit(run.context.spellID, run.context.onChanged)
        return editor() ~= nil
    end
    if not openBook() then return false end
    local bookPanel = panel()
    if not bookPanel then return false end
    if run and run.context.draft and addon.SpellEditorWindow.OpenNew then
        addon.SpellEditorWindow.OpenNew(run.context.draftTab, run.context.onChanged)
        return editor() ~= nil
    end
    local placeholder = bookPanel.fancyControls and bookPanel.fancyControls.placeholder
    if placeholder and placeholder:IsShown() then placeholder:Click()
    else bookPanel.newSpellButton:Click() end
    return true
end
local function revealCreation()
    if editor() then return true end
    local run = onboarding.GetActive()
    if run and run.context.spellID then return beginSpell() end
    if not openBook() then return false end
    local p = panel()
    return p and addon.SpellbookPanel.RevealTutorialCreation(p)
end
local function field(name)
    return function()
        local frame = editor()
        if not frame then return nil end
        local control = frame.fields[name] or frame[name]
        if name == "description" and control and control.scrollFrame then return control.scrollFrame end
        if control and control:IsVisible() then return control end
        if name == "magicType" then return frame.damageTypeControl and frame.damageTypeControl.field end
        if name == "duration" or name == "effectMessage" then return frame.buffToggle end
        return nil
    end
end
local function editorStep(id, key, fieldName, required)
    local function observe(ignoreFocus)
        local frame, state = editor()
        if not frame then return nil end
        if fieldName == "iconButton" then
            return tostring(state.icon) .. ":" .. tostring(state.nameColor)
        elseif fieldName == "magicButton" then return state.kind
        elseif fieldName == "buffToggle" then
            return state.effects and (state.effects.debuff and "debuff" or state.effects.buff and "buff" or "none")
        elseif fieldName == "healingToggle" then return state.effects and state.effects.healing == true
        elseif fieldName == "tabName" then return state.selectedTabID end
        local control = fieldName == "magicType" and field(fieldName)() or frame.fields[fieldName]
        if not ignoreFocus and control and control.HasFocus and control:HasFocus() then return nil end
        return control and control:GetText()
    end
    return step(id, key, { anchor = field(fieldName), action = beginSpell,
        editorField = fieldName,
        replayOptional = fieldName == "tabName" and function()
            local book = addon.Database.GetActiveSpellbook()
            return book and #(book.tabOrder or {}) <= 1
        end or nil,
        actionText = "TUTORIAL_SHOW_EDITOR",
        observe = function() return observe(false) end,
        baseline = function() return observe(true) end,
        guidance = function(context)
            local frame = editor()
            if not frame then
                return context.spellID and "TUTORIAL_SAVED_EDITOR_CLOSED" or "TUTORIAL_EDITOR_CLOSED"
            end
            if (fieldName == "duration" or fieldName == "effectMessage")
                and not frame.fields[fieldName]:IsVisible() then
                return fieldName == "duration" and "TUTORIAL_ENABLE_DURATION" or "TUTORIAL_ENABLE_MESSAGE"
            end
        end,
        ready = function()
            local frame = editor()
            if not frame then return false end
            local target = field(fieldName)()
            if not target or not target:IsVisible() then return false end
            if (fieldName == "duration" or fieldName == "effectMessage")
                and not frame.fields[fieldName]:IsVisible() then return false end
            return not required or frame.fields[fieldName]:GetText():match("%S") ~= nil
        end })
end
local function openSettings()
    return addon.TRP3Bridge.OpenConfigurationPage(addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID)
end
local function settingsPage()
    local getter = addon.TRP3Bridge.GetTutorialConfigurationPage
    return getter and getter(addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID)
end
local function settingsPageAnchor()
    return settingsPage() or addon.TRP3Bridge.GetTutorialNavigationAnchor(
        "main_91_config_" .. addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID)
end
local function settingsAnchor()
    if addon.TRP3Bridge.GetTutorialConfigurationAnchor then
        local button = addon.TRP3Bridge.GetTutorialConfigurationAnchor(addon.L("TUTORIAL_TITLE"))
        if button then return button end
    end
    return addon.TRP3Bridge.GetTutorialNavigationAnchor("main_91_config_" .. addon.Constants.GAMEMASTER_SETTINGS_PAGE_ID)
end
local function finishStep()
    return step("settings", "SETTINGS", { enter = openSettings, anchor = settingsPageAnchor,
        action = openSettings, resume = true })
end
local function bookPart(key)
    return function()
        local p = panel()
        if key == "bookmarkHost" and p and p.fancyControls then
            for _, bookmark in ipairs(p.fancyControls.bookmarks or {}) do
                if bookmark:IsVisible() and bookmark.tabID == p.activeTabID then return bookmark.sleeve end
            end
        end
        return p and ((p.fancyControls and p.fancyControls[key]) or p[key])
    end
end
local function newSlot(context)
    local p = panel()
    if not p or not p:IsVisible() or p.spellbook ~= context.book then return nil end
    for _, slot in ipairs(p and p.spellSlots or {}) do
        if slot.spellID == context.spellID and slot:IsVisible() then return slot end
    end
end
local function readingTarget(context, sharing)
    local p = panel()
    if not p or not p:IsVisible() or p.spellbook ~= context.book then
        return "TUTORIAL_BOOK_CLOSED", addon.TRP3Integration.toolbarButton
    end
    local details = p.detailsView
    if details and details:IsVisible() then
        if p.detailSpellID == context.spellID then
            return nil, sharing and details.insertChatButton or details
        end
        return "TUTORIAL_RETURN_LIST", details.backButton
    end
    local slot = newSlot(context)
    if slot then return sharing and "TUTORIAL_READ_TEXT" or nil, slot end
    if p.searchBox and p.searchBox:GetText():match("%S") then
        return "TUTORIAL_FIND_SEARCH", p.searchBox
    end
    if p.favoritesOnly and not context.book.favorites[context.spellID] then
        return "TUTORIAL_FIND_FAVORITES", p.fancyPresentation and p.fancyControls.ribbon or p.favoriteFilterButton
    end
    for _, id in ipairs(context.book.tabOrder or {}) do
        for _, spellID in ipairs(context.book.tabs[id].spellIds or {}) do
            if spellID == context.spellID and id ~= p.activeTabID then
                for _, bookmark in ipairs(p.fancyControls and p.fancyControls.bookmarks or {}) do
                    if bookmark.tabID == id and bookmark:IsVisible() then
                        return "TUTORIAL_FIND_TAB", bookmark.sleeve
                    end
                end
                for _, button in ipairs(p.tabButtons or {}) do
                    if button.tabID == id and button:IsVisible() then return "TUTORIAL_FIND_TAB", button end
                end
                return "TUTORIAL_FIND_TAB", p.fancyControls and p.fancyControls.bookmarkHost or p.tabBar
            end
        end
    end
    return "TUTORIAL_FIND_PAGE", p.pageNumber or p.nextPageButton
end
local function readingReady(context)
    local p = panel()
    return p ~= nil and p:IsVisible() and p.spellbook == context.book
        and p.detailSpellID == context.spellID and p.detailsView ~= nil and p.detailsView:IsVisible()
end
local function backToBook()
    openBook()
    local p = panel()
    if p and p.detailSpellID then p.detailsView.backButton:Click() end
    return true
end

function onboarding.GetCreationDraft(storage)
    local run = onboarding.GetActive()
    local current = run and run.tour.steps[run.index]
    if run and run.id == "npc" and current.id == "create_spell" and not run.context.spellID
        and addon.NPCArchive and storage == addon.NPCArchive.SpellbookStorage then
        run.context.npcDraft = run.context.npcDraft or { description = "" }
        return run.context.npcDraft
    end
    if run and run.id == "spellbook" and (current.id == "create" or current.editorField or current.id == "save")
        and not run.context.spellID and (not storage or storage == addon.Database) then
        local book = addon.Database.GetActiveSpellbook()
        if book and book.id == run.context.bookID then
            run.context.draft = run.context.draft or addon.TutorialExamples.ForPlayer()
            return run.context.draft
        end
    end
end

function onboarding.OnSpellSaved(state, spell)
    local run = onboarding.GetActive()
    if run and run.id == "npc" and addon.NPCArchive and state.storage == addon.NPCArchive.SpellbookStorage then
        if run.tour.steps[run.index].id ~= "create_spell" then return end
        if run.context.npcDraft and not run.context.spellID and state.creationDraft ~= run.context.npcDraft then return end
        local before = run.context.originalSpells
        if spell.id == run.context.spellID or not run.context.spellID and before and not before[spell.id] then
            run.context.spellID, run.context.npcSpellChanged = spell.id, state.onChanged
            local storage = addon.NPCArchive.SpellbookStorage
            run.context.npcSpellToken = storage.GetSpellToken and storage.GetSpellToken(spell.id)
            run.context.npcSpellSaved = true
        end
        return
    end
    if not run or run.id ~= "spellbook" or state.bookID ~= run.context.bookID
        or (state.storage and state.storage ~= addon.Database) then return end
    local context = run.context
    if (context.draft and state.creationDraft == context.draft)
        or (context.spellID and spell.id == context.spellID) then
        context.spellID, context.onChanged = spell.id, state.onChanged
        context.savedPending = true
        context.requireSave = nil
    end
end

local function rememberEditorDraft(frame, state, draft)
    for _, name in ipairs({ "name", "description", "range", "castTime", "cooldown", "resource" }) do
        if frame.fields[name] then draft[name] = frame.fields[name]:GetText() end
    end
    draft.icon, draft.nameColor = state.icon, state.nameColor
    if state.effects then
        draft.effects = { buff = state.effects.buff, debuff = state.effects.debuff, healing = state.effects.healing,
            duration = frame.fields.duration:GetText(), whisperTemplate = frame.fields.effectMessage:GetText(),
            debuffType = frame.fields.debuffType and frame.fields.debuffType:GetText() }
        if addon.SpellPresentation and addon.SpellPresentation.ParseEffectDuration then
            draft.effects.durationRounds, draft.effects.durationSeconds =
                addon.SpellPresentation.ParseEffectDuration(draft.effects.duration)
        end
    end
    draft.tags = draft.tags or {}
    if state.kind then draft.tags[addon.Constants.SPELL_TAG_KIND] = state.kind end
    for name, key in pairs({ magicType = addon.Constants.MAGIC_TAG_TYPE,
        magicSchool = addon.Constants.MAGIC_TAG_SCHOOL, damageType = addon.Constants.SPELL_TAG_DAMAGE_TYPE }) do
        if key and frame.fields[name] then draft.tags[key] = frame.fields[name]:GetText() end
    end
    if frame.resourceControl then
        local amount = frame.resourceControl.amount
        if amount:IsEnabled() and amount:GetText() ~= "" then
            draft.resource = amount:GetText() .. " " .. draft.resource
        end
    end
end

local function rememberDraft(context)
    local frame, state = editor(true)
    if not frame or context.spellID or not context.draft then return end
    context.draftTab, context.onChanged = state.selectedTabID, state.onChanged
    rememberEditorDraft(frame, state, context.draft)
end

local function rememberNPCDraft(context)
    local frame, state = addon.SpellEditorWindow.GetTutorialContext()
    if frame and state and context.npcDraft and not context.spellID
        and state.storage == addon.NPCArchive.SpellbookStorage and state.creationDraft == context.npcDraft then
        context.npcDraftTab, context.npcSpellChanged = state.selectedTabID, state.onChanged
        rememberEditorDraft(frame, state, context.npcDraft)
    end
end

local function captureCore(context, target)
    rememberDraft(context)
    local p = panel()
    local snapshot = { tab = p and p.activeTabID, favoritesOnly = p and p.favoritesOnly,
        search = p and p.searchBox and p.searchBox:GetText() }
    local frame, state = editor(true)
    if not frame then return snapshot end
    local control = target.editorField and frame.fields[target.editorField]
    snapshot.text, snapshot.kind, snapshot.icon, snapshot.color = control and control:GetText(), state.kind, state.icon, state.nameColor
    snapshot.buff, snapshot.debuff, snapshot.healing = state.effects and state.effects.buff,
        state.effects and state.effects.debuff, state.effects and state.effects.healing
    snapshot.selectedTabID = state.selectedTabID
    return snapshot
end

local function restoreCore(context, target, snapshot)
    local frame = editor()
    rememberDraft(context)
    local layout = addon.GameMasterLayoutEditor.GetTutorialContext()
    if target.id == "layout" or target.id == "layout_options" or target.id == "layout_close" then
        if not layout or not layout:IsShown() then addon.GameMasterLayoutEditor.Open() end
        if target.id ~= "layout" then addon.GameMasterLayoutEditor.SelectModule("roundOverview") end
        return true
    end
    if context.layoutOpened and layout and layout:IsShown() then layout.discard:Click() end
    if target.editorField or target.id == "save" then
        if target.id == "save" then context.requireSave = true end
        if not beginSpell() then return false end
        local frame, state = editor()
        if snapshot then
            local control = target.editorField and frame.fields[target.editorField]
            if snapshot.text and control then control:SetText(snapshot.text) end
            if target.id == "appearance" then
                state.icon, state.nameColor = snapshot.icon, snapshot.color
                if frame.iconButton.iconTexture then
                    addon.UIFactory.SetIconTexture(frame.iconButton.iconTexture, state.icon, addon.Constants.DEFAULT_BOOK_ICON)
                end
                if frame.colorButton then
                    addon.UIFactory.SetColorButton(frame.colorButton, state.nameColor)
                    addon.UIFactory.SetFontColor(frame.fields.name, state.nameColor, addon.Theme.Colors.text)
                end
            elseif target.id == "tab" and frame.previousTab then
                local book = addon.Database.GetActiveSpellbook()
                if book.tabs[snapshot.selectedTabID] then
                    for _ = 1, #(book.tabOrder or {}) do
                        if state.selectedTabID == snapshot.selectedTabID then break end
                        frame.previousTab:Click()
                    end
                end
            elseif (target.id == "kind" or target.id == "school") and snapshot.kind then
                local button = snapshot.kind == addon.Constants.SPELL_KIND_MAGIC and frame.magicButton or frame.abilityButton
                if button then button:Click() end
            elseif (target.id == "effects" or target.id == "duration" or target.id == "effect_message") and state.effects then
                for _ = 1, 3 do
                    if state.effects.buff == snapshot.buff and state.effects.debuff == snapshot.debuff then break end
                    frame.buffToggle:Click()
                end
            elseif target.id == "healing" and snapshot.healing ~= nil then
                frame.healingToggle:SetChecked(snapshot.healing)
                local callback = frame.healingToggle.GetScript and frame.healingToggle:GetScript("OnClick")
                if callback then callback(frame.healingToggle) end
            end
        end
        return true
    end
    if frame then frame:Hide() end
    if target.id == "create" or target.id == "read" then return backToBook() end
    if target.id == "share" then
        backToBook()
        local slot = newSlot(context)
        if slot and slot.spellID == context.spellID then slot:Click(); return true end
        return false
    end
    if target.id == "navigation" or target.id == "bookmarks" or target.id == "arrange"
        or target.id == "search" or target.id == "favorites" or target.id == "export" then
        backToBook()
        local p = panel()
        if p and snapshot and (target.id == "bookmarks" or target.id == "search" or target.id == "favorites") then
            p.favoritesOnly = snapshot.favoritesOnly
            if snapshot.search then p.searchBox:SetText(snapshot.search) end
            if addon.SpellbookPanel.Refresh then
                addon.SpellbookPanel.Refresh(p, addon.Database.GetActiveSpellbook(), p.profileLabel, snapshot.tab)
            else p.activeTabID = snapshot.tab end
        end
        return true
    end
    return true
end

registerTour("spellbook", {
    canStart = editorFree,
    capture = captureCore,
    restore = restoreCore,
    start = function(context)
        if not openBook() then return false end
        return bindBook(context)
    end,
    validate = function(context)
        if not sameBook(context) then return false end
        if context.spellID and not context.book.spells[context.spellID] then
            return false, addon.L("TUTORIAL_SPELL_MISSING")
        end
        return true
    end,
    cleanup = function(context)
        if context.layoutOpened then
            local frame = addon.GameMasterLayoutEditor.GetTutorialContext()
            if frame and frame:IsShown() then frame.discard:Click() end
        end
    end,
    update = function(context, current)
        if not context.savedPending then return end
        context.savedPending = nil
         
        if current.id == "create" or current.action == beginSpell and current.id ~= "save" then
            beginSpell()
        end
    end,
    steps = {
        step("navigation", "NAVIGATION", { enter = openBook, action = openBook,
            anchor = function() return addon.TRP3Bridge.GetTutorialNavigationAnchor(addon.Constants.NAVIGATION_MENU_ID) end }),
        step("create", "CREATE", { autoAdvance = true, enter = function(context)
            if onboarding.GetActive().rewinding then return backToBook() end
            return revealCreation(context)
        end, anchor = function(context)
            return context.spellID and newSlot(context) or bookPart("placeholder")()
        end, action = beginSpell,
            guidance = function(context) if context.spellID then return "TUTORIAL_REOPEN_SPELL" end end,
            actionText = "TUTORIAL_CREATE_SPELL", ready = function() return editor() ~= nil end }),
        editorStep("name", "NAME", "name", true),
        editorStep("appearance", "APPEARANCE", "iconButton"),
        editorStep("kind", "KIND", "magicButton"),
        editorStep("effects", "EFFECTS", "buffToggle"),
        editorStep("healing", "HEALING", "healingToggle"),
        editorStep("duration", "DURATION", "duration"),
        editorStep("effect_message", "EFFECT_MESSAGE", "effectMessage"),
        editorStep("resource", "RESOURCE", "resource"),
        editorStep("range", "RANGE", "range"),
        editorStep("cast_time", "CAST_TIME", "castTime"),
        editorStep("cooldown", "COOLDOWN", "cooldown"),
        editorStep("school", "SCHOOL", "magicType"),
        editorStep("description", "DESCRIPTION", "description", true),
        editorStep("tab", "TAB", "tabName"),
        step("save", "SAVE", { autoAdvance = true, anchor = field("saveButton"), action = beginSpell,
            actionText = "TUTORIAL_SHOW_EDITOR", guidance = function(context)
                if not editor() then
                    local book = addon.Database.GetActiveSpellbook()
                    local spell = book and context.spellID and book.spells[context.spellID]
                    if spell and type(spell.description) == "string" and spell.description:match("%S") then return nil end
                    return context.spellID and "TUTORIAL_SAVED_EDITOR_CLOSED" or "TUTORIAL_EDITOR_CLOSED"
                end
            end, ready = function(context)
                local book = addon.Database.GetActiveSpellbook()
                if not book or book.id ~= context.bookID then return false end
                local spell = context.spellID and book.spells[context.spellID]
                return not context.requireSave and not editor() and spell ~= nil and type(spell.description) == "string"
                    and spell.description:match("%S") ~= nil
            end }),
        step("read", "READ", { autoAdvance = true, anchor = function(context)
                local _, anchor = readingTarget(context); return anchor
            end, guidance = function(context) return readingTarget(context) end,
            ready = readingReady,
            actionText = "TUTORIAL_READ_SPELL", action = function(context)
                local slot = newSlot(context)
                if slot and slot.spellID == context.spellID then slot:Click(); return true end
                return backToBook()
            end }),
        step("share", "SHARE", { anchor = function(context)
            local _, anchor = readingTarget(context, true); return anchor
        end, guidance = function(context) return readingTarget(context, true) end, ready = readingReady }),
        step("bookmarks", "BOOKMARKS", { enter = backToBook, anchor = bookPart("bookmarkHost"), resume = true,
            observe = function() return panel() and panel().activeTabID end }),
        step("arrange", "ARRANGE", { anchor = bookPart("content") }),
        step("search", "SEARCH", { anchor = bookPart("searchBox"), observe = function()
            local box = panel() and panel().searchBox
            if box and not (box.HasFocus and box:HasFocus()) then return box:GetText() end
        end }),
        step("favorites", "FAVORITES", { anchor = function()
            local p = panel()
            return p and (p.fancyPresentation and p.fancyControls.ribbon or p.favoriteFilterButton)
        end, observe = function() return panel() and panel().favoritesOnly end }),
        step("export", "EXPORT", { anchor = bookPart("title") }),
        step("settings_overview", "SETTINGS_OVERVIEW", { enter = openSettings, resume = true,
            anchor = settingsPageAnchor }),
        step("layout", "LAYOUT", { enter = function(context)
            local frame = addon.GameMasterLayoutEditor.GetTutorialContext()
            if not frame or not frame:IsShown() then addon.GameMasterLayoutEditor.Open() end
            context.layoutOpened = true
        end, anchor = function() return addon.GameMasterLayoutEditor.GetTutorialContext() end }),
        step("layout_options", "LAYOUT_OPTIONS", { enter = function()
            addon.GameMasterLayoutEditor.SelectModule("roundOverview")
        end, anchor = function()
            local _, options = addon.GameMasterLayoutEditor.GetTutorialContext(); return options
        end }),
        step("layout_close", "LAYOUT_CLOSE", { autoAdvance = true, anchor = function()
            local frame = addon.GameMasterLayoutEditor.GetTutorialContext(); return frame and frame.discard
        end, ready = function()
            local frame = addon.GameMasterLayoutEditor.GetTutorialContext(); return frame and not frame:IsShown()
        end }),
        finishStep(),
    },
})

local function practiceAnchor(key)
    return function() return addon.TutorialPractice.GetAnchor(key) end
end
local function practiceReady(predicate)
    return function()
        local state = addon.TutorialPractice.GetState()
        return state ~= nil and predicate(state)
    end
end
local function practiceStep(id, key, anchor, predicate, options)
    local result = options or {}
    result.practiceAnchor = anchor
    result.anchor = practiceAnchor(anchor)
    if predicate then result.ready = practiceReady(predicate) end
    result.autoAdvance = predicate ~= nil
    return step(id, key, result)
end
local function cleanPractice() addon.TutorialPractice.Close() end
local function capturePractice() return addon.TutorialPractice.Capture() end
local function restorePractice(_, _, snapshot) return addon.TutorialPractice.Rewind(snapshot) end
local function practiceStart(role)
    return function(context) return bindBook(context) and addon.TutorialPractice.Open(role) end
end
local function updatePractice(context, current)
    if current.id == "settings" then return end
    local key = current.practiceAnchor
        or ({ share_large = "large_spell", share_compact = "spark", remove_buff = "buff", remove_debuff = "debuff",
            add_npc = "npc_add", enemy = "npc_side", release = "npc_release", marker = "npc_marker", npc_cast = "npc_cast" })[current.id]
    local navigation = addon.TutorialPractice.ResolveNavigation(key, context, current)
    addon.TutorialPractice.SetNavigationBlocked(navigation.pauseMocks)
    addon.TutorialPractice.Update()
    local state = addon.TutorialPractice.GetState()
    if not state or state.interrupted or (state.finished and current.id ~= "third_round") then
        onboarding.Stop(false)
        onboarding.OpenHub()
        if addon.Logger then addon.Logger.Error(addon.L("TUTORIAL_PRACTICE_INTERRUPTED")) end
    end
end
registerTour("gameMasterPlayer", {
    canStart = editorFree,
    validate = sameBook,
    capture = capturePractice, restore = restorePractice,
    start = practiceStart("player"), cleanup = cleanPractice,
    update = updatePractice,
    steps = {
        practiceStep("welcome", "PLAYER_INTRO", "overview", nil, { textArgs = function()
            local state = addon.GameMasterService.GetTutorialState()
            return state and state.actorNames or {}
        end }),
        practiceStep("windows_intro", "PLAYER_WINDOWS", "overview"),
        practiceStep("watch_turn", "PLAYER_WATCH", "overview", function(s) return s.isNext end,
            { enter = function() addon.TutorialPractice.SetMockFlow(true) end }),
        practiceStep("book", "PLAYER_BOOK", "spark", function()
            local dialog, _, spell = addon.GameMasterActionDialog.GetTutorialContext()
            return dialog and dialog:IsVisible() and not dialog.npcActorID
                and spell and spell.id == "tutorial_spark"
        end),
        practiceStep("target", "PLAYER_TARGET", "target", function(s) return s.target ~= nil end),
        practiceStep("action_types", "PLAYER_TYPES", "action_kind"),
        practiceStep("after_emote", "PLAYER_EMOTE", "emote"),
        practiceStep("cast", "PLAYER_CAST", "cast", function(s)
            return s.currentActions and s.currentActions[1] and s.currentActions[1].action == "cast"
                and s.currentActions[1].spell.id == "tutorial_spark"
        end),
        practiceStep("overview", "PLAYER_OVERVIEW", "overview"),
        practiceStep("action", "PLAYER_ACTION", "action"),
        step("share_large", "PLAYER_SHARE_LARGE", { autoAdvance = true,
            enter = function() return addon.TutorialPractice.OpenLargeBook() end,
            anchor = practiceAnchor("large_spell"), ready = function(context)
                return context.events and context.events.share_large ~= nil
            end }),
        step("share_compact", "PLAYER_SHARE_COMPACT", { autoAdvance = true,
            enter = function() addon.TutorialPractice.CloseLargeBook() end,
            anchor = practiceAnchor("spark"), ready = function(context)
                return context.events and context.events.share_compact ~= nil
            end }),
        practiceStep("prepare", "PLAYER_PREPARE", "ritual", function(s)
            return s.actions[1] ~= nil and s.actions[1].preparing == true
        end),
        practiceStep("turn", "PLAYER_TURN", "turn", function(s) return s.completed[1] == true end),
        practiceStep("wait_one", "PLAYER_WAIT", "overview", function(s) return s.mocksDone end),
        practiceStep("round_two", "PLAYER_INCOMING", "incoming", function(s) return s.isNext end,
            { enter = function() return addon.TutorialPractice.NextPlayerRound() end }),
        practiceStep("effects", "PLAYER_BUFFS", "buffs"),
        practiceStep("release", "PLAYER_RELEASE", "ritual", function(s)
            return s.currentActions and s.currentActions[1] and s.currentActions[1].spell.id == "tutorial_ritual"
                and s.currentActions[1].action == "cast"
        end),
        practiceStep("channel", "PLAYER_CHANNEL", "spark", function(s) return s.hasChannel == true end),
        practiceStep("multi", "PLAYER_MULTI", "multi", function(s) return s.actionCount >= 2 and s.hasHealing == true end),
        practiceStep("turn_two", "PLAYER_TURN_TWO", "turn", function(s) return s.completed[2] == true end),
        practiceStep("wait_two", "PLAYER_WAIT", "overview", function(s) return s.mocksDone end),
        practiceStep("round_three", "PLAYER_THIRD", "overview", nil,
            { enter = function() return addon.TutorialPractice.NextPlayerRound() end }),
        practiceStep("aoe", "PLAYER_AOE", "aoe", function(s) return s.hasAOE == true end),
        practiceStep("turn_three", "PLAYER_TURN_THREE", "turn", function(s) return s.completed[3] == true end),
        practiceStep("wait_three", "PLAYER_WAIT", "overview", function(s) return s.mocksDone end),
        practiceStep("windows", "WINDOWS", "overview", function(s) return s.minimized and s.restored end,
            { action = function() addon.TutorialPractice.Restore() end, actionText = "TUTORIAL_RESTORE" }),
        step("settings", "PLAYER_DONE", { enter = function()
            addon.TutorialPractice.AllowFinish(); addon.TutorialPractice.NextPlayerRound(); cleanPractice(); return openSettings()
        end, anchor = settingsAnchor }),
    },
})
registerTour("gameMaster", {
    canStart = editorFree,
    validate = sameBook,
    capture = capturePractice, restore = restorePractice,
    start = practiceStart("gm"), cleanup = cleanPractice,
    update = updatePractice,
    steps = {
        practiceStep("create_scene", "GM_CREATE", "scene", function(s) return s.created end),
        practiceStep("roster", "GM_ROSTER", "order", function(s) return s.reordered == true end),
        practiceStep("visibility", "GM_VISIBILITY", "visibility", function(s) return s.visibilityChanges > 0 end),
        practiceStep("start_round", "GM_START", "advance", function(s) return s.round >= 1 and s.roundStatus == "open" end,
            { enter = function() addon.TutorialPractice.SetMockFlow(true) end }),
        practiceStep("exclude", "GM_EXCLUDE", "exclude", function() return addon.TutorialPractice.IsRosterExcluded() == true end,
            { enter = function() return addon.TutorialPractice.MarkRosterTarget() end }),
        practiceStep("include", "GM_INCLUDE", "exclude", function() return addon.TutorialPractice.IsRosterExcluded() == false end),
        practiceStep("lock", "GM_LOCK", "lock", function(s) return s.locked end),
        practiceStep("unlock", "GM_UNLOCK", "lock", function(s) return not s.locked end),
        practiceStep("read_spell", "GM_READ", "read_spell", function(s) return s.readSpell == true end),
        practiceStep("targets", "GM_TARGETS", "control"),
        practiceStep("played", "GM_PLAYED", "played", function(s) return s.mocksDone end),
        practiceStep("overview", "GM_OVERVIEW", "overview", nil,
            { enter = function()
                local npc = addon.GameMasterNPCDialog.GetTutorialContext(); if npc then npc:Hide() end
                addon.TutorialPractice.ShowWindows()
            end }),
        practiceStep("first_round", "GM_ROUND_ONE", "advance", function(s) return s.round >= 2 end),
        practiceStep("effects", "GM_EFFECTS", "buff"),
        step("remove_buff", "GM_REMOVE_BUFF", { autoAdvance = true,
            anchor = practiceAnchor("buff"), ready = function(context) return context.events and context.events.removed_buff == true end }),
        step("remove_debuff", "GM_REMOVE_DEBUFF", { autoAdvance = true,
            anchor = practiceAnchor("debuff"), ready = function(context) return context.events and context.events.removed_debuff == true end }),
        practiceStep("second_round", "GM_ROUND_TWO", "advance", function(s) return s.round >= 3 end),
        practiceStep("windows", "WINDOWS", "control", function(s) return s.minimized and s.restored end,
            { action = function() addon.TutorialPractice.Restore() end, actionText = "TUTORIAL_RESTORE" }),
        practiceStep("third_round", "GM_ROUND_THREE", "finish", function(s) return s.finished end,
            { enter = function() addon.TutorialPractice.AllowFinish() end }),
        step("settings", "GM_DONE", { enter = function() cleanPractice(); return openSettings() end,
            anchor = settingsAnchor }),
    },
})

local function npcContext()
    if addon.NPCArchive and addon.NPCArchive.GetTutorialContext then
        return addon.NPCArchive.GetTutorialContext()
    end
end
local function openNPC() return addon.TRP3Integration.OpenNPCArchive() end
local function npcAnchor(key)
    return function()
        local page = npcContext()
        return page and (page[key] or (page.profile and page.profile[key]))
    end
end
local function noGM() return addon.Modules and not addon.Modules.IsEnabled("gameMaster") end
local function npcBattle(id, key, anchor, predicate, options)
    local result = practiceStep(id, key, anchor, predicate, options)
    result.skip = noGM
    return result
end
local function capturedActor(context)
    local session = addon.GameMasterService.GetActiveSession()
    for _, id in ipairs(session and session.npcOrder or {}) do
        local actor = session.npcActors[id]
        if tostring(actor.templateID) == tostring(context.npcID) then context.actorID = id; return actor end
    end
end
local function actorReady(predicate)
    return function(context)
        local actor = capturedActor(context)
        return actor ~= nil and predicate(actor, context) == true
    end
end
local function npcBattleAction(id, key, anchor, predicate, enter)
    return step(id, key, { autoAdvance = true, skip = noGM,
        anchor = practiceAnchor(anchor), ready = actorReady(predicate), enter = enter })
end

local function restoreNPC(context, target, snapshot)
    rememberNPCDraft(context)
    if not addon.TutorialPractice.Rewind(snapshot) then return false end
    context.battleStarted = snapshot ~= nil
    local frame, state = addon.SpellEditorWindow.GetTutorialContext()
    if frame and frame:IsShown() and state and state.storage == addon.NPCArchive.SpellbookStorage
        and (state.creationDraft and state.creationDraft == context.npcDraft
            or state.spellID and state.spellID == context.spellID) then frame:Hide() end
    if target.id == "assign" and context.npcID and context.spellID then
         
        if not addon.NPCArchive.AssignSpell(context.npcID, context.spellID, false) then return false end
    end
    if not snapshot then
        if target.id == "register" or target.id == "book" or target.id == "library" then
            if not openNPC() then return false end
            local page = npcContext()
            if page then
                local button = target.id == "library" and page.bookButton or page.registerButton
                button:Click()
            end
        elseif target.id ~= "capture" and context.npcID then
            return addon.NPCArchive.OpenTutorialProfile(context.npcID)
        end
    end
    if snapshot and target.id == "enemy" then
        local actor = capturedActor(context)
        local session = addon.GameMasterService.GetActiveSession()
        if actor and not addon.GameMasterService.SetNPCController(actor.id, "players", session.ownerKey) then return false end
    end
    return true
end
registerTour("npc", {
    canStart = editorFree,
    capture = function(context) rememberNPCDraft(context); return capturePractice() end, restore = restoreNPC,
    validate = function(context)
        if not sameBook(context) or context.battleStarted and noGM() then return false end
        local archive, storage = addon.NPCArchive, addon.NPCArchive.SpellbookStorage
        if context.npcToken and archive.GetIdentityToken(context.npcID) ~= context.npcToken
            or context.npcSpellToken and storage.GetSpellToken(context.spellID) ~= context.npcSpellToken then
            return false, addon.L("TUTORIAL_NPC_MISSING")
        end
        return true
    end,
    start = function(context)
        if not bindBook(context) then return false end
        if not openNPC() then return false end
        local page = npcContext(); if page then page.registerButton:Click() end
    end,
    cleanup = cleanPractice,
    update = function(context, current)
        if context.npcID and not addon.NPCArchive.Get(context.npcID)
            or context.spellID and not addon.NPCArchive.SpellbookStorage.GetSpell(context.spellID) then
            onboarding.Stop(false)
            onboarding.OpenHub()
            if addon.Logger then addon.Logger.Error(addon.L("TUTORIAL_NPC_MISSING")) end
            return
        end
        if context.battleStarted and current.id ~= "settings" then updatePractice(context, current) end
    end,
    steps = {
        step("register", "NPC_REGISTER", { anchor = npcAnchor("registerButton") }),
        step("book", "NPC_BOOK", { autoAdvance = true, anchor = npcAnchor("bookButton"),
            ready = function() local _, mode = npcContext(); return mode == "book" end }),
        step("library", "NPC_LIBRARY", { anchor = npcAnchor("newSpell") }),
        step("capture", "NPC_CAPTURE", { autoAdvance = true,
            enter = function(context)
                if context.npcID then return addon.NPCArchive.OpenTutorialProfile(context.npcID) end
                addon.TRP3Bridge.CloseMainFrame()
            end,
            guidance = function(context) if context.npcID then return "TUTORIAL_NPC_PROFILE_SURFACE" end end,
            replayOptional = function(context) return context.npcID ~= nil end,
            anchor = function() return addon.TRP3Integration.toolbarButton end,
            ready = function(context)
                local id = context.npcID or context.events and context.events.npcCaptured
                local npc = id and addon.NPCArchive.Get(id)
                if not npc then return false end
                context.npcID, context.description = id, npc.description or ""
                context.npcToken = addon.NPCArchive.GetIdentityToken and addon.NPCArchive.GetIdentityToken(id)
                return true
            end }),
        step("profile", "NPC_PROFILE", { autoAdvance = true,
            enter = function(context)
                local npc = addon.NPCArchive.Get(context.npcID)
                if not npc then return false end
                context.description = npc.description or ""
                return addon.NPCArchive.OpenTutorialProfile(context.npcID)
            end,
            anchor = npcAnchor("descriptionBox"), ready = function(context)
                local npc = addon.NPCArchive.Get(context.npcID)
                return npc and npc.description and npc.description:match("%S") ~= nil and npc.description ~= context.description
            end }),
        step("assignment", "NPC_ASSIGNMENT", { autoAdvance = true, anchor = npcAnchor("assignment"),
            enter = function()
                local page = npcContext()
                if page and page.scroll then addon.TutorialView.RevealScrollChild(page.scroll, page.profile.assignment) end
            end, ready = function(context)
                local _, mode, id = npcContext(); return mode == "book" and id == context.npcID
            end }),
        step("create_spell", "NPC_CREATE_SPELL", { autoAdvance = true,
            guidance = function(context) if context.spellID then return "TUTORIAL_RESAVE_NPC_SPELL" end end,
            enter = function(context)
                local book = addon.NPCArchive.SpellbookStorage.GetActiveSpellbook()
                if not book then return false end
                context.originalSpells, context.npcSpellSaved = {}, false
                for id in pairs(book.spells) do context.originalSpells[id] = true end
                local frame, state = addon.SpellEditorWindow.GetTutorialContext()
                local owns = state and state.storage == addon.NPCArchive.SpellbookStorage
                    and (state.spellID == context.spellID and context.spellID ~= nil
                        or state.creationDraft == context.npcDraft and context.npcDraft ~= nil)
                if owns and state.token and state.book and addon.SpellEditorWindow.ResumeTutorialDraft then
                    return addon.SpellEditorWindow.ResumeTutorialDraft(state.token, state.storage, state.book)
                end
                if frame and state and (state.token or frame:IsShown()) then return end
                if context.spellID then
                    addon.SpellEditorWindow.OpenEdit(context.spellID, context.npcSpellChanged, addon.NPCArchive.SpellbookStorage)
                elseif context.npcDraft then
                    addon.SpellEditorWindow.OpenNew(context.npcDraftTab, context.npcSpellChanged, addon.NPCArchive.SpellbookStorage)
                end
            end, anchor = function()
                local frame, state = addon.SpellEditorWindow.GetTutorialContext()
                if frame and frame:IsShown() and state.storage == addon.NPCArchive.SpellbookStorage then return frame.saveButton end
                return npcAnchor("newSpell")()
            end, ready = function(context)
                return context.npcSpellSaved == true and context.spellID ~= nil
                    and addon.NPCArchive.SpellbookStorage.GetSpell(context.spellID) ~= nil
            end }),
        step("assign", "NPC_ASSIGN", { autoAdvance = true,
            anchor = function(context)
                local page, _, _, rows = npcContext()
                for _, row in ipairs(rows or {}) do
                    if row.entry and row.entry.id == context.spellID then return row.assigned end
                end
                return page
            end, ready = function(context)
                local npc = addon.NPCArchive.Get(context.npcID)
                for _, id in ipairs(npc and npc.spellIDs or {}) do if id == context.spellID then return true end end
                return false
            end }),
        step("return", "NPC_RETURN", { autoAdvance = true, anchor = npcAnchor("returnButton"),
            ready = function(context) local _, mode, id = npcContext(); return mode == "profile" and id == context.npcID end }),
        step("relationship", "NPC_RELATIONSHIP", { autoAdvance = true, anchor = npcAnchor("relationship"),
            enter = function(context)
                local npc = addon.NPCArchive.Get(context.npcID)
                if not npc then return false end
                context.relationship = npc.relationship
            end,
            ready = function(context)
                local npc = addon.NPCArchive.Get(context.npcID)
                return npc and npc.relationship ~= context.relationship
            end }),
        step("battle_warning", "NPC_BATTLE_WARNING", { anchor = npcAnchor("registerButton"),
            guidance = function() if noGM() then return "TUTORIAL_NPC_GM_DISABLED" end end }),
        npcBattle("battle", "NPC_BATTLE", "control", nil, { enter = function(context)
            if not addon.TutorialPractice.BeginNPCScene() then return false end
            context.battleStarted = true
        end }),
        step("add_npc", "NPC_ADD", { autoAdvance = true, skip = noGM,
            enter = function(context)
                addon.GameMasterNPCDialog.Open()
                local dialog = addon.GameMasterNPCDialog.GetTutorialContext()
                if dialog then dialog.picker:SetValue(context.npcID, true) end
            end, anchor = practiceAnchor("npc_add"), ready = function(context) return capturedActor(context) ~= nil end }),
        npcBattleAction("enemy", "NPC_ENEMY", "npc_side", function(actor) return actor.side == "enemies" end),
        npcBattleAction("release", "NPC_RELEASE", "npc_release", function(actor) return actor.released end),
        npcBattleAction("marker", "GM_MARKER", "npc_marker", function(actor) return actor.markerIndex ~= nil end),
        step("npc_cast", "NPC_CAST", { autoAdvance = true, skip = noGM,
            enter = function(context)
                addon.GameMasterNPCDialog.Open(nil, context.actorID)
                local dialog = addon.GameMasterNPCDialog.GetTutorialContext()
                if dialog then dialog.spell:SetValue(context.spellID, true) end
            end,
            anchor = function()
                local frame = addon.GameMasterActionDialog.GetTutorialContext()
                return frame and frame:IsShown() and frame.submitButton or practiceAnchor("npc_cast")()
            end, ready = function(context)
                local session, round = addon.GameMasterService.GetActiveSession(), addon.GameMasterService.GetActiveRound()
                if not session or not round then return false end
                for _, action in ipairs(addon.GameMasterActionCollection.Get(round.npcSubmissions and round.npcSubmissions[context.actorID])) do
                    if action.action == "cast" and action.spell.id == context.spellID then
                        local targets = action.targets and #action.targets > 0 and action.targets or { action.target }
                        for _, target in ipairs(targets) do
                            if scenePlayer(session, target) then return true end
                        end
                    end
                end
                return false
            end }),
        npcBattle("enemy_phase", "NPC_PHASE", "control", nil, { enter = function()
            local dialog = addon.GameMasterNPCDialog.GetTutorialContext(); if dialog then dialog:Hide() end
        end }),
        npcBattle("end_enemy", "NPC_END_ENEMY", "advance", function(s) return s.phase == "players" end),
        npcBattle("perspective", "NPC_PERSPECTIVE", "incoming", nil,
            { enter = function() return addon.TutorialPractice.PlayerPerspective() end }),
        step("settings", "NPC_DONE", { enter = function() cleanPractice(); return openSettings() end,
            guidance = function() if noGM() then return "TUTORIAL_NPC_REGISTER_DONE" end end,
            anchor = settingsAnchor }),
    },
})

local function visible(target)
    if addon.TutorialView and addon.TutorialView.IsTargetVisible then return addon.TutorialView.IsTargetVisible(target) end
    return target ~= nil and target.IsVisible and target:IsVisible()
end
local function missing(key, anchor, recover, args)
    return { blocked = true, key = key, anchor = anchor, recover = recover, args = args }
end
local function controlNavigation(target, scroll)
    if visible(target) then return { anchor = target } end
    if scroll and target and target:IsVisible() then
        return missing("TUTORIAL_SCROLL_CONTROL", scroll, function()
            return addon.TutorialView.RevealScrollChild(scroll, target)
        end)
    end
    return missing("TUTORIAL_FIND_CONTROL", scroll)
end
local function editorNavigation(context, current, npc)
    local frame, state = addon.SpellEditorWindow.GetTutorialContext()
    local storage = npc and addon.NPCArchive.SpellbookStorage or addon.Database
    local draft = npc and context.npcDraft or context.draft
    local owns = state and (state.storage or addon.Database) == storage
        and (state.spellID and state.spellID == context.spellID
            or not state.spellID and draft ~= nil and state.creationDraft == draft)
        and (npc or state.bookID == context.bookID and (not state.book or state.book == context.book))
    if not owns then
        if frame and (frame:IsVisible() or state and state.token) then return missing("TUTORIAL_OTHER_DRAFT", frame) end
        return nil
    end
    if not frame:IsVisible() then
        local token, book = state.token, state.book
        return missing("TUTORIAL_RESUME_DRAFT", nil, token and book
            and addon.SpellEditorWindow.ResumeTutorialDraft and function()
                return addon.SpellEditorWindow.ResumeTutorialDraft(token, storage, book)
            end)
    end
    local target = npc and frame.saveButton or field(current.editorField or "saveButton")()
    return controlNavigation(target)
end
local function bookNavigation(context, current)
    local p = panel()
    if not p or not p:IsVisible() or p.spellbook ~= context.book then
        return missing("TUTORIAL_BOOK_CLOSED", addon.TRP3Integration.toolbarButton, openBook)
    end
    if p.detailsView and p.detailsView:IsVisible() and p.detailSpellID then
        return missing("TUTORIAL_RETURN_LIST", p.detailsView.backButton)
    end
    return controlNavigation(current.anchor and current.anchor(context))
end
local function settingsNavigation(context, current)
    local anchor = addon.TRP3Bridge.GetTutorialConfigurationAnchor
        and addon.TRP3Bridge.GetTutorialConfigurationAnchor(addon.L(current.id == "settings_overview"
            and "SPELLBOOK_SETTING_PRESENTATION" or "TUTORIAL_TITLE"))
    if visible(anchor) then return { anchor = anchor } end
    return missing("TUTORIAL_SETTINGS_CLOSED", settingsAnchor(), openSettings)
end
local function coreNavigation(context, current, ready)
    if current.id == "navigation" then return controlNavigation(current.anchor(context)) end
    if current.id == "save" and ready or current.id == "layout_close" and ready then return {} end
    if current.editorField or current.id == "save" then
        return editorNavigation(context, current) or missing("TUTORIAL_EDITOR_CLOSED", addon.TRP3Integration.toolbarButton)
    end
    if current.id == "create" then
        if ready then return {} end
        local owned = editor(true)
        if owned then return editorNavigation(context, current) end
        local other, state = addon.SpellEditorWindow.GetTutorialContext()
        if other and (other:IsVisible() or state and state.token) then return missing("TUTORIAL_OTHER_DRAFT", other) end
        if context.spellID then
            local key, anchor = readingTarget(context)
            return missing(key or "TUTORIAL_REOPEN_SPELL", anchor,
                key == "TUTORIAL_BOOK_CLOSED" and openBook or nil)
        end
        local p = panel()
        if p and p:IsVisible() and p.spellbook == context.book then
            if p.searchBox and p.searchBox:GetText() ~= "" then return missing("TUTORIAL_FIND_SEARCH", p.searchBox) end
            if p.favoritesOnly then
                return missing("TUTORIAL_FIND_FAVORITES", p.fancyPresentation and p.fancyControls.ribbon or p.favoriteFilterButton)
            end
            local target = current.anchor(context)
            if visible(target) then return { anchor = target } end
            return missing("TUTORIAL_FIND_PAGE", p.pageNumber or p.nextPageButton)
        end
        return missing("TUTORIAL_BOOK_CLOSED", addon.TRP3Integration.toolbarButton, openBook)
    end
    if current.id == "read" or current.id == "share" then
        local key, anchor = readingTarget(context, current.id == "share")
        return { blocked = key ~= nil, key = key, anchor = anchor,
            recover = key == "TUTORIAL_BOOK_CLOSED" and openBook or nil }
    end
    if current.id == "settings" or current.id == "settings_overview" then
        local page = settingsPage()
        if visible(page) then return { anchor = page } end
        return missing("TUTORIAL_SETTINGS_CLOSED", settingsPageAnchor(), openSettings)
    end
    if current.id == "layout" or current.id == "layout_options" or current.id == "layout_close" then
        local frame, options, _, selected = addon.GameMasterLayoutEditor.GetTutorialContext()
        if not visible(frame) then return missing("TUTORIAL_LAYOUT_CLOSED", settingsAnchor()) end
        if current.id == "layout_options" and (selected ~= "roundOverview" or not visible(options)) then
            return missing("TUTORIAL_SELECT_OVERVIEW", frame.moduleRows and frame.moduleRows.roundOverview,
                function() return addon.GameMasterLayoutEditor.SelectModule("roundOverview") end)
        end
        return controlNavigation(current.anchor(context))
    end
    return bookNavigation(context, current)
end
local function npcNavigation(context, current, ready)
    if current.id == "settings" then return settingsNavigation(context, current) end
    if current.practiceAnchor or current.skip then
        if current.ready and ready then return {} end
        if current.id == "npc_cast" then
            local dialog, targets, spell = addon.GameMasterActionDialog.GetTutorialContext()
            local session = addon.GameMasterService.GetActiveSession()
            if session and dialog and dialog:IsVisible() and dialog.npcActorID == context.actorID
                and spell and spell.id == context.spellID and dialog.npcContext
                and dialog.npcContext.sessionID == session.id then
                if dialog.actionSelector:GetValue() ~= "cast" then return controlNavigation(dialog.actionSelector) end
                local aoe = dialog.aoeCheck:GetChecked()
                if aoe then
                    for _, target in ipairs(targets or {}) do
                        if scenePlayer(session, target) then
                            return controlNavigation(dialog.submitButton)
                        end
                    end
                end
                if dialog.targetTypeSelector:GetValue() ~= "player" then return controlNavigation(dialog.targetTypeSelector) end
                if aoe then
                    return controlNavigation(scenePlayer(session, { kind = "player", value = dialog.playerSelector:GetValue() })
                        and dialog.addTarget or dialog.playerSelector)
                end
                local target = addon.GameMasterActionDialog.GetTutorialTarget()
                if not scenePlayer(session, target) then
                    return controlNavigation(dialog.playerSelector)
                end
                return controlNavigation(dialog.submitButton)
            end
        end
        return addon.TutorialPractice.ResolveNavigation(current.practiceAnchor
            or ({ add_npc = "npc_add", enemy = "npc_side", release = "npc_release", marker = "npc_marker",
                npc_cast = "npc_cast" })[current.id], context, current)
    end
    if current.id == "capture" then
        if ready then return {} end
        local toolbar = addon.TRP3Integration.toolbarButton
        if visible(toolbar) then return { anchor = toolbar } end
        return missing("TUTORIAL_TOOLBAR_HIDDEN")
    end
    if current.ready and ready and current.id ~= "book" and current.id ~= "assignment" and current.id ~= "return" then return {} end
    if current.id == "create_spell" then
        local navigation = editorNavigation(context, current, true)
        if navigation then return navigation end
    end
    local page, mode, id, rows = npcContext()
    if not page or not page:IsVisible() then
        return missing("TUTORIAL_REGISTER_CLOSED", addon.TRP3Integration.toolbarButton, openNPC)
    end
    if context.npcID and id ~= context.npcID then
        local npc = addon.NPCArchive.Get(context.npcID)
        return missing("TUTORIAL_SELECT_CAPTURED_NPC", page.registerButton, nil, { npc and npc.name or "" })
    end
    local expectedMode = ({ register = "register", book = "register", library = "book", profile = "profile",
        assignment = "profile", create_spell = "book", assign = "book", ["return"] = "book", relationship = "profile" })[current.id]
    if expectedMode and mode ~= expectedMode then
        if current.id == "book" and mode == "book" or current.id == "assignment" and mode == "book"
            or current.id == "return" and mode == "profile" then return { anchor = page } end
        local key = mode == "copy" and "TUTORIAL_NPC_LEAVE_COPY"
            or expectedMode == "profile" and "TUTORIAL_NPC_PROFILE_SURFACE"
            or expectedMode == "book" and "TUTORIAL_NPC_BOOK_SURFACE" or "TUTORIAL_NPC_REGISTER_SURFACE"
        return missing(key, mode == "copy" and page.returnButton or page.registerButton)
    end
    if current.id == "assign" then
        for _, row in ipairs(rows or {}) do
            if row.entry and row.entry.id == context.spellID then return controlNavigation(row.assigned, page.scroll) end
        end
        if page.search and page.search:GetText() ~= "" then return missing("TUTORIAL_FIND_SEARCH", page.search) end
        return missing("TUTORIAL_FIND_NPC_ABILITY", page.tabNext or page.scroll)
    end
    return controlNavigation(current.anchor and current.anchor(context), page.scroll)
end

for id, tour in pairs(authored) do
    for _, current in ipairs(tour.steps) do
        local stepDefinition, tourID = current, id
        current.resolve = function(context, ready)
            if tourID == "spellbook" then return coreNavigation(context, stepDefinition, ready) end
            if tourID == "npc" then return npcNavigation(context, stepDefinition, ready) end
            if stepDefinition.id == "settings" then return settingsNavigation(context, stepDefinition) end
            if stepDefinition.ready and ready then return {} end
            return addon.TutorialPractice.ResolveNavigation(stepDefinition.practiceAnchor
                or ({ share_large = "large_spell", share_compact = "spark", remove_buff = "buff", remove_debuff = "debuff" })[stepDefinition.id],
                context, stepDefinition)
        end
    end
end
