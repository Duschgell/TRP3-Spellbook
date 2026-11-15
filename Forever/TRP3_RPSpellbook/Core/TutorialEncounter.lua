local _, addon = ...
addon.TutorialEncounter = {}
local encounter = addon.TutorialEncounter

function encounter.New(role)
    return {
        role = role, created = role == "player", round = role == "player" and 1 or 0,
        locked = false, finished = false, completed = {}, actions = {}, history = {},
        visibility = "full", target = nil, selectedSpell = "spark", preparation = nil,
        visibilityChanges = 0, minimized = false, restored = false,
        order = { "player", "ally", "enemy" }, inactive = {},
    }
end

function encounter.Create(state, name)
    if state.role ~= "gm" or state.created or type(name) ~= "string" then return false end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 100 then return false end
    state.name, state.created, state.round = name, true, 1
    return true
end

function encounter.Cast(state, spell, target)
    if not state.created or state.finished or state.locked or state.completed[state.round]
        or not ({ spark = true, shield = true, ritual = true })[spell]
        or not ({ player = true, ally = true, enemy = true })[target] then return false end
    if state.actions[state.round] then return false end
    if state.role == "player" and ((state.round == 1 and spell == "ritual")
        or (state.round == 2 and spell ~= "ritual")) then return false end
    local action = { spell = spell, target = target, round = state.round }
    if spell == "ritual" then
        action.preparing = true
        state.preparation = { target = target, readyRound = state.round + 1 }
    end
    state.actions[state.round] = action
    return true
end

function encounter.CompleteTurn(state)
    if not state.created or state.locked or not state.actions[state.round] then return false end
    state.completed[state.round] = true
    return true
end

function encounter.ToggleLock(state)
    if state.role ~= "gm" or not state.created or state.finished then return false end
    state.locked = not state.locked
    return true
end

function encounter.Advance(state)
    if not state.created or state.finished then return false end
    if state.role == "gm" then
        if not state.locked then return false end
    elseif not state.completed[state.round] then
        return false
    end
    state.history[state.round] = { own = state.actions[state.round], ally = "shield", enemy = "spark" }
    if state.round == 3 then state.finished = true; return true end
    state.round, state.locked = state.round + 1, false
    if state.role == "player" and state.round == 2 then state.selectedSpell = "ritual" end
    if state.preparation and state.preparation.readyRound <= state.round then
        state.actions[state.round] = { spell = "ritual", target = state.preparation.target,
            round = state.round, released = true }
        state.preparation = nil
    end
    return true
end

function encounter.CycleVisibility(state)
    if state.role ~= "gm" or not state.created then return false end
    local nextMode = { full = "targets", targets = "hidden", hidden = "full" }
    state.visibility = nextMode[state.visibility]
    state.visibilityChanges = state.visibilityChanges + 1
    return true
end

function encounter.MoveParticipant(state, id)
    if state.role ~= "gm" or state.finished then return false end
    for i, current in ipairs(state.order) do
        if current == id then
            local target = i == 1 and #state.order or i - 1
            table.remove(state.order, i)
            table.insert(state.order, target, id)
            state.reordered = true
            return true
        end
    end
    return false
end
