local _, addon = ...

addon.GameMasterActionPresentation = {}

local function getTargets(submission)
    if type(submission) ~= "table" then
        return {}
    end
    if type(submission.targets) == "table" and #submission.targets > 0 then
        return submission.targets
    end
    return type(submission.target) == "table" and { submission.target } or {}
end

local function getTargetLabel(target)
    if type(target) ~= "table" then
        return nil
    end
    local label = target.label or target.name or target.value
    if label == nil or tostring(label) == "" then
        return nil
    end
    return tostring(label)
end

function addon.GameMasterActionPresentation.GetTargets(submission)
    return getTargets(submission)
end

function addon.GameMasterActionPresentation.GetTargetOverview(submission)
    local overview = {}
    for _, target in ipairs(getTargets(submission)) do
        local label = getTargetLabel(target)
        if label then
            overview[#overview + 1] = {
                color = target.color,
                icon = target.icon,
                kind = target.kind,
                label = label,
            }
        end
    end
    return overview
end

function addon.GameMasterActionPresentation.FormatTargetSummary(submission)
    local targets = addon.GameMasterActionPresentation
        .GetTargetOverview(submission)
    if #targets == 0 then
        return addon.L("GAMEMASTER_NO_TARGET")
    end
    if #targets == 1 then
        return targets[1].label
    end
    return addon.L("GAMEMASTER_TARGET_SUMMARY", #targets)
end

function addon.GameMasterActionPresentation.FormatTargets(submission, maximum)
    local labels = {}
    local targets = addon.GameMasterActionPresentation
        .GetTargetOverview(submission)
    maximum = math.max(1, math.floor(tonumber(maximum) or #targets))
    for index, target in ipairs(targets) do
        if index > maximum then
            break
        end
        labels[#labels + 1] = target.label
    end
    if #targets > maximum then
        labels[#labels + 1] = addon.L(
            "GAMEMASTER_MORE_TARGETS",
            #targets - maximum
        )
    end
    return #labels > 0
        and table.concat(labels, ", ")
        or addon.L("GAMEMASTER_NO_TARGET")
end

function addon.GameMasterActionPresentation.FormatPreparation(submission)
    local preparation = type(submission) == "table"
        and submission.preparation
        or nil
    local progress = preparation and tonumber(preparation.progress)
    local required = preparation and tonumber(preparation.required)
    if not progress or not required then
        return nil
    end
    return addon.L(
        "GAMEMASTER_PREPARATION_PROGRESS",
        math.max(0, math.floor(progress)),
        math.max(1, math.floor(required))
    )
end
