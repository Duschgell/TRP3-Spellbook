local _, addon = ...

local onboarding = {}
addon.Onboarding = onboarding
local order = { "spellbook", "gameMasterPlayer", "gameMaster", "npc" }
local definitions = {
    spellbook = { titleKey = "TUTORIAL_CORE" },
    gameMasterPlayer = { titleKey = "TUTORIAL_PLAYER" },
    gameMaster = { titleKey = "TUTORIAL_GM", optionalModule = "gameMaster" },
    npc = { titleKey = "TUTORIAL_NPC", optionalModule = "npc" },
}
local tours, active = {}, nil
local deferred, initialized, welcomeOffered = false, false, false

local function realSessionActive()
    local service = addon.GameMasterService
    return service and service.IsSessionActive()
        and not (service.IsTutorialActive and service.IsTutorialActive())
end

local function now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function report(message)
    if addon.Logger then addon.Logger.Error(tostring(message)) end
end

local function invoke(callback, ...)
    if not callback then return true end
    local ok, value, err = pcall(callback, ...)
    if not ok then report(value); return false, value end
    return value ~= false, err
end

local function cancelPendingConfirmation()
    local factory = addon.UIFactory
    if not factory or not factory.GetTutorialWindows then return end
    for _, window in ipairs(factory.GetTutorialWindows()) do
        if window.confirmButton and window.closeButton then
            invoke(function() window.closeButton:Click() end)
             
            window.confirmButton:SetScript("OnClick", nil)
        end
    end
end

function onboarding.RegisterTour(id, tour)
    if not definitions[id] or (type(tour) ~= "function" and type(tour) ~= "table") then return false end
    if type(tour) == "table" then
        if type(tour.steps) ~= "table" or #tour.steps == 0 then return false end
        local seen = {}
        for _, step in ipairs(tour.steps) do
            if type(step.id) ~= "string" or not step.id:match("^[%w_]+$") or #step.id > 64
                or seen[step.id] or type(step.title) ~= "string" or type(step.text) ~= "string" then
                return false
            end
            seen[step.id] = true
        end
    end
    tours[id] = tour
    return true
end

function onboarding.HasTour(id)
    local definition = definitions[id]
    return definition ~= nil and tours[id] ~= nil and (not definition.optionalModule
        or (addon.Modules and addon.Modules.IsEnabled(definition.optionalModule)) == true)
end

function onboarding.GetTours()
    local result = {}
    for _, id in ipairs(order) do
        result[#result + 1] = { id = id, title = addon.L(definitions[id].titleKey),
            available = onboarding.HasTour(id),
            complete = addon.OnboardingState and addon.OnboardingState.IsComplete(id) or false }
    end
    return result
end

function onboarding.GetActive() return active end

function onboarding.RecordAction(kind, value, origin)
    if type(kind) ~= "string" or not active or active.paused or inCombat() or realSessionActive()
        or not onboarding.HasTour(active.id)
        or active.tour.validate and not invoke(active.tour.validate, active.context) then return false end
    if kind == "share_large" then
        local tutorial = addon.GameMasterService and addon.GameMasterService.GetTutorialState()
        if not tutorial or origin ~= tutorial.book or not tutorial.book.spells[value] then return false end
    elseif kind == "share_compact" then
        local tutorial = addon.GameMasterService and addon.GameMasterService.GetTutorialState()
        local _, filters = addon.GameMasterCompactSpellbook.GetTutorialContext()
        if not tutorial or not tutorial.book.spells[value] or filters and filters.actorID then return false end
    end
    active.context.events = active.context.events or {}
    active.context.events[kind] = value == nil and true or value
    return true
end

function onboarding.Stop(completed)
    local previous = active
    active = nil
    if previous then
        cancelPendingConfirmation()
        invoke(previous.tour.cleanup, previous.context)
        if completed and addon.OnboardingState then addon.OnboardingState.Complete(previous.id) end
    end
    if addon.TutorialView then addon.TutorialView.Hide() end
end

