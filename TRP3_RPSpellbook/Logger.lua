local addonName, addon = ...

addon.Logger = {}

local function write(message)
    local formattedMessage = string.format("|cffffb347%s:|r %s", addonName, tostring(message))

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(formattedMessage)
    else
        print(formattedMessage)
    end
end

function addon.Logger.Info(message)
    write(message)
end

function addon.Logger.Error(message)
    write(message)
end
