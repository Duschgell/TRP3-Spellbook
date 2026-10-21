local addonName, addon = ...

addon.Events = {}

local eventFrame

local function onEvent(_, event, loadedAddonName)
    if event ~= "ADDON_LOADED" or loadedAddonName ~= addonName then
        return
    end

    eventFrame:UnregisterEvent("ADDON_LOADED")
    if not addon.Core.moduleRegistered then
        addon.Core.InitializeFallback()
    end
end

function addon.Events.Initialize()
    if eventFrame then
        return
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("ADDON_LOADED")
end
