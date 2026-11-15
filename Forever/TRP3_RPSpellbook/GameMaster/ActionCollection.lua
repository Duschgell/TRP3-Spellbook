local _, addon = ...

addon.GameMasterActionCollection = {}

local actionFields = {
    "action",
    "aoe",
    "emote",
    "preparation",
    "spell",
    "submissionId",
    "submittedAt",
    "target",
    "targets",
}

local function isAction(value)
    return type(value) == "table"
        and addon.Constants.GAMEMASTER_ACTIONS[value.action] == true
        and type(value.spell) == "table"
end

function addon.GameMasterActionCollection.Get(submission)
    if type(submission) ~= "table" then
        return {}
    end
    local actions = submission.actions
    if type(actions) == "table" then
        local count = addon.Runtime.GetBoundedArrayLength(
            actions,
            addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
        )
        if count and count > 0 then
            for index = 1, count do
                if not isAction(actions[index]) then
                    return {}
                end
            end
            return actions
        end
    end
    return isAction(submission) and { submission } or {}
end

function addon.GameMasterActionCollection.Count(submission)
    return #addon.GameMasterActionCollection.Get(submission)
end

function addon.GameMasterActionCollection.GetLatest(submission)
    local actions = addon.GameMasterActionCollection.Get(submission)
    return actions[#actions]
end

function addon.GameMasterActionCollection.ContainsPreparation(submission)
    for _, action in ipairs(addon.GameMasterActionCollection.Get(submission)) do
        if action.action == "prepare" then
            return true
        end
    end
    return false
end

function addon.GameMasterActionCollection.Set(container, actions)
    if type(container) ~= "table" or type(actions) ~= "table" then
        return nil
    end
    local count = addon.Runtime.GetBoundedArrayLength(
        actions,
        addon.Constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER
    )
    if not count or count < 1 then
        return nil
    end
    for index = 1, count do
        if not isAction(actions[index]) then
            return nil
        end
    end
    local latest = actions[count]
    container.actions = actions
    for _, field in ipairs(actionFields) do
        container[field] = latest[field]
    end
    return container
end
