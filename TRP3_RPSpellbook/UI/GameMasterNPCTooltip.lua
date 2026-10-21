local _, addon = ...

addon.GameMasterNPCTooltip = {}
local tooltip = addon.GameMasterNPCTooltip
local owner

local relationships = {
    friendly = { "GAMEMASTER_NPC_FRIENDLY", 0.2, 1, 0.25 },
    neutral = { "GAMEMASTER_NPC_NEUTRAL", 1, 0.85, 0.1 },
    hostile = { "GAMEMASTER_NPC_HOSTILE", 1, 0.25, 0.2 },
}

 
local function plain(value, limit)
    if type(value) ~= "string" then return "" end
    if type(issecretvalue) == "function" and issecretvalue(value) then return "" end
    value = value:sub(1, limit)
    value = value:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|K.-|k", "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|", ""):gsub("[%z\1-\8\11\12\14-\31\127]", "")
    return value
end

local function addIcon(icon)
    if type(GameTooltip.AddTexture) ~= "function" or not Enum or not Enum.TooltipTextureAnchor
        or not addon.TRP3Bridge or type(addon.TRP3Bridge.ResolveIconTexture) ~= "function" then return end
    if type(issecretvalue) == "function" and issecretvalue(icon) then return end
    if type(icon) == "number" then
        if icon ~= icon or icon < 1 or icon > 2147483647 or icon ~= math.floor(icon) then return end
    elseif type(icon) ~= "string" or #icon > 200 or not icon:match("^[%w_\\/%.%-]+$") then
        return
    end
    local texture = addon.TRP3Bridge.ResolveIconTexture(icon)
    if texture then
         
        GameTooltip:AddTexture(texture, { width = 24, height = 24,
            anchor = Enum.TooltipTextureAnchor.LeftCenter,
            margin = { left = 0, right = 4, top = 0, bottom = 0 } })
    end
end

function tooltip.Show(anchor, profile)
    if not GameTooltip or not anchor or type(profile) ~= "table" then return false end
    local name = plain(profile.name, 160)
    if name == "" then return false end
    local r, g, b = 1, 0.82, 0
    local color = plain(profile.nameColor, 8)
    if color:match("^%x%x%x%x%x%x$") then
        r = tonumber(color:sub(1, 2), 16) / 255
        g = tonumber(color:sub(3, 4), 16) / 255
        b = tonumber(color:sub(5, 6), 16) / 255
    end
    owner = anchor
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText(name, r, g, b)
    addIcon(profile.icon)
    local title = plain(profile.title, 160)
    if title ~= "" then GameTooltip:AddLine(title, 0.85, 0.8, 0.7, true) end
    local relation = relationships[plain(profile.relationship, 20)]
    if relation then GameTooltip:AddLine(addon.L(relation[1]), relation[2], relation[3], relation[4]) end
    local description = plain(profile.description, 2000)
    if description ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(description, 1, 1, 1, true)
    end
    GameTooltip:Show()
    return true
end

function tooltip.Hide(anchor)
    if owner and (not anchor or anchor == owner) then
        owner = nil
        if GameTooltip then GameTooltip:Hide() end
    end
end
