local _, addon = ...

addon.SeasonalStyles = {}

local order = {
    "winterveil", "lunar", "love", "noblegarden", "children", "midsummer",
    "brewfest", "harvest", "hallowsend", "dayofthedead", "pilgrim",
}

local function style(texture, blend, color, size, alpha, drift, motif, count, height)
    return {
        particle = { texture = texture, blend = blend, color = color,
            size = size, alpha = alpha, drift = drift },
        ornament = { hanging = true, motif = motif, count = count, height = height or 30 },
    }
end

local styles = {
    winterveil = style(166917, "ADD", { 0.78, 0.9, 1 }, 15, 0.7, -54,
        "lights", 12, 24),
    lunar = style(166928, "ADD", { 0.55, 0.72, 1 }, 11, 0.45, 12,
        "lanterns", 6),
    love = style(166320, "BLEND", { 1, 0.9, 0.95 }, 13, 0.55, -46,
        "hearts", 8),
    noblegarden = style(166928, "ADD", { 0.6, 1, 0.45 }, 9, 0.4, 14,
        "eggs", 8),
    children = style(166928, "ADD", { 1, 0.75, 0.35 }, 9, 0.4, -24,
        "bunting", 10),
    midsummer = style(166928, "ADD", { 1, 0.42, 0.12 }, 9, 0.5, 28,
        "flames", 8),
    brewfest = style(166928, "ADD", { 1, 0.76, 0.3 }, 8, 0.4, 22,
        "mugs", 8),
    harvest = style(166454, "BLEND", { 1, 0.9, 0.72 }, 16, 0.65, -48,
        "leaves", 8),
    hallowsend = style(2818012, "BLEND", { 0.26, 0.2, 0.34 }, 28, 0.85, 0,
        "pumpkins", 8),
    dayofthedead = style(166320, "BLEND", { 1, 0.62, 0.2 }, 12, 0.6, -42,
        "flowers", 8),
    pilgrim = style(166454, "BLEND", { 1, 0.84, 0.58 }, 14, 0.6, -44,
        "corn", 8),
}

styles.winterveil.snowfall = true
styles.winterveil.ornament.hanging = true
styles.lunar.ornament.hanging = true
styles.lunar.ornament.lanterns = true
styles.lunar.moonlight = true
styles.hallowsend.bats = true
styles.hallowsend.webTexture = 203396

local function prop(file, x, y, z, radius, size, offset, elevation)
    return { file = file, center = { x, y, z }, radius = radius, size = size,
        offset = offset or 8, elevation = elevation or 0.3 }
end

styles.winterveil.corners = { prop(199604, -0.00484, 0.00415, 0.31208, 0.64854, 52) }
styles.lunar.corners = { prop(534430, 0.25552, 0.02946, 1.64896, 3.19553, 72) }
styles.lunar.corners[1].tether = true
styles.love.corners = { prop(200172, 0.00484, 0.00043, 0.02195, 0.09529, 46, 8, 0.9) }
styles.noblegarden.ornament.hanging = false
styles.noblegarden.meadow = true
styles.noblegarden.corners = {
    prop(199691, 0, -0.02714, 0.20983, 0.43509, 44, 12),
    prop(199691, 0, -0.02714, 0.20983, 0.43509, 36, 42),
}
styles.children.corners = { prop(5282585, -0.01405, 0.01049, 0.84364, 1.25373, 56) }
styles.midsummer.corners = { prop(200094, 0.04324, -0.00622, 0.36842, 0.45792, 50) }
styles.brewfest.corners = {
    prop(2920482, 0.00013, -0.02465, 0.08883, 0.49514, 48, 8, 1),
    prop(2918344, 0.03825, 0.07735, 0.19730, 0.36586, 44, 36),
}
styles.harvest.corners = { { texture = 190583, size = 48, offset = 12 } }
styles.dayofthedead.corners = { prop(308312, 0.01388, -0.00108, 0.41736, 0.59019, 56) }
styles.pilgrim.corners = { prop(200118, 0.0755, -0.07312, 0.60253, 1.93197, 60) }

function addon.SeasonalStyles.GetThemes()
    local result = {}
    for index, name in ipairs(order) do result[index] = name end
    return result
end

function addon.SeasonalStyles.Get(theme)
    return styles[theme]
end

function addon.SeasonalStyles.Resolve(active)
    if type(active) ~= "table" then return nil end
    for _, theme in ipairs(order) do
        for _, candidate in ipairs(active) do
            if candidate == theme then return theme end
        end
    end
end
