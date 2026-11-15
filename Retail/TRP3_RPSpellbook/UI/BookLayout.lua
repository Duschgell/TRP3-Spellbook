local _, addon = ...

local layout = {
    Font = "Fonts\\FRIZQT__.TTF",
    Ink = { icon = 0.82, name = 0.88, body = 0.86 },
    IconHighlight = { 1, 0.94, 0.84 },
    IconDesaturation = 0.25,
}
addon.BookLayout = layout
local unpackValues = unpack or table.unpack

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function layout.TextInk(region, enabled, opacity)
    if not region then return end
    local original = region.bookTextInk
    if not enabled then
        if original then
            region:SetShadowColor(unpackValues(original.shadow))
            region:SetShadowOffset(unpackValues(original.offset))
            region:SetAlpha(original.alpha)
            region.bookTextInk = nil
        end
        return
    end
    if not original then
        original = { alpha = region:GetAlpha(), shadow = { region:GetShadowColor() },
            offset = { region:GetShadowOffset() } }
        region.bookTextInk = original
    end
     
    region:SetAlpha(original.alpha * opacity)
    region:SetShadowColor(0, 0, 0, 0)
    region:SetShadowOffset(0, 0)
end

function layout.SetNameColor(region, color, fallback, fancy)
    if not fancy then layout.TextInk(region, false) end
    addon.UIFactory.SetFontColor(region, color, fallback)
    if not fancy then return end
     
    layout.TextInk(region, true, layout.Ink.name)
end

function layout.IconInk(icon, enabled)
    local original = icon.bookIconInk
    if not enabled then
        if original then
            icon:SetTexCoord(unpackValues(original.coords))
            icon:SetBlendMode(original.blend)
            icon:SetDesaturation(original.desaturation)
            icon:SetVertexColor(unpackValues(original.color))
            icon:SetAlpha(original.alpha)
            icon.bookIconInk = nil
        end
        return
    end
    if not original then
        original = { alpha = icon:GetAlpha(), coords = { icon:GetTexCoord() }, blend = icon:GetBlendMode(),
            desaturation = icon:GetDesaturation(), color = { icon:GetVertexColor() } }
        icon.bookIconInk = original
    end
    local uv, crop = original.coords, 0.07
    local function corner(x, y)
        local leftX, leftY = uv[1] + (uv[3] - uv[1]) * y, uv[2] + (uv[4] - uv[2]) * y
        local rightX, rightY = uv[5] + (uv[7] - uv[5]) * y, uv[6] + (uv[8] - uv[6]) * y
        return leftX + (rightX - leftX) * x, leftY + (rightY - leftY) * x
    end
     
    local ulX, ulY = corner(crop, crop)
    local llX, llY = corner(crop, 1 - crop)
    local urX, urY = corner(1 - crop, crop)
    local lrX, lrY = corner(1 - crop, 1 - crop)
    icon:SetTexCoord(ulX, ulY, llX, llY, urX, urY, lrX, lrY)
    icon:SetBlendMode("BLEND")
     
    icon:SetDesaturation(layout.IconDesaturation)
    icon:SetVertexColor(layout.IconHighlight[1], layout.IconHighlight[2], layout.IconHighlight[3], original.color[4])
     
    icon:SetAlpha(original.alpha * layout.Ink.icon)
end

function layout.SetSpellIcon(icon, spell, fallback, visible, fancy)
     
    layout.IconInk(icon, false)
    addon.UIFactory.SetSpellIcon(icon, spell, fallback, visible)
    if fancy then layout.IconInk(icon, true) end
end

 
 
function layout.Plan(width, height, columns, rows)
    width, height = math.max(1, width), math.max(1, height)
    columns, rows = math.max(1, columns), math.max(1, rows)
    local gutter = math.min(width / 8, clamp(width * 0.045, 18, 64))
    local margin = math.min(16, height * 0.025, math.max(0, (height - rows) / 2))
    local gap = math.min(height / (rows * 4), clamp(height * 0.025, 8, 24))
    local columnWidth = math.max(1, (width - (columns - 1) * gutter) / columns)
    local rowHeight = math.max(1, (height - margin * 2 - (rows - 1) * gap) / rows)
    local scale = clamp(math.min(columnWidth / 230, rowHeight / 86), 1, 1.28)
    local entryHeight = math.min(rowHeight, 138 * scale)
    local entryWidth = math.min(columnWidth, 480 * scale)
    return {
        width = entryWidth, height = entryHeight,
        columnPitch = columnWidth + gutter, rowPitch = rowHeight + gap,
        left = (columnWidth - entryWidth) / 2,
        top = margin + (rowHeight - entryHeight) / 2,
        iconSize = math.floor(34 * scale + 0.5),
        titleSize = math.floor(17 * scale + 0.5),
        bodySize = math.floor(13 * scale + 0.5),
    }
end

local function plainInk(text)
    text = type(text) == "string" and text or ""
     
    return text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
end

function layout.Excerpt(spell)
    local text = plainInk(spell.description)
    if text == "" then
        text = plainInk(addon.SpellPresentation.GetClassificationSummary(spell.tags, spell.effects))
    end
     
    local position, count = 1, 0
    while position <= #text and count < 280 do
        local byte = text:byte(position)
        position = position + (byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1)
        count = count + 1
    end
    if position <= #text then return text:sub(1, position - 1) .. "..." end
    return text
end

function layout.Entry(slot, plan)
    slot.bookLayout = plan
    slot.icon:ClearAllPoints()
    slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -3)
    slot.icon:SetSize(plan.iconSize, plan.iconSize)
    local width = math.max(1, plan.width - plan.iconSize - 16)
    slot.name:ClearAllPoints()
    slot.name:SetPoint("TOPLEFT", slot.icon, "TOPRIGHT", 10, -1)
    slot.name:SetFont(layout.Font, plan.titleSize, "")
    slot.name:SetJustifyV("TOP")
    slot.name:SetMaxLines(2)
    slot.name:SetWidth(width)
    slot.name:SetHeight(0)
    local nameHeight = math.min(plan.titleSize * 2 + 4, math.max(plan.titleSize + 2, slot.name:GetStringHeight()))
    slot.name:SetHeight(nameHeight)
    slot.excerpt:ClearAllPoints()
    slot.excerpt:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -7)
    slot.excerpt:SetFont(layout.Font, plan.bodySize, "")
    slot.excerpt:SetWidth(width)
    local lines = math.max(0, math.min(5, math.floor((plan.height - nameHeight - 14) / (plan.bodySize + 3))))
    slot.excerpt:SetMaxLines(math.max(1, lines))
    slot.excerpt:SetHeight(math.max(1, lines * (plan.bodySize + 3)))
    slot.excerpt:SetShown(lines > 0 and slot.excerpt:GetText() ~= "")
    layout.TextInk(slot.name, true, layout.Ink.name)
    layout.TextInk(slot.excerpt, true, layout.Ink.body)
end
