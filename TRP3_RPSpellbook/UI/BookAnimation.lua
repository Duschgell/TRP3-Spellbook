local _, addon = ...

 
 
local states = setmetatable({}, { __mode = "k" })
local BookAnimation = {}
addon.BookAnimation = BookAnimation

local DURATIONS = {
    open = 0.24,
    close = 0.20,
    page = 0.16,
    focus = 0.12,
    unfocus = 0.12,
    write = 0.14,
    move = 0.20,
}

local function call(method, object, ...)
    if object and type(object[method]) == "function" then
        return pcall(object[method], object, ...)
    end
    return false
end

local function value(method, object, fallback)
    local ok, result = call(method, object)
    if ok and type(result) == "number" then return result end
    return fallback
end

local function fire(callback)
    if type(callback) == "function" then callback() end
end

local function reset(state)
    local frame = state.frame
    if state.restoreAlpha ~= nil then call("SetAlpha", frame, state.restoreAlpha) end
    if state.restoreScale ~= nil then call("SetScale", frame, state.restoreScale) end
    if state.fold then
        call("SetAlpha", state.fold, 0)
        call("Hide", state.fold)
    end
end

local function cancel(state)
    state.generation = state.generation + 1
    state.callback = nil
    state.phase = nil
    state.stopping = true
    call("Stop", state.first)
    call("Stop", state.second)
    state.stopping = false
    state.playing = false
    reset(state)
end

local function complete(state, token, invoke)
    if state.generation ~= token or not state.playing then return end
    local callback = state.callback
    state.callback = nil
    state.phase = nil
    state.playing = false
    reset(state)
    if invoke then fire(callback) end
end

local function configureAnimation(animation, duration, alphaFrom, alphaTo, scaleFromX,
        scaleFromY, scaleToX, scaleToY, origin, offsetX, offsetY)
    call("SetDuration", animation.alpha, duration)
    call("SetFromAlpha", animation.alpha, alphaFrom)
    call("SetToAlpha", animation.alpha, alphaTo)
    call("SetSmoothing", animation.alpha, "IN_OUT")

    call("SetDuration", animation.scale, duration)
    call("SetScaleFrom", animation.scale, scaleFromX, scaleFromY)
    call("SetScaleTo", animation.scale, scaleToX, scaleToY)
    call("SetOrigin", animation.scale, origin or "CENTER", 0, 0)
    call("SetSmoothing", animation.scale, "IN_OUT")

    call("SetDuration", animation.translation, duration)
    call("SetOffset", animation.translation, offsetX or 0, offsetY or 0)
    call("SetSmoothing", animation.translation, "IN_OUT")
end

local function createGroup(frame)
    local ok, group = call("CreateAnimationGroup", frame)
    if not ok or not group then return nil end

    local _, alpha = call("CreateAnimation", group, "Alpha")
    local _, scale = call("CreateAnimation", group, "Scale")
    local _, translation = call("CreateAnimation", group, "Translation")
    if not alpha or not scale or not translation
        or type(group.Play) ~= "function" or type(group.Stop) ~= "function"
        or type(group.SetScript) ~= "function" then
        return nil
    end
    return { group = group, alpha = alpha, scale = scale, translation = translation }
end

local function createFold(frame)
    if type(frame.CreateTexture) ~= "function" then return nil end
    local ok, fold = pcall(frame.CreateTexture, frame, nil, "OVERLAY", nil, 7)
    if not ok or not fold then return nil end
    call("SetAllPoints", fold, frame)
    call("SetTexture", fold, 375503)
    call("SetTexCoord", fold, 0.20, 0.90, 0.10, 0.90)
    call("SetBlendMode", fold, "BLEND")
    call("SetAlpha", fold, 0)
    call("Hide", fold)
    return fold
end

local function ensureState(frame)
    local state = states[frame]
    if state then return state end
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return nil end

    local first, second = createGroup(frame), createGroup(frame)
    if not first or not second then return nil end
    state = {
        frame = frame,
        first = first.group,
        second = second.group,
        animation = { first = first, second = second },
        generation = 0,
    }
    states[frame] = state
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnHide", function()
            cancel(state)
        end)
    end
    return state
end

local function isVisible(frame)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
    if type(frame.IsVisible) == "function" then
        local ok, visible = call("IsVisible", frame)
        if ok and type(visible) == "boolean" then return visible end
    end
    if type(frame.IsShown) ~= "function" then return true end
    local ok, shown = call("IsShown", frame)
    return ok and shown ~= false
end

local function bindStop(state, group, token)
    group:SetScript("OnStop", function()
        if not state.stopping and state.generation == token then cancel(state) end
    end)
end

local function startGroup(state, animation, token, phase, reverse)
    local group = animation.group
    bindStop(state, group, token)
    group:SetScript("OnFinished", function()
        if state.generation ~= token or not state.playing then return end
        if phase == "midpoint" then
            local callback = state.callback
            state.callback = nil
            fire(callback)
            if state.generation ~= token or not state.playing then return end
            state.phase = "finish"
            local nextAnimation = state.animation.second
            local ok = pcall(nextAnimation.group.Play, nextAnimation.group)
            if not ok then complete(state, token, false) end
        elseif phase == "return" then
            state.phase = "finish"
            local nextAnimation = state.animation.second
            local ok = pcall(nextAnimation.group.Play, nextAnimation.group)
            if not ok then complete(state, token, false) end
        else
            complete(state, token, true)
        end
    end)
    local ok = pcall(group.Play, group, reverse == true)
    return ok
