local _, addon = ...

addon.SeasonalStyles = {}

local order = {
    "winterveil", "lunar", "love", "noblegarden", "children", "midsummer",
    "brewfest", "harvest", "hallowsend", "dayofthedead", "pilgrim",
}

local function style(texture, blend, color, size, alpha, motion, motif, count, height)
    return {
        particle = { texture = texture, blend = blend, color = color,
            size = size, alpha = alpha, motion = motion },
        ornament = { hanging = true, motif = motif, count = count, height = height or 30 },
    }
end

local styles = {
    winterveil = style(166917, "ADD", { 0.78, 0.9, 1 }, 15, 0.7, "snow",
        "lights", 12, 24),
    lunar = style(166928, "ADD", { 0.55, 0.72, 1 }, 11, 0.45, "none",
        "lanterns", 6),
    love = style(166320, "BLEND", { 1, 0.9, 0.95 }, 13, 0.55, "petals",
        "hearts", 8),
    noblegarden = style(166928, "ADD", { 0.6, 1, 0.45 }, 9, 0.4, "none",
        "eggs", 8),
    children = style(166928, "ADD", { 1, 0.75, 0.35 }, 9, 0.4, "motes",
        "bunting", 10),
    midsummer = style(774366, "ADD", { 1, 0.62, 0.28 }, 6, 0.65, "embers",
        "flames", 8),
    brewfest = style(166928, "ADD", { 1, 0.76, 0.3 }, 8, 0.4, "bubbles",
        "mugs", 8),
    harvest = style(166454, "BLEND", { 1, 0.9, 0.72 }, 16, 0.65, "none",
        "leaves", 8),
    hallowsend = style(2818012, "BLEND", { 0.26, 0.2, 0.34 }, 28, 0.85, "bats",
        "pumpkins", 8),
    dayofthedead = style(166320, "BLEND", { 1, 0.62, 0.2 }, 12, 0.6, "petals",
        "flowers", 8),
    pilgrim = style(166454, "BLEND", { 1, 0.84, 0.58 }, 14, 0.6, "leaves",
        "corn", 8),
}

styles.winterveil.snowfall = true
styles.winterveil.ornament.hanging = true
styles.lunar.ornament.hanging = true
styles.lunar.ornament.lanterns = true
styles.lunar.moonlight = true
styles.hallowsend.bats = true
styles.hallowsend.webTexture = 203396

local function model(file, size, options)
    local entry = options or {}
    entry.file, entry.size = file, size
    entry.offset = entry.offset or (entry.anchor == "BOTTOMRIGHT" and -4 or 4)
    entry.elevation = entry.elevation or 0.3
    return entry
end

local function banner(file, bounds, count)
    return { hanging = true, banner = true, models = { file }, count = count or 2, height = 28,
        view = { elevation = 0, cameraAngle = 0, bounds = bounds } }
end

styles.winterveil.particle.count = 24
styles.winterveil.navigation = "ribbon"
styles.winterveil.corners = {
    model(199604, 84, { height = 76, elevation = 0.55,
        bounds = { -0.3579, -0.45034, 0.0131, 0.34822, 0.45863, 0.61107 } }),
}
styles.lunar.corners = { model(534430, 82, { height = 112, bottom = 6,
    motion = "float", freeze = true, animationSpeed = 0, elevation = 0.08, cameraAngle = 0,
    bounds = { 0.19056, -0.36991, 1.31776, 0.47727, 0.37788, 2.21470 } }) }
styles.lunar.ornament = banner(199595, { -0.88060, -5.88509, -1.47681, 0.85391, 5.92226, 0.89838 }, 4)
styles.love.navigation = "hearts"
styles.love.ornament = banner(200191, { -0.00654, -5.6499, -1.57004, 0.38826, 5.53682, 0.88115 })
styles.love.particle.alternate = 166311
styles.love.corners = { model(200192, 98, { height = 106, offset = -2, bottom = 0,
    elevation = 0.3, cameraAngle = 0,
    bounds = { -0.80812, -0.92739, -0.17346, 0.70537, 0.99741, 2.13224 } }) }
styles.love.visitors = {
    model(166316, 22, { motion = "heart", animation = 158, fraction = 0.3, cameraAngle = 0,
        bounds = { -0.00588, -0.10475, -0.0975, 0.01452, 0.10522, 0.09592 } }),
    model(166316, 18, { motion = "heart", animation = 158, fraction = 0.66, phase = 6,
        reverse = true, cameraAngle = 0, yaw = 0,
        bounds = { -0.00588, -0.10475, -0.0975, 0.01452, 0.10522, 0.09592 } }),
}
styles.love.fireworks = { 5493563 }
styles.love.fireworkView = { nativeCast = true,
    bounds = { -0.08284, -1.0316, -1.0946, 0.05587, 1.0316, 12.10152 } }
styles.noblegarden.ornament = banner(5499940, { -0.1599, -5.15812, -1.82056, 0.25431, 5.15814, 0.44861 })
styles.noblegarden.particle.count = 0
styles.noblegarden.corners = { model(199691, 72, { height = 94,
    elevation = 1.53, cameraAngle = -math.pi / 2,
    bounds = { -0.22064, -0.33265, -0.00763, 0.22064, 0.27837, 0.42729 } }) }
