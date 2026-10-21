local _, addon = ...

addon.SoundCatalog = {}

 
local recommended = {
    { "IG_PLAYER_INVITE", 880, "INVITE" },
    { "MAP_PING", 3175, "PING" },
    { "READY_CHECK", 8960, "READY" },
    { "UI_BNET_TOAST", 18019, "BNET" },
    { "LFG_ROLE_CHECK", 17317, "ROLE" },
    { "TUTORIAL_POPUP", 7355, "TUTORIAL" },
    { "UI_GROUP_FINDER_RECEIVE_APPLICATION", 47615, "APPLICATION" },
    { "IG_QUEST_LIST_SELECT", 877, "QUEST_SELECT" },
    { "UI_BATTLEGROUND_COUNTDOWN_FINISHED", 25478, "COUNTDOWN" },
    { "ALARM_CLOCK_WARNING_1", 18871, "ALARM_SHORT" },
    { "UI_ORDERHALL_TALENT_READY_TOAST", 73280, "RESEARCH" },
    { "UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST", 73919, "RECIPE" },
    { "UI_71_SOCIAL_QUEUEING_TOAST", 79739, "SOCIAL" },
    { "UI_PET_BATTLES_TRAP_READY", 28814, "TRAP" },
    { "UI_AUTO_QUEST_COMPLETE", 23404, "QUEST_NOTICE" },
    { "UI_GARRISON_TOAST_MISSION_COMPLETE", 44294, "MISSION" },
    { "PVP_ENTER_QUEUE", 8458, "QUEUE" },
    { "ALARM_CLOCK_WARNING_3", 12889, "ALARM" },
    { "RAID_WARNING", 8959, "RAID" },
    { "UI_RAID_BOSS_WHISPER_WARNING", 37666, "BOSS_WHISPER" },
}

local function validID(id)
    return type(id) == "number" and id >= 1 and id <= 2147483647 and id == math.floor(id)
end

function addon.SoundCatalog.ParseID(text)
    text = addon.Runtime.Trim(text)
    if not text or #text > 10 or not text:match("^%d+$") then return nil end
    local preset = addon.Runtime.NormalizeSoundPreset("kit:" .. text)
    return preset and tonumber(preset:sub(5)) or nil
end

function addon.SoundCatalog.GetRecommended()
    local result = {}
    local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
    for _, entry in ipairs(recommended) do
        local id = validID(kits[entry[1]]) and kits[entry[1]] or entry[2]
        result[#result + 1] = { id = id, name = addon.L("SOUND_CHOICE_" .. entry[3]), key = entry[1] }
    end
    return result
end

function addon.SoundCatalog.GetAll()
    local result, seen = {}, {}
    local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
    local names = {}
    for name, id in pairs(kits) do
        if type(name) == "string" and #name <= 160 and name:match("^[A-Z0-9_]+$") and validID(id) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local id = kits[name]
        if not seen[id] then
            result[#result + 1] = { id = id, name = name, key = name }
            seen[id] = true
        end
    end
    for _, entry in ipairs(addon.SoundCatalog.GetRecommended()) do
        if not seen[entry.id] then
            result[#result + 1] = entry
            seen[entry.id] = true
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function addon.SoundCatalog.GetPresetID(preset)
    preset = addon.Runtime.NormalizeSoundPreset(preset)
    if not preset then return nil end
    if preset:match("^kit:") then return tonumber(preset:sub(5)) end
    local keys = { ready = "READY_CHECK", whisper = "TELL_MESSAGE", soft = "IG_MAINMENU_OPTION_CHECKBOX_ON" }
    local fallbacks = { ready = 8960, whisper = 3081, soft = 856 }
    local id = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[keys[preset]]
    return validID(id) and id or fallbacks[preset]
end