end

local function start(frame, kind, callback, direction, moveOffset)
    local settings = addon.SpellCreationSettings
    if settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() then
        BookAnimation.Stop(frame)
        fire(callback)
        return false
    end
    if not DURATIONS[kind] or not isVisible(frame) then
        fire(callback)
        return false
    end
    local state = ensureState(frame)
    if not state then
        fire(callback)
        return false
    end
    cancel(state)

    state.restoreAlpha = value("GetAlpha", frame)
    state.restoreScale = value("GetScale", frame)
    state.generation = state.generation + 1
    state.callback = callback
    state.playing = true
    local token = state.generation
    local alpha = state.restoreAlpha or 1
    local dimAlpha = state.restoreAlpha and alpha * 0.82 or alpha
    local foldAlpha = state.restoreAlpha and alpha * 0.28 or alpha
    local foldX = state.restoreScale and 0.08 or 1
    local writeAlpha = state.restoreAlpha and 0 or alpha
    local first, second = state.animation.first, state.animation.second
    local origin = direction == -1 and "LEFT" or "RIGHT"
    local duration = DURATIONS[kind]
    local phase, reverse = "finish", false

    if kind == "open" then
        configureAnimation(first, duration, foldAlpha, alpha, foldX, 1, 1, 1, "LEFT")
    elseif kind == "close" then
        configureAnimation(first, duration, alpha, foldAlpha, 1, 1, foldX, 1, "RIGHT")
    elseif kind == "page" then
        if not state.fold then state.fold = createFold(frame) end
        if state.fold then
            call("SetAlpha", state.fold, 0.18)
            call("Show", state.fold)
        end
        configureAnimation(first, duration, alpha, foldAlpha, 1, 1, foldX, 1, origin)
        configureAnimation(second, duration, foldAlpha, alpha, foldX, 1, 1, 1, origin)
        phase = "midpoint"
    elseif kind == "focus" then
        configureAnimation(first, duration, alpha, dimAlpha, 1, 1, 1.035, 1.035, "CENTER")
        configureAnimation(second, duration, dimAlpha, alpha, 1.035, 1.035, 1, 1, "CENTER")
        phase = "midpoint"  
    elseif kind == "unfocus" then
        configureAnimation(first, duration, alpha, dimAlpha, 1, 1, 0.98, 0.98, "CENTER")
        configureAnimation(second, duration, dimAlpha, alpha, 0.98, 0.98, 1, 1, "CENTER")
        phase = "return"  
    elseif kind == "write" then
        configureAnimation(first, 0.32, alpha, writeAlpha, 1, 1, 1, 1, "CENTER")
        configureAnimation(second, 0.68, writeAlpha, alpha, 1, 1, 1, 1, "CENTER")
        phase = "midpoint"  
    else  
        local offset = moveOffset or { x = 0, y = 0 }
        configureAnimation(first, duration, alpha, alpha, 1, 1, 1, 1, "CENTER", offset.x, offset.y)
        reverse = true
    end

     
     
    bindStop(state, second.group, token)
    second.group:SetScript("OnFinished", function()
        complete(state, token, true)
    end)

    if not startGroup(state, first, token, phase, reverse) then
        cancel(state)
        fire(callback)
        return false
    end
    return true
end

 
 
 
function BookAnimation.Play(frame, kind, callback, direction)
    if kind == "page" and direction ~= 1 and direction ~= -1 then direction = 1 end
    return start(frame, kind, callback, direction)
end

 
function BookAnimation.Stop(frame)
    if not frame then return false end
    local state = states[frame]
    if not state then return false end
    local wasPlaying = state.playing == true
    cancel(state)
    return wasPlaying
end

function BookAnimation.Finish(frame)
    local state = frame and states[frame]
    if not state or not state.playing then return false end
    local callback = state.callback
    cancel(state)
    fire(callback)
    return true
end

function BookAnimation.IsPlaying(frame)
    if not frame then return false end
    local state = states[frame]
    if not state or not state.playing then return false end
    local ok, playing = call("IsPlaying", state.first)
    if ok and playing == true then return true end
    ok, playing = call("IsPlaying", state.second)
    return ok and playing == true
end

local function stableID(frame, keyField)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return nil end
    local id = frame and frame[keyField]
    if id == nil and type(frame.GetID) == "function" then
        local ok, value = call("GetID", frame)
        if ok then id = value end
    end
    if type(id) ~= "string" and type(id) ~= "number" then return nil end
    return id
end

 
function BookAnimation.Capture(frames, keyField)
    local snapshot = {}
    keyField = keyField or "id"
    for _, frame in ipairs(frames or {}) do
        local id = stableID(frame, keyField)
        if id then
            local left = value("GetLeft", frame)
            local top = value("GetTop", frame)
            if left and top then snapshot[id] = { left = left, top = top } end
        end
    end
    return snapshot
end

 
function BookAnimation.Reflow(frames, snapshot, keyField)
    local started = 0
    keyField = keyField or "id"
    for _, frame in ipairs(frames or {}) do
        local prior = snapshot and snapshot[stableID(frame, keyField)]
        local left, top = value("GetLeft", frame), value("GetTop", frame)
        if prior and left and top then
             
            local offset = { x = prior.left - left, y = prior.top - top }
            if offset.x ~= 0 or offset.y ~= 0 then
                if start(frame, "move", nil, nil, offset) then started = started + 1 end
            end
        end
    end
    return started
end