styles.noblegarden.visitors = {
    model(1112735, 48, { displayID = 328, motion = "hop", animation = 5, elevation = 0.12,
        cameraAngle = math.pi / 2, yaw = math.pi,
        bounds = { -0.61254, -0.32468, -0.16938, 0.48093, 0.29009, 0.82460 } }),
    model(1112735, 42, { displayID = 1560, motion = "hop", animation = 5, reverse = true,
        elevation = 0.12, cameraAngle = math.pi / 2, phase = 1.5, yaw = 0,
        bounds = { -0.61254, -0.32468, -0.16938, 0.48093, 0.29009, 0.82460 } }),
    model(4048782, 28, { displayID = 101137, motion = "fly", animation = 135, offset = 60 }),
}
styles.children.ornament = banner(5282587, { -0.27028, -5.18557, -1.86652, 0.27028, 5.18557, 0.44789 })
styles.children.railway = true
styles.children.corners = { model(2166594, 66, { height = 152, offset = 16, bottom = 6, elevation = 0.02,
    cameraAngle = 0, factionFiles = { Alliance = 2166594, Horde = 2166595 },
    pin = { -0.02193, 0.08941, 1.87392 },
    bounds = { -0.35093, -0.37723, 1.87392, 0.46288, 0.45653, 6.27337 } }) }
styles.children.visitors = { model(244204, 64, { height = 35, motion = "train", particles = true,
    animationSpeed = 0, freeze = true, phase = 14.4, yaw = math.pi,
    cameraAngle = math.pi, elevation = 0, fitMargin = 1.02,
    bounds = { 1.4233451, 0.216149, 0.0354722, 1.7124379, 0.765226, 0.3380582 } }) }
styles.midsummer.ornament = banner(5046509, { -0.25157, -5.51953, -1.74736, 0.25157, 5.51953, 0.5481 })
styles.midsummer.particle.count = 24
styles.midsummer.corners = {
    model(200080, 104, { height = 108, bottom = 0, offset = 0, particles = true,
        elevation = 0.4, cameraAngle = 0, viewportScale = 1.5,
        bounds = { -5.18877, -5.21198, -0.91411, 5.16437, 5.14117, 6.09143 } }),
    model(5013015, 54, { height = 64, anchor = "TOPRIGHT", offset = -28, elevation = 0.08, cameraAngle = 0,
        bounds = { -2.61711, -11.09363, 0.07544, 2.50706, 11.13735, 25.73487 } }),
}
styles.brewfest.ornament.models = { 2920482 }
styles.brewfest.ornament.count = 8
styles.brewfest.ornament.lift = 4
styles.brewfest.ornament.wireLift = 7
styles.brewfest.ornament.view = { elevation = 1.53, cameraAngle = -math.pi / 2,
    bounds = { -0.32918, -0.38106, -0.00964, 0.32943, 0.33176, 0.18729 } }
styles.brewfest.particle.texture, styles.brewfest.particle.blend = 165677, "BLEND"
styles.brewfest.particle.color = { 1, 0.96, 0.84 }
styles.brewfest.particle.size = 12
styles.brewfest.particle.cornerCount = 3
styles.brewfest.particle.count = 16
styles.brewfest.corners = { model(2918345, 78, { height = 84, particles = true, elevation = 0.22,
    cameraAngle = math.pi, bounds = { -0.15305, -0.18703, 0.00006, 0.16302, 0.34204, 0.45384 } }),
    model(2961115, 36, { height = 70, anchor = "TOPLEFT", offset = 2, top = -2, behind = true, cameraAngle = 0,
        bounds = { -0.18952, -4.66034, -2.65688, 1.75022, 4.35072, 14.43859 } }),
}
styles.harvest.particle.count = 0
styles.harvest.fireworks = { 166165, 166166, 166167, 166168, 166170 }
styles.harvest.ornament.hanging = true
styles.harvest.ornament.models, styles.harvest.ornament.count = { 198202, 198203, 198204, 198205, 198206 }, 8
styles.harvest.ornament.size = 128
styles.harvest.ornament.lift = 16
styles.harvest.ornament.view = { height = 64, followWire = true, elevation = 1.1, cameraAngle = 0 }
styles.harvest.corners = {
    model(1331239, 78, { height = 44, offset = 33, elevation = 1.15, cameraAngle = -math.pi / 2,
        bounds = { -0.34927, -0.16246, -0.00224, 0.34927, 0.16246, 0.05003 } }),
    model(1124094, 32, { height = 56, offset = 1, bottom = 5, particles = true, viewportScale = 1.6,
        elevation = 0.12, cameraAngle = 0, flame = 0.35382,
        bounds = { -0.10145, -0.10097, 0, 0.10204, 0.10253, 0.39123 } }),
}
styles.hallowsend.ornament.models = { 8015706, 8015707, 8015708 }
styles.hallowsend.ornament.count = 8
styles.hallowsend.ornament.particles = true
styles.hallowsend.ornament.view = { elevation = 0.12, cameraAngle = 0 }
styles.hallowsend.corners = { model(5019425, 24, { height = 110, anchor = "TOPLEFT", offset = 0, top = -2, behind = true,
    cameraAngle = 0, elevation = 0, bounds = { -0.22548, -0.42939, -0.83543, 0.25082, 0.50503, 7.15824 } }) }
styles.dayofthedead.ornament = {}
styles.dayofthedead.particle.continuous = true
styles.dayofthedead.particle.count = 18
styles.dayofthedead.corners = { model(199401, 60, { height = 80, offset = 0, bottom = 8, particles = true, elevation = 0.08, viewportScale = 1.6,
    cameraAngle = 0, flame = 0.57159, bounds = { -0.18699, -0.12059, -0.00867, 0.17652, 0.1284, 0.54686 } }) }
styles.pilgrim.ornament = banner(5499942, { -0.15161, -5.2028, -1.8157, 0.26458, 5.2028, 0.4581 })
styles.pilgrim.particle.count = 18
styles.pilgrim.corners = {
    model(200118, 188, { height = 148, elevation = 0.45, cameraAngle = -0.25, offset = -60, scaleOffset = true,
        bounds = { -1.47019, -1.01444, -0.0737, 1.62119, 0.8682, 1.27875 } }),
}

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
