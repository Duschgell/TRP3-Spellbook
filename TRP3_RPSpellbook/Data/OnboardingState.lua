local _, addon = ...
addon.OnboardingState = {}
local state = addon.OnboardingState
local known = { spellbook = true, gameMasterPlayer = true, gameMaster = true, npc = true }
local RESET_REVISION = 1

local cachedSettings, cachedRecord
local function getRecord()
    local database = addon.Database and addon.Database.GetDB()
    if type(database) ~= "table" then return nil end
    if type(database.settings) ~= "table" then database.settings = {} end
    local settings = database.settings
    if settings ~= cachedSettings or settings.onboarding ~= cachedRecord then
        cachedRecord = addon.Schema.NormalizeOnboarding(settings)
        if cachedRecord.revision ~= RESET_REVISION then
            cachedRecord.completed, cachedRecord.progress = {}, {}
            cachedRecord.revision = RESET_REVISION
        end
        cachedSettings = settings
    end
    return cachedRecord
end

function state.IsComplete(id)
    if not known[id] then return false end
    local saved = getRecord()
    return saved ~= nil and saved.completed[id] == true
end

function state.GetProgress(id)
    local saved = known[id] and getRecord()
    return saved and saved.progress[id] or nil
end

function state.SetProgress(id, step)
    if not known[id] or type(step) ~= "string" or #step > 64 or not step:match("^[%w_]+$") then return false end
    local saved = getRecord()
    if not saved then return false end
    saved.progress[id] = step
    return true
end

function state.Complete(id)
    if not known[id] then return false end
    local saved = getRecord()
    if not saved then return false end
    saved.completed[id], saved.progress[id] = true, nil
    return true
end
