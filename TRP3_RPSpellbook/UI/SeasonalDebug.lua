local _, addon = ...

addon.SeasonalDebug = {}
local slashKey, slashAlias = "TRP3RPSBSEASON", "/sbseason"
local validThemes = {
    winterveil = true, lunar = true, love = true, noblegarden = true, children = true, midsummer = true,
    brewfest = true, harvest = true, hallowsend = true, dayofthedead = true, pilgrim = true,
}

local function report(message)
    if addon.Logger and type(addon.Logger.Info) == "function" then
        addon.Logger.Info("Seasonal debug: " .. message)
    end
end

local function handleCommand(input)
    if input == nil then input = "" end
    if type(input) ~= "string" or #input > 128 or input:find("%c") then
        report("invalid command. Use /sbseason list.")
        return
    end
    local command = input:match("^%s*(.-)%s*$"):lower()
    local visuals = addon.SeasonalVisuals
    if command == "" or command == "list" then
        if type(visuals) == "table" and type(visuals.GetThemes) == "function" then
            local listed, seen = {}, {}
            local available = visuals.GetThemes()
            for _, name in ipairs(type(available) == "table" and available or {}) do
                if validThemes[name] and not seen[name] then listed[#listed + 1] = name; seen[name] = true end
            end
            report("themes: " .. table.concat(listed, ", ") .. ".")
            if type(visuals.GetDebugTheme) == "function" then
                local current = visuals.GetDebugTheme()
                if current == "auto" or current == "off" or validThemes[current] then report("mode: " .. current .. ".") end
            end
        else
            report("visual API unavailable.")
        end
        report("/sbseason <theme> | auto | off | list. Session only; auto uses calendar, off hides seasonal decorations.")
        return
    end
    if validThemes[command] or command == "auto" or command == "off" then
        if type(visuals) ~= "table" or type(visuals.SetDebugTheme) ~= "function" then
            report("visual API unavailable.")
        elseif visuals.SetDebugTheme(command) then
            if command == "auto" then report("automatic calendar restored (session only).")
            elseif command == "off" then report("seasonal decorations hidden (session only).")
            else report("theme selected: " .. command .. " (session only).") end
        else
            report("theme selection unavailable; unchanged.")
        end
        return
    end
    report("unknown command. Use /sbseason list.")
end

function addon.SeasonalDebug.Initialize()
    local commands = _G.SlashCmdList
    if type(commands) == "table" and commands[slashKey] == handleCommand
        and _G["SLASH_" .. slashKey .. "1"] == slashAlias then return true end
    if commands ~= nil and type(commands) ~= "table" then report("slash registration unavailable."); return false end
    if commands and commands[slashKey] ~= nil then
        report("slash registration collision; existing command preserved.")
        return false
    end
    for key, value in pairs(_G) do
        if type(key) == "string" and key:match("^SLASH_.+%d+$") then
            if key:match("^SLASH_" .. slashKey .. "%d+$")
                or (type(value) == "string" and value:lower() == slashAlias) then
                report("slash registration collision; existing alias preserved.")
                return false
            end
        end
    end
    if commands == nil then commands = {}; _G.SlashCmdList = commands end
    _G["SLASH_" .. slashKey .. "1"] = slashAlias
    commands[slashKey] = handleCommand
    return true
end
