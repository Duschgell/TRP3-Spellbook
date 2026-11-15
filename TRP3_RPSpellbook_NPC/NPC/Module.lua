local _, private = ...
local addon = private.Shared or private
local archive = addon.NPCArchive

local function initialize()
    if archive.ready then return true end
    local ok, err = archive.Initialize()
    if not ok then return false, archive.L(err) end
    local events = CreateFrame("Frame")
    events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    events:SetScript("OnEvent", function(_, _, spellID, success)
        archive.OnSpellDataResult(spellID, success)
    end)
     
    archive.ready = true
    return true
end

 
addon.Modules.Register("npc", initialize)
