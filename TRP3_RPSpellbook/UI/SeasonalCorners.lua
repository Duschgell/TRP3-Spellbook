local _, addon = ...

addon.SeasonalCorners = {}
local Corners = addon.SeasonalCorners

local function call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    local ok, result = pcall(object[method], object, ...)
    return ok and result ~= false
end

local function pose(slot)
    local actor, spec, scene = slot.actor, slot.spec, slot.frame
    if not spec or not scene:IsVisible() or actor:GetModelFileID() ~= spec.file or not actor:IsLoaded() then return end
    local center = spec.center
    local distance = spec.radius * 1.12 / math.sin(math.pi / 8)
    local elevation, angle = spec.elevation, math.pi / 4
    local c, s, ca, sa = math.cos(elevation), math.sin(elevation), math.cos(angle), math.sin(angle)
    local ok = call(actor, "SetUseCenterForOrigin", false, false, false)
        and call(actor, "SetRequestedScale", 1)
        and call(actor, "SetScale", 1)
        and call(actor, "SetPosition", -center[1], -center[2], -center[3])
        and call(actor, "SetYaw", 0)
        and call(actor, "SetAnimation", 0, 0, 0, 0)
        and call(actor, "SetPaused", true, false)
        and call(actor, "SetParticleOverrideScale", 0)
        and call(scene, "SetCameraFieldOfView", math.pi / 4)
        and call(scene, "SetCameraNearClip", math.min(0.01, spec.radius * 0.01))
        and call(scene, "SetCameraFarClip", math.max(1000, distance + spec.radius * 2))
        and call(scene, "SetCameraPosition", distance * c * ca, distance * c * sa, distance * s)
        and call(scene, "SetCameraOrientationByAxisVectors", -c * ca, -c * sa, -s, sa, -ca, 0, -s * ca, -s * sa, c)
    if not ok then
        slot.failed = true
        actor:Hide()
        scene:Hide()
        for _, line in ipairs(slot.rope or {}) do line:SetShown(false) end
        return
    end
    actor:SetAlpha(0.9)
    actor:Show()
end

local function createSlot(host, model)
    local slot = {}
    local ok, frame = pcall(CreateFrame, model and "ModelScene" or "Frame", nil, host)
    if not ok or not frame then slot.unavailable = true; return slot end
    slot.frame = frame
    frame:Hide()
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
    if not model then
        slot.texture = frame:CreateTexture(nil, "ARTWORK")
        slot.texture:SetAllPoints(frame)
        slot.texture:SetBlendMode("BLEND")
        return slot
    end
    local created, actor = pcall(function() return frame:CreateActor(nil, "ModelSceneActorTemplate") end)
    if not created or not actor then slot.unavailable = true; return slot end
    slot.actor = actor
    if type(actor.GetModelFileID) ~= "function" or type(actor.IsLoaded) ~= "function"
        or not call(frame, "SetAllowOverlappedModels", true)
        or not call(frame, "SetLightVisible", true)
        or not call(frame, "SetLightAmbientColor", 0.8, 0.8, 0.8)
        or not call(frame, "SetLightDiffuseColor", 0.7, 0.7, 0.7)
        or not call(frame, "SetLightDirection", -0.4, -0.35, -0.82)
        or not call(actor, "SetNormalizedScaleAggressiveness", 0)
        or not call(actor, "SetScript", "OnUpdate", nil)
        or not call(actor, "SetOnModelLoadedCallback", function() pose(slot) end) then
        slot.unavailable = true
        actor:Hide()
    end
    return slot
end

local function tether(host, slot, size)
    if not slot.rope then
        slot.rope = {}
        for index = 1, 3 do
            local line = host:CreateLine(nil, "OVERLAY")
            line:SetColorTexture(0.65, 0.52, 0.24, 0.8)
            line:SetThickness(index == 1 and 1.3 or 1)
            slot.rope[index] = line
        end
    end
    local x = 4 + size / 2
    local points = { { x, -2, x, -size * 0.32 }, { x - 4, -1, x + 3, -6 }, { x + 4, -1, x - 3, -6 } }
    for index, line in ipairs(slot.rope) do
        local point = points[index]
        line:SetStartPoint("TOPLEFT", host, point[1], point[2])
        line:SetEndPoint("TOPLEFT", host, point[3], point[4])
        line:Show()
    end
end

local function meadow(host, width)
    if not host.meadow then
        local frame = CreateFrame("Frame", nil, host)
        frame:EnableMouse(false)
        frame:EnableMouseWheel(false)
        frame.grass = {}
        for index = 1, 16 do
            local texture = frame:CreateTexture(nil, "ARTWORK")
            texture:SetTexture(189758)
            texture:SetBlendMode("BLEND")
            texture:SetVertexColor(0.85, 1, 0.75, 0.6)
            frame.grass[index] = texture
        end
        host.meadow = frame
    end
    local frame = host.meadow
    frame:SetFrameLevel(host:GetFrameLevel() + 3)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 12, 2)
    local length = math.max(1, width - 24)
    frame:SetSize(length, 22)
    for index, texture in ipairs(frame.grass) do
        texture:ClearAllPoints()
        texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (index - 1) * length / #frame.grass, 0)
        texture:SetSize(length / #frame.grass + 2, 14 + index % 3 * 3)
        texture:SetTexCoord(index % 2 == 0 and 1 or 0, index % 2 == 0 and 0 or 1, 0, 1)
        texture:Show()
    end
    frame:Show()
end

function Corners.Hide(host)
    if not host then return end
    for _, types in ipairs(host.cornerSlots or {}) do
        for _, slot in pairs(types) do
            slot.spec = nil
            if slot.frame then slot.frame:Hide() end
            if slot.actor then slot.actor:Hide() end
            for _, line in ipairs(slot.rope or {}) do line:SetShown(false) end
        end
    end
    if host.meadow then host.meadow:Hide() end
end

function Corners.Refresh(host, spec, width, height)
    local entries = spec.corners or {}
    host.cornerSlots = host.cornerSlots or {}
    for index, entry in ipairs(entries) do
        local slot = host.cornerSlots[index]
        local model = entry.file ~= nil
        local key = model and "model" or "texture"
        if not slot then slot = {}; host.cornerSlots[index] = slot end
        local item = slot[key]
        if not item then item = createSlot(host, model); slot[key] = item end
        if not item.unavailable then
            local frame = item.frame
            local size = math.min(entry.size, width * 0.22, height * 0.2)
            frame:SetFrameLevel(host:GetFrameLevel() + 2)
            frame:ClearAllPoints()
            frame:SetSize(size, size)
            frame:SetPoint(entry.tether and "TOPLEFT" or "BOTTOMLEFT", host,
                entry.tether and "TOPLEFT" or "BOTTOMLEFT", entry.tether and 4 or entry.offset, entry.tether and -8 or 2)
            item.spec, item.failed = entry, false
            frame:Show()
            if model then
                local actor = item.actor
                if item.file ~= entry.file then
                    actor:SetAlpha(0)
                    actor:ClearModel()
                    item.file = entry.file
                    actor:Show()
                    if not call(actor, "SetModelByFileID", entry.file) then
                        item.failed, item.file = true, nil
                        actor:Hide()
                    end
                end
                if not item.failed then pose(item) end
                if item.failed then frame:Hide() end
            else
                item.texture:SetTexture(entry.texture)
                item.texture:SetVertexColor(1, 1, 1, 0.75)
                item.texture:Show()
            end
            if entry.tether and not item.failed then tether(host, item, size) end
        end
    end
    if spec.meadow then meadow(host, width) end
end
