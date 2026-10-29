local _, addon = ...

addon.SeasonalOrnaments = {}
local palette = {
    pink = { 1, 0.38, 0.55, 0.9 }, gold = { 0.95, 0.68, 0.18, 0.9 },
    green = { 0.35, 0.6, 0.21, 0.9 }, orange = { 1, 0.45, 0.12, 0.95 },
    cream = { 1, 0.93, 0.72, 0.95 }, dark = { 0.15, 0.08, 0.05, 0.95 },
}
local pastels = { { 0.85, 0.57, 0.92, 0.95 }, { 0.55, 0.85, 0.64, 0.95 }, { 1, 0.79, 0.4, 0.95 } }
local flags = { palette.orange, { 0.3, 0.65, 1, 0.95 }, palette.pink, palette.green, palette.gold }

local function region(painter, x, y, width, height)
    painter.used = painter.used + 1
    local texture = painter.textures[painter.used]
    if not texture then
        texture = painter.frame:CreateTexture(nil, "ARTWORK")
        painter.textures[painter.used] = texture
    end
    if texture.seasonalMaskAttached then
        texture:RemoveMaskTexture(texture.seasonalMask)
        texture.seasonalMaskAttached = false
    end
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", painter.frame, "CENTER", x, y)
    texture:SetSize(width, height)
    texture:SetBlendMode("BLEND")
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetAlpha(1)
    texture:Show()
    return texture
end

local function fill(painter, x, y, width, height, color, rounded)
    local texture = region(painter, x, y, width, height)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    if rounded then
        if not texture.seasonalMask then
            local mask = painter.frame:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture.seasonalMask = mask
        end
        texture:AddMaskTexture(texture.seasonalMask)
        texture.seasonalMaskAttached = true
    end
end

local function stroke(painter, x1, y1, x2, y2, color, thickness)
    painter.usedLines = painter.usedLines + 1
    local line = painter.lines[painter.usedLines]
    if not line then line = painter.frame:CreateLine(nil, "OVERLAY"); painter.lines[painter.usedLines] = line end
    line:SetStartPoint("CENTER", painter.frame, x1, y1)
    line:SetEndPoint("CENTER", painter.frame, x2, y2)
    line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    line:SetThickness(thickness or 1.4)
    line:Show()
end

local motifs = {}

function motifs.hearts(p)
    stroke(p, -4, 2, 0, -5, palette.pink, 5)
    stroke(p, 4, 2, 0, -5, palette.pink, 5)
    fill(p, -3, 3, 7, 7, palette.pink, true)
    fill(p, 3, 3, 7, 7, palette.pink, true)
end

function motifs.eggs(p, index)
    fill(p, 0, 0, 11, 16, pastels[(index - 1) % #pastels + 1], true)
    fill(p, 0, 0, 9, 2, palette.cream)
    fill(p, -2, 3, 2, 2, palette.cream, true)
    fill(p, 2, -3, 2, 2, palette.cream, true)
end

function motifs.bunting(p, index)
    local color = flags[(index - 1) % #flags + 1]
    for row = 1, 6 do fill(p, 0, 6 - row * 2, 15 - row * 2, 2, color) end
end

function motifs.flames(p)
    stroke(p, 0, -9, 0, -2, palette.dark, 3)
    fill(p, 0, 2, 10, 17, palette.orange, true)
    stroke(p, 2, 8, 0, 12, palette.orange, 2)
    fill(p, 0, 0, 5, 10, palette.gold, true)
    fill(p, 0, -2, 2, 5, palette.cream, true)
end

function motifs.mugs(p)
    stroke(p, 4, 3, 8, 3, palette.gold, 2)
    stroke(p, 8, 3, 8, -3, palette.gold, 2)
    stroke(p, 8, -3, 4, -3, palette.gold, 2)
    fill(p, 0, -1, 10, 12, palette.gold)
    fill(p, 0, -6, 10, 3, palette.gold, true)
    for x = -3, 3, 3 do fill(p, x, 6, 6, 4, palette.cream, true) end
    fill(p, -2, 0, 1, 7, palette.cream)
end

function motifs.leaves(p, index)
    local texture = region(p, 0, 0, 20, 20)
    texture:SetTexture(index % 2 == 0 and 166456 or 166454)
    texture:SetTexCoord(0, 1, 0, 1)
end

function motifs.pumpkins(p)
    fill(p, 0, 0, 17, 13, palette.orange, true)
    stroke(p, -3, -5, -3, 5, { 0.7, 0.24, 0.05, 0.5 }, 1)
    stroke(p, 3, -5, 3, 5, { 0.7, 0.24, 0.05, 0.5 }, 1)
    fill(p, 0, 8, 3, 4, palette.green)
    fill(p, -3, 1, 2, 2, palette.dark)
    fill(p, 3, 1, 2, 2, palette.dark)
    fill(p, 0, -3, 7, 1.5, palette.dark)
end

function motifs.flowers(p)
    stroke(p, 0, -9, 0, -1, palette.green, 1.5)
    for index = 1, 6 do
        local angle = index * math.pi / 3
        fill(p, math.cos(angle) * 4, math.sin(angle) * 4 + 2, 6, 6, palette.orange, true)
    end
    fill(p, 0, 2, 5, 5, palette.gold, true)
end

function motifs.roses(p, index)
    local color = index % 2 == 0 and palette.pink or { 0.8, 0.08, 0.18, 0.95 }
    stroke(p, -14, 0, 14, -1, palette.green, 4)
    fill(p, -9, 3, 10, 5, palette.green, true)
    fill(p, 9, -3, 10, 5, palette.green, true)
    for petal = 1, 5 do
        local angle = petal * math.pi * 0.4
        fill(p, math.cos(angle) * 4, math.sin(angle) * 4, 8, 8, color, true)
    end
    fill(p, 0, 0, 4, 4, palette.cream, true)
end

function motifs.skulls(p)
    fill(p, 0, 0, 22, 24, palette.cream, true)
    local texture = p.textures[p.used]
    texture:SetTexture(307568)
    texture:SetTexCoord(0.12, 0.88, 0.08, 0.9)
    texture:SetVertexColor(1, 1, 1, 0.9)
end

function motifs.corn(p)
    stroke(p, -4, -7, 2, 7, palette.green, 2)
    stroke(p, -2, -8, 5, 4, palette.green, 2)
    fill(p, 0, 0, 9, 17, palette.gold, true)
    for row = -4, 4, 4 do
        stroke(p, -3, row, 3, row, palette.orange, 1)
    end
    stroke(p, 0, -6, 0, 6, palette.orange, 1)
end

function addon.SeasonalOrnaments.Paint(frame, kind, index)
    local draw = motifs[kind]
    if not draw then return false end
    local painter = frame.seasonalPainter
    if not painter then
        painter = { frame = frame, textures = {}, lines = {} }
        frame.seasonalPainter = painter
    end
    painter.used, painter.usedLines = 0, 0
    draw(painter, index)
    for position = painter.used + 1, #painter.textures do painter.textures[position]:SetShown(false) end
    for position = painter.usedLines + 1, #painter.lines do painter.lines[position]:SetShown(false) end
    frame.seasonalMotif = kind
    return true
end
