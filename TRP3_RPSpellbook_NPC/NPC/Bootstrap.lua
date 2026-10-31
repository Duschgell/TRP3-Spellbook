local _, private = ...
local core = _G.TRP3_RPSpellbookAddon
assert(type(core) == "table", "NPC archive requires TRP3_RPSpellbook")
private.Shared = core
core.NPCArchive = { Version = "1.2.0" }
