local _, private = ...
local addon = private.Shared
assert(addon.Modules.Register("gameMaster", function()
    addon.Communication.Announce()
end), "Game Master module registration failed")