local function enterStep(index, rewinding)
    local run = active
    if not run then return false end
    local step = run.tour.steps[index]
    while step and step.skip and step.skip(run.context) do
        index = index + 1
        step = run.tour.steps[index]
    end
    if not step then onboarding.Stop(true); return true end
    run.transitioning = true
    run.index, run.ready, run.anchor, run.failed = index, false, nil, false
    run.rewinding, run.replayArmed, run.replayBaselineSet = rewinding == true, false, false
    run.navigation, run.navigationBlocked, run.rebaseNavigation = nil, false, false
    run.context.events = {}
    run.autoInitialized, run.autoPending, run.autoBaseline, run.autoObserved = false, nil, nil, nil
    if run.tour.capture then
        local ok, checkpoint = pcall(run.tour.capture, run.context, step)
        if not ok then
            report(checkpoint)
            run.failed, run.transitioning = true, false
            return false
        end
        run.checkpoints[index] = checkpoint
    end
    run.visited[#run.visited + 1] = index
    if addon.OnboardingState then addon.OnboardingState.SetProgress(run.id, step.id) end
    local ok = invoke(step.enter, run.context)
    if active ~= run then return false end
    if not ok then run.failed = true end
    run.transitioning = false
    onboarding.Tick(false)
    return ok
end

function onboarding.Start(id, replay)
    if not onboarding.HasTour(id) then return false, addon.L("ONBOARDING_NOT_AVAILABLE") end
    if inCombat() then return false, addon.L("TUTORIAL_COMBAT_WAIT") end
    if realSessionActive() then
        return false, addon.L("TUTORIAL_SESSION_WAIT")
    end
    if type(tours[id]) == "function" then return invoke(tours[id], replay == true) end
    local tour = tours[id]
    local ok, err = invoke(tour.canStart)
    if not ok then return false, err end
    onboarding.Stop(false)
    welcomeOffered = true
    if onboarding.watcher then onboarding.watcher:Show() end
    active = { id = id, tour = tour, context = {}, index = 1, replay = replay == true,
        visited = {}, checkpoints = {} }
    if not invoke(tour.start, active.context) then onboarding.Stop(false); return false end
    local index = 1
    local saved = not replay and addon.OnboardingState and addon.OnboardingState.GetProgress(id)
    for i, step in ipairs(tour.steps) do
        if step.id == saved and step.resume then index = i; break end
    end
    return enterStep(index)
end

function onboarding.Next()
    if not active or active.transitioning then return false end
    local run = active
    onboarding.Tick(false)
    if active ~= run or active.paused or not active.ready then return false end
    return enterStep(active.index + 1)
end

function onboarding.Back()
    if inCombat() then return false end
    local run = active
    if not run or run.paused or run.transitioning or #run.visited <= 1 then return false end
     
    if not onboarding.HasTour(run.id) or realSessionActive()
        or (run.tour.validate and not invoke(run.tour.validate, run.context)) then
        onboarding.Stop(false)
        return false
    end
    if active ~= run then return false end
    local index = run.visited[#run.visited - 1]
    run.transitioning, run.autoPending = true, nil
    cancelPendingConfirmation()
    if active ~= run then return false end
    local ok = invoke(run.tour.restore, run.context, run.tour.steps[index], run.checkpoints[index])
    if active ~= run then return false end
    run.transitioning = false
    if not ok then run.failed = true; onboarding.Tick(false); return false end
    table.remove(run.visited)
    table.remove(run.visited)
    return enterStep(index, true)
end

function onboarding.Action()
    if not active or active.paused or active.transitioning or inCombat() then return false end
    local run = active
    if not onboarding.HasTour(run.id) or realSessionActive()
        or (run.tour.validate and not invoke(run.tour.validate, run.context)) then
        onboarding.Stop(false)
        return false
    end
    if active ~= run then return false end
    local step = run.tour.steps[run.index]
    run.transitioning, run.autoPending = true, nil
    local ok = invoke(step.action, run.context)
    if active ~= run then return false end
    run.transitioning, run.failed = false, not ok
    onboarding.Tick(false)
    return ok
end

function onboarding.ReturnToStep()
    local run = active
    if not run or run.paused or run.transitioning or inCombat() then return false end
    if not onboarding.HasTour(run.id) or realSessionActive()
        or (run.tour.validate and not invoke(run.tour.validate, run.context)) then
        onboarding.Stop(false)
        return false
    end
    if active ~= run then return false end
    local step = run.tour.steps[run.index]
    local readyOK, ready = pcall(function() return not step.ready or step.ready(run.context) == true end)
    local ok, navigation = pcall(function() return step.resolve and step.resolve(run.context, readyOK and ready) end)
    if not ok or type(navigation) ~= "table" or not navigation.recover then return false end
    run.transitioning, run.autoPending = true, nil
    local recovered = invoke(navigation.recover)
    if active ~= run then return false end
    run.transitioning = false
     
    run.navigationBlocked, run.rebaseNavigation = true, true
    onboarding.Tick(false)
    return recovered
end

function onboarding.Defer()
    deferred = true
    onboarding.Stop(false)
end

function onboarding.OpenHub()
    if inCombat() then return false, addon.L("TUTORIAL_COMBAT_WAIT") end
    onboarding.Stop(false)
    welcomeOffered = true
    if onboarding.watcher then onboarding.watcher:Show() end
    addon.TutorialView.ShowHub(onboarding.GetTours())
    return true
end

function onboarding.Tick(allowAuto)
    if not active or active.transitioning then return end
    local run, view = active, addon.TutorialView
    if not onboarding.HasTour(run.id) then onboarding.Stop(false); return end
    if run.tour.validate then
        local valid, err = invoke(run.tour.validate, run.context)
        if not valid then
            onboarding.Stop(false)
            report(err or addon.L("TUTORIAL_PROFILE_CHANGED"))
            return
        end
    end
    if realSessionActive() then
        onboarding.Stop(false)
        report(addon.L("TUTORIAL_SESSION_WAIT"))
        return
    end
    run.paused = inCombat() == true
    if run.paused then
        run.autoPending = nil
        if view then view.Suspend() end
        if addon.TutorialPractice then addon.TutorialPractice.SetSuspended(true) end
        return
    end
    if addon.TutorialPractice then addon.TutorialPractice.SetSuspended(false) end
    local step = run.tour.steps[run.index]
    if not invoke(run.tour.update, run.context, step) then run.failed = true end
    if active ~= run then return end
    local ok, anchor = pcall(function() return step.anchor and step.anchor(run.context) end)
    run.anchor = ok and anchor or nil
    local readyOK, ready = pcall(function() return not step.ready or step.ready(run.context) == true end)
    run.ready = readyOK and ready and not run.failed
    local navigationOK, navigation = pcall(function()
        return step.resolve and step.resolve(run.context, run.ready)
    end)
    if active ~= run then return end
    run.navigation = type(navigation) == "table" and navigation or nil
    if not navigationOK then
        report(navigation)
        run.navigation = { blocked = true, key = "TUTORIAL_RETRY" }
    end
    if run.navigation then
        run.anchor = run.navigation.anchor
        run.ready = run.ready and not run.navigation.blocked
    end
    local observedOK, observed = pcall(function()
        if step.observe then return step.observe(run.context) end
        return run.ready
    end)
    local baselineOK, baseline = pcall(function() return step.baseline and step.baseline(run.context) or observed end)
    if run.navigation and run.navigation.blocked then
        run.navigationBlocked, run.autoPending = true, nil
    elseif run.navigationBlocked then
        if step.observe or run.rebaseNavigation then
            run.autoBaseline, run.autoInitialized, run.autoPending = baselineOK and baseline or observed, true, nil
        end
        run.navigationBlocked, run.rebaseNavigation = false, false
    end
    if run.rewinding and (step.observe or step.autoAdvance)
        and not (step.replayOptional and step.replayOptional(run.context)) then
        if not run.replayBaselineSet then
            run.replayBaselineSet, run.replayBaseline = true, baselineOK and baseline or observed
            run.replayArmed = not run.ready
        elseif not run.ready or (observedOK and observed ~= nil and observed ~= run.replayBaseline) then
            run.replayArmed = true
        end
        run.ready = run.ready and run.replayArmed
    end
    if view then view.ShowStep(run, step) end
    if active ~= run then return end
    if not run.autoInitialized then
        run.autoInitialized, run.autoBaseline = true, baselineOK and baseline or observed
    end
    local changed = observedOK and observed ~= nil and observed ~= run.autoBaseline
    if run.ready and (step.observe or step.autoAdvance) and changed then
        if not run.autoPending or observed ~= run.autoObserved then run.autoPending = now() + 0.65 end
        run.autoObserved = observed
        if allowAuto ~= false and now() >= run.autoPending then
            enterStep(run.index + 1)
        end
    else
        run.autoPending = nil
    end
end

function onboarding.Initialize()
    if initialized or not addon.TutorialView then return end
    initialized = true
    local watcher = CreateFrame("Frame")
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        if active then onboarding.Tick(); return end
        if addon.TutorialView.UpdateIdle then
            addon.TutorialView.UpdateIdle(inCombat() or (addon.GameMasterService
                and addon.GameMasterService.IsSessionActive()))
        end
        if welcomeOffered or deferred or inCombat() then return end
        if not addon.Core or not addon.Core.enabled or not addon.TRP3Integration.isRegistered then return end
        if addon.Modules and not addon.Modules.IsReady() then return end
        if addon.OnboardingState.IsComplete("spellbook") then watcher:Hide(); return end
        if addon.GameMasterService and addon.GameMasterService.IsSessionActive() then return end
        welcomeOffered = true
        addon.TutorialView.ShowWelcome()
    end)
    onboarding.watcher = watcher
end

function onboarding.GetSettingsElements()
    return {
        { inherit = "TRP3_ConfigButton", title = addon.L("TUTORIAL_TITLE"),
            help = addon.L("ONBOARDING_REPLAY_HELP"), text = addon.L("TUTORIAL_TITLE"),
            callback = function()
                local step = active and active.tour.steps[active.index]
                if active and active.id == "spellbook" and step
                    and (step.id == "settings_overview" or step.id == "settings") then
                    onboarding.Tick(false)
                    return
                end
                local ok, err = onboarding.OpenHub()
                if not ok and err then report(err) end
            end },
    }
end
