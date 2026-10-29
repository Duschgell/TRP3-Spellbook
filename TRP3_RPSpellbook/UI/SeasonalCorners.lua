local _, addon = ...

addon.SeasonalCorners = {}
local Corners = addon.SeasonalCorners
local animateSlot

local function call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    local ok, result = pcall(object[method], object, ...)
    return ok and result ~= false
end

local function stopSlot(slot)
    slot.posed = false
    slot.pendingPose, slot.poseAttempts, slot.retryElapsed = nil, 0, 0
    slot.motion, slot.activity, slot.started = nil, nil, false
    if slot.rocket then slot.rocket:Hide() end
    if slot.flame then slot.flame:Hide() end
    for _, puff in ipairs(slot.steam or {}) do puff:Hide() end
    if slot.actor then
        slot.actor:Hide()
        call(slot.actor, "SetPaused", true, false)
        call(slot.actor, "SetParticleOverrideScale", 0)
    end
    for _, line in ipairs(slot.rope or {}) do line:SetShown(false) end
end

local function failSlot(slot)
    slot.failed = true
    stopSlot(slot)
    slot.frame:Hide()
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function coordinates(value)
    local kind = type(value)
    if (kind == "table" or kind == "userdata") and type(value.GetXYZ) == "function" then
        return pcall(value.GetXYZ, value)
    end
    return false
end

local function facing(slot, yaw)
    if slot.yaw == yaw then return true end
    local center = slot.center
    local c, s = math.cos(yaw), math.sin(yaw)
    if not call(slot.actor, "SetYaw", yaw)
        or not call(slot.actor, "SetPosition", -center[1] * c + center[2] * s,
            -center[1] * s - center[2] * c, -center[3]) then return false end
    slot.yaw = yaw
    return true
end

local function projectionTangents(slot, radius, distance, c, s, ca, sa)
    local scene = slot.frame
    local ok, scale = pcall(scene.GetEffectiveScale, scene)
    if not ok or not finite(scale) or scale <= 0 then return end
    local probe = radius * 0.25 * math.min(slot.width, slot.height) / math.max(slot.width, slot.height)
    local centerOK, x, y = pcall(scene.Project3DPointTo2D, scene, 0, 0, 0)
    local rightOK, right = pcall(scene.Project3DPointTo2D, scene, probe * sa, -probe * ca, 0)
    local upOK, _, up = pcall(scene.Project3DPointTo2D, scene, -probe * s * ca, -probe * s * sa, probe * c)
    if not centerOK or not rightOK or not upOK or not finite(x) or not finite(y)
        or not finite(right) or not finite(up) then return end
    local dx, dy = math.abs(right - x), math.abs(up - y)
    if dx <= 0 or dy <= 0 then return end
    local horizontal = slot.width * scale * probe / (2 * distance * dx)
    local vertical = slot.height * scale * probe / (2 * distance * dy)
    if finite(horizontal) and finite(vertical) and horizontal > 0 and vertical > 0 then
        return horizontal, vertical
    end
end

local function pose(slot)
    local actor, spec, scene = slot.actor, slot.spec, slot.frame
    if not spec or slot.failed or slot.posed or not scene:IsVisible() or not actor:IsLoaded() then return end
    local file = actor:GetModelFileID()
    if file ~= spec.file and not (spec.modelFiles and spec.modelFiles[file]) then return end
    if not call(actor, "SetAnimation", spec.animation or 0, 0, slot.reduced and 0 or spec.animationSpeed or 1, 0)
        or not call(actor, "SetPaused", slot.reduced == true or slot.waiting == true or spec.freeze == true, false) then
        failSlot(slot)
        return
    end
    local center, radius, bounds = spec.center, spec.radius, spec.bounds
    if not center then
        local ok, x1, y1, z1, x2, y2, z2
        if bounds then
            ok, x1, y1, z1, x2, y2, z2 = true, bounds[1], bounds[2], bounds[3], bounds[4], bounds[5], bounds[6]
        elseif type(actor.GetActiveBoundingBox) == "function" then
            ok, x1, y1, z1, x2, y2, z2 = pcall(actor.GetActiveBoundingBox, actor)
        end
        if ok and not finite(x1) then
            local bottom, top, bottomOK, topOK = x1, y1
            bottomOK, x1, y1, z1 = coordinates(bottom)
            topOK, x2, y2, z2 = coordinates(top)
            ok = bottomOK and topOK
        end
        if ok and finite(x1) and finite(y1) and finite(z1) and finite(x2) and finite(y2) and finite(z2)
            and x1 <= x2 and y1 <= y2 and z1 <= z2 then
            center = { (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2 }
            radius = math.sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2) / 2
            bounds = { x1, y1, z1, x2, y2, z2 }
        end
    end
    if type(center) ~= "table" or not finite(center[1]) or not finite(center[2]) or not finite(center[3])
        or not finite(radius) or radius <= 0 then
        failSlot(slot)
        return
    end
    local elevation, angle = spec.elevation or 0.3, spec.cameraAngle or math.pi / 4
    local c, s, ca, sa = math.cos(elevation), math.sin(elevation), math.cos(angle), math.sin(angle)
    local yaw = spec.yaw or (spec.reverse and math.pi or 0)
    local distance = radius * 4
    if not call(scene, "SetCameraFieldOfView", math.pi / 4)
        or not call(scene, "SetCameraNearClip", math.min(0.01, radius * 0.01))
        or not call(scene, "SetCameraFarClip", math.max(1000, distance + radius * 2))
        or not call(scene, "SetCameraPosition", distance * c * ca, distance * c * sa, distance * s)
        or not call(scene, "SetCameraOrientationByAxisVectors", -c * ca, -c * sa, -s, sa, -ca, 0, -s * ca, -s * sa, c) then
        failSlot(slot)
        return
    end
    local horizontalTangent, verticalTangent = projectionTangents(slot, radius, distance, c, s, ca, sa)
    if not horizontalTangent then
        slot.poseAttempts = (slot.poseAttempts or 0) + 1
        if slot.poseAttempts >= 3 then failSlot(slot)
        else
            slot.pendingPose, slot.retryElapsed = true, 0
            actor:SetAlpha(0)
            call(actor, "SetPaused", true, false)
            call(actor, "SetParticleOverrideScale", 0)
            if slot.host.RequestPoseUpdate then slot.host.RequestPoseUpdate() end
        end
        return
    end
    distance = radius * 1.12 / math.sin(math.atan(math.min(horizontalTangent, verticalTangent)))
    if bounds then
        distance = 0
        local cy, sy = math.cos(yaw), math.sin(yaw)
        for index = 0, 7 do
            local x = bounds[index % 2 == 0 and 1 or 4] - center[1]
            local y = bounds[math.floor(index / 2) % 2 == 0 and 2 or 5] - center[2]
            local z = bounds[index < 4 and 3 or 6] - center[3]
            x, y = x * cy - y * sy, x * sy + y * cy
            local depth = x * c * ca + y * c * sa + z * s
            local horizontal = math.abs(x * sa - y * ca) / horizontalTangent
            local vertical = math.abs(-x * s * ca - y * s * sa + z * c) / verticalTangent
            distance = math.max(distance, depth + math.max(horizontal, vertical))
        end
        distance = math.max(radius * 0.1, distance * (spec.fitMargin or 1.12))
    end
    distance = distance * (spec.viewportScale or 1)
    slot.radius, slot.center, slot.yaw = radius, center, nil
    local ok = call(actor, "SetUseCenterForOrigin", false, false, false)
        and call(actor, "SetRequestedScale", 1)
        and call(actor, "SetNormalizedScaleAggressiveness", 0)
        and call(actor, "SetScale", 1)
        and facing(slot, yaw)
        and call(actor, "SetParticleOverrideScale", not slot.reduced and not slot.waiting and spec.particles and 1 or 0)
        and call(scene, "SetCameraFarClip", math.max(1000, distance + radius * 2))
        and call(scene, "SetCameraPosition", distance * c * ca, distance * c * sa, distance * s)
    if not ok then
        failSlot(slot)
        return
    end
    if spec.pin then
        local x, y, z = spec.pin[1] - center[1], spec.pin[2] - center[2], spec.pin[3] - center[3]
        local cy, sy = math.cos(yaw), math.sin(yaw)
        x, y = x * cy - y * sy, x * sy + y * cy
        local depth = distance - x * c * ca - y * c * sa - z * s
        local horizontal = (x * sa - y * ca) / (depth * horizontalTangent)
        local vertical = (-x * s * ca - y * s * sa + z * c) / (depth * verticalTangent)
        slot.x, slot.y = slot.x - slot.width * (1 + horizontal) / 2, slot.y - slot.height * (1 + vertical) / 2
        scene:SetPoint(slot.anchor, slot.host, slot.relative, slot.x, slot.y)
    end
    slot.posed = true
    slot.pendingPose = nil
    slot.started = true
    slot.activity = nil
    actor:SetAlpha(0.9)
    actor:Show()
    if spec.flame then
        if not slot.flame then slot.flame = scene:CreateTexture(nil, "OVERLAY") end
        local z = spec.flame - center[3]
        local depth = z * s
        local y = slot.height * 0.5 + z * c / (distance - depth) / verticalTangent * slot.height * 0.5
        slot.flame:ClearAllPoints()
        slot.flame:SetPoint("CENTER", scene, "BOTTOMLEFT", slot.width * 0.5, y)
        slot.flame:SetTexture(124636)
        slot.flame:SetBlendMode("ADD")
        slot.flame:SetVertexColor(1, 0.72, 0.22, 0.95)
        local viewport = spec.viewportScale or 1
        slot.flame:SetSize(math.max(5, slot.width / viewport * 0.1), math.max(9, slot.height / viewport * 0.19))
        slot.flame:SetShown(not slot.reduced)
    end
    animateSlot(slot)
end

local function createSlot(host, model)
    local slot = { host = host }
    local ok, frame = pcall(CreateFrame, model and "ModelScene" or "Frame", nil, host:GetParent())
    if not ok or not frame then slot.unavailable = true; return slot end
    slot.frame = frame
    frame.bookAnimationManaged = true
    frame:Hide()
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
    frame:SetScript("OnHide", function()
        slot.spec = nil
        stopSlot(slot)
    end)
    if not model then
        slot.texture = frame:CreateTexture(nil, "ARTWORK")
        slot.texture:SetAllPoints(frame)
        slot.texture:SetBlendMode("BLEND")
        return slot
    end
    local created, actor = pcall(function() return frame:CreateActor(nil, "ModelSceneActorTemplate") end)
    if not created or not actor then slot.unavailable = true; return slot end
    slot.actor = actor
    stopSlot(slot)
    frame:SetClipsChildren(true)
    if type(actor.GetModelFileID) ~= "function" or type(actor.IsLoaded) ~= "function"
        or not call(frame, "SetAllowOverlappedModels", true)
        or not call(frame, "SetLightVisible", true)
        or not call(frame, "SetLightAmbientColor", 0.8, 0.8, 0.8)
        or not call(frame, "SetLightDiffuseColor", 0.7, 0.7, 0.7)
        or not call(frame, "SetLightDirection", -0.4, -0.35, -0.82)
        or not call(actor, "SetOnModelLoadedCallback", function() pose(slot) end) then
        slot.unavailable = true
        stopSlot(slot)
    end
    return slot
end

local function tether(host, slot)
    if not slot.rope then
        slot.rope = {}
        for index = 1, 3 do
            local line = host:CreateLine(nil, "OVERLAY")
            line:SetColorTexture(0.65, 0.52, 0.24, 0.8)
            line:SetThickness(index == 1 and 1.3 or 1)
            slot.rope[index] = line
        end
    end
    for index, line in ipairs(slot.rope) do
        line:SetStartPoint("BOTTOMLEFT", host, index == 3 and 7 or 2, index == 2 and 6 or 2)
        if index == 1 then line:SetEndPoint("BOTTOM", slot.frame, 0, slot.height * 0.12)
        else line:SetEndPoint("BOTTOMLEFT", host, index == 3 and 2 or 7, index == 2 and 2 or 6) end
        line:Show()
    end
end

local function rocket(slot)
    if not slot.rocket then
        slot.rocket = (slot.host.particles or slot.host):CreateTexture(nil, "OVERLAY")
        slot.rocket:SetTexture(774366)
        slot.rocket:SetSize(4, 11)
        slot.rocket:SetBlendMode("ADD")
        slot.rocket:SetVertexColor(1, 0.7, 0.4, 0.75)
    end
    slot.rocket:Hide()
end

local function activity(slot, active)
    slot.waiting = not active
    if not slot.posed or slot.activity == active then return end
    if not call(slot.actor, "SetPaused", not active or slot.spec.freeze == true, false)
        or not call(slot.actor, "SetParticleOverrideScale", active and slot.spec.particles and 1 or 0) then
        failSlot(slot)
        return
    end
    slot.activity = active
end

animateSlot = function(slot)
    if not slot.spec or slot.failed or slot.reduced or not slot.frame:IsVisible() then return end
    local entry, time = slot.spec, slot.elapsed or 0
    if slot.flame then slot.flame:SetAlpha(0.8 + 0.15 * math.sin(time * 7) * math.sin(time * 11)) end
    if not slot.motion then return end
    local x, y, alpha = slot.x, slot.y, 1
    if slot.motion == "float" then
        y = y + math.sin(time * math.pi / 3.5) * 3
    elseif slot.motion == "hop" then
        local progress = (time % 10) / 5
        local returning = progress > 1
        if returning then progress = 2 - progress end
        x = x + slot.travel * progress
        y = y + math.abs(math.sin(time * 7.5)) * 3
        local yaw = (entry.yaw or (entry.reverse and math.pi or 0)) + (returning and math.pi or 0)
        if slot.posed and not facing(slot, yaw) then failSlot(slot); return end
    elseif slot.motion == "heart" then
        local progress = time % 12 / 9
        local active = progress < 1
        x = x + slot.travel * math.sin(math.min(1, progress) * math.pi)
        y = y + slot.rise * math.min(1, progress)
        alpha = active and math.min(1, progress / 0.08, (1 - progress) / 0.15) or 0
        activity(slot, active)
    else
        local delay = slot.motion == "firework" and 22 or slot.motion == "fly" and 20 or 14
        local duration = slot.motion == "firework" and 4 or slot.motion == "fly" and 9 or 12
        local phase = time % (delay + duration) - delay
        local launch = slot.motion == "firework" and not entry.nativeCast and 1.25 or 0
        local active = phase >= launch
        local progress = math.max(0, phase) / duration
        if slot.motion == "firework" then
            if slot.rocket and phase >= 0 and phase < launch then
                slot.rocket:SetPoint("CENTER", slot.frame, "CENTER", 0, -90 + phase / 1.25 * 90)
                slot.rocket:SetAlpha(math.min(1, phase / 0.12, (1.25 - phase) / 0.12))
                slot.rocket:Show()
            elseif slot.rocket then slot.rocket:Hide() end
            local cycle = math.floor(time / (delay + duration))
            if active and slot.burstCycle ~= cycle then
                slot.burstCycle, slot.posed, slot.activity, slot.waiting = cycle, false, nil, false
                slot.actor:ClearModel()
                if not call(slot.actor, "SetModelByFileID", entry.file) then slot.file = nil; failSlot(slot); return end
                pose(slot)
            end
            alpha = active and math.min(1, (phase - launch) / 0.1, (duration - phase) / 0.6) or 0
        else
            x = x + slot.travel * progress
            y = y + (slot.motion == "fly" and 28 * math.sin(progress * math.pi) or 0)
            alpha = active and math.min(1, phase / 0.4, (duration - phase) / 0.6) or 0
        end
        activity(slot, active)
    end
    if slot.failed then return end
    slot.frame:SetPoint(slot.anchor, slot.host, slot.relative, x, y)
    slot.frame:SetAlpha(math.max(0, alpha))
    if slot.motion == "train" and slot.steam then
        for index, puff in ipairs(slot.steam) do
            local phase = (time * 0.7 + index * 0.5) % 1
            puff:SetPoint("CENTER", slot.frame, "CENTER", 3 - phase * 9, 4 + phase * 16)
            puff:SetAlpha(alpha * math.sin(phase * math.pi) * 0.35)
            puff:SetShown(alpha > 0)
        end
    end
end

local function motion(slot, entry, width, height, reduced)
    slot.elapsed, slot.motion, slot.burstCycle = entry.phase or 0, not reduced and entry.motion or nil, nil
    slot.started = false
    slot.travel = entry.motion == "hop" and slot.travelLimit
        or entry.motion == "train" and slot.travelLimit
        or entry.motion == "heart" and width * 0.12
        or entry.motion == "fly" and width * 0.6 or math.max(0, width - slot.width - 80)
    slot.rise = height * 0.9
    if entry.reverse then slot.travel = -slot.travel end
    slot.waiting = slot.motion == "train" or slot.motion == "fly" or slot.motion == "firework" or slot.motion == "heart"
    if slot.waiting then slot.frame:SetAlpha(0) end
    if slot.motion == "firework" and not entry.nativeCast then rocket(slot) end
    if slot.motion == "train" and not slot.steam then
        slot.steam = {}
        for index = 1, 2 do
            local puff = slot.frame:CreateTexture(nil, "OVERLAY")
            puff:SetTexture(166917)
            puff:SetBlendMode("BLEND")
            puff:SetVertexColor(0.8, 0.85, 0.9, 0.5)
            puff:SetSize(8, 11)
            slot.steam[index] = puff
        end
    end
end

function Corners.HasMotion(host)
    for _, types in ipairs(host.cornerSlots or {}) do
        for _, slot in pairs(types) do
            if slot.spec and not slot.failed and not slot.unavailable
                and (slot.pendingPose or not slot.reduced and (slot.motion or slot.spec.flame)) then return true end
        end
    end
    return false
end

function Corners.Update(host, elapsed)
    if not finite(elapsed) or elapsed <= 0 or not host:IsVisible() then return end
    for _, types in ipairs(host.cornerSlots or {}) do
        for _, slot in pairs(types) do
            if slot.pendingPose and slot.spec and not slot.failed then
                slot.retryElapsed = slot.retryElapsed + elapsed
                if slot.retryElapsed >= 0.05 then pose(slot) end
            end
            if slot.spec and slot.started and not slot.failed and not slot.unavailable and not slot.reduced
                and (slot.motion or slot.spec.flame) then
                slot.elapsed = (slot.elapsed or 0) + elapsed
                animateSlot(slot)
            end
        end
    end
end

local function railway(host, width)
    host.rails = host.rails or {}
    for index = 1, 18 do
        local line = host.rails[index]
        if not line then line = host:CreateLine(nil, "ARTWORK"); host.rails[index] = line end
        if index <= 2 then
            line:SetStartPoint("BOTTOMLEFT", host, 28, 4 + index * 3)
            line:SetEndPoint("BOTTOMLEFT", host, 28 + width, 4 + index * 3)
        else
            local x = 28 + (index - 3) * width / 15
            line:SetStartPoint("BOTTOMLEFT", host, x, 5)
            line:SetEndPoint("BOTTOMLEFT", host, x, 12)
        end
        line:SetThickness(index <= 2 and 1.4 or 2)
        line:SetColorTexture(0.28, 0.17, 0.08, 0.65)
        line:Show()
    end
end

local function bottomInset(host, anchor, x, width, requested)
    local owner = host:GetParent()
    if type(owner.GetLeft) ~= "function" or not owner:GetLeft() or not owner:GetBottom() then return requested end
    local left = owner:GetLeft() + x + (anchor == "BOTTOMRIGHT" and owner:GetWidth() - width or 0)
    local bottom = requested
    for _, key in ipairs({ "previousPageButton", "nextPageButton", "bulkDeleteButton", "createButton" }) do
        local button = owner[key]
        if button and button:IsVisible() and type(button.GetLeft) == "function" then
            local first, last, top = button:GetLeft(), button:GetRight(), button:GetTop()
            if first and last and top and left < last + 4 and left + width > first - 4 then
                bottom = math.max(bottom, top - owner:GetBottom() + 4)
            end
        end
    end
    return bottom
end

local function travelRoom(host, width, size)
    local owner = host:GetParent()
    local edge = math.max(width * 0.7, width - 180)
    if type(owner.GetLeft) == "function" and owner:GetLeft() then
        for _, key in ipairs({ "previousPageButton", "nextPageButton" }) do
            local button = owner[key]
            if button and button:IsVisible() and type(button.GetLeft) == "function" and button:GetLeft() then
                edge = math.min(edge, button:GetLeft() - owner:GetLeft() - 4)
            end
        end
    end
    return math.max(0, edge - size - 12)
end

function Corners.Hide(host)
    if not host then return end
    for _, types in ipairs(host.cornerSlots or {}) do
        for _, slot in pairs(types) do
            slot.spec = nil
            slot.waiting = nil
            stopSlot(slot)
            if slot.frame then slot.frame:Hide() end
        end
    end
    for _, line in ipairs(host.rails or {}) do line:SetShown(false) end
end

function Corners.Refresh(host, spec, width, height, reduced)
    Corners.Hide(host)
    if not host:IsVisible() then return end
    local entries = {}
    for _, entry in ipairs(spec.corners or {}) do
        if entry.factionFiles and type(UnitFactionGroup) == "function" then
            local selected = {}
            for key, value in pairs(entry) do selected[key] = value end
            selected.file = entry.factionFiles[UnitFactionGroup("player")] or entry.file
            entries[#entries + 1] = selected
        else entries[#entries + 1] = entry end
    end
    for _, entry in ipairs(spec.visitors or {}) do
        if not reduced then entries[#entries + 1] = entry end
    end
    if spec.fireworks and #spec.fireworks > 0 and not reduced then
        local entry = { file = spec.fireworks[math.random(#spec.fireworks)],
            radius = 3, size = math.min(160, width * 0.28), motion = "firework", particles = true, offset = width * 0.25 }
        if spec.fireworkView then
            for key, value in pairs(spec.fireworkView) do entry[key] = value end
        else entry.center = { 0, 0, 0 } end
        entries[#entries + 1] = entry
    end
    local ornament = spec.ornament
    if ornament.models then
        local count = math.min(ornament.count, ornament.banner and 4 or 8,
            math.max(2, math.floor(width / (ornament.banner and 130 or ornament.size or 65))))
        for index = 1, count do
            local entry = {}
            for key, value in pairs(ornament.view or {}) do entry[key] = value end
            entry.file, entry.size = ornament.models[(index - 1) % #ornament.models + 1], ornament.size or 26
            entry.header, entry.fraction, entry.wave = true,
                ornament.banner and (index - 0.5) / count or index / (count + 1), ornament.wave
            if ornament.banner then entry.size, entry.height = math.max(1, width - 34) / count, ornament.height or 28 end
            entry.elevation, entry.particles, entry.resting = entry.elevation or 0.2, ornament.particles, ornament.resting
            entry.lift = ornament.lift or 0
            entries[#entries + 1] = entry
        end
    end
    host.cornerSlots = host.cornerSlots or {}
    for index, entry in ipairs(entries) do
        if index > 12 then break end
        local slot = host.cornerSlots[index]
        local model = entry.file ~= nil
        local key = model and "model" or "texture"
        if not slot then slot = {}; host.cornerSlots[index] = slot end
        local item = slot[key]
        if not item then item = createSlot(host, model); slot[key] = item end
        if not item.unavailable then
            local frame = item.frame
            local scale = entry.header and entry.height and 1
                or math.min(1, width * 0.3 / entry.size, height * 0.32 / (entry.height or entry.size))
            local size, tall = entry.size * scale, (entry.height or entry.size) * scale
            frame:SetFrameLevel(host.behindContent and host:GetFrameLevel()
                or entry.header and host:GetFrameLevel() or host:GetParent():GetFrameLevel() + 1)
            frame:ClearAllPoints()
            local viewport = entry.viewportScale or 1
            frame:SetSize(size * viewport, tall * viewport)
            frame:SetAlpha(1)
            item.width, item.height = size * viewport, tall * viewport
            local anchor, x, y = entry.anchor or "BOTTOMLEFT", entry.offset or 4, entry.bottom or 4
            if entry.scaleOffset then x = x * scale end
            if entry.header then
                anchor, x, y = entry.resting and "BOTTOMLEFT" or "TOPLEFT",
                    6 + (width - 34) * entry.fraction - size / 2, tall - 12
                y = y + (entry.lift or 0)
                if entry.resting then y = -math.sin(entry.fraction * math.pi) * 4 - 2 + (entry.lift or 0) end
                if entry.followWire then
                    y = tall / 2 - math.sin(entry.fraction * math.pi) * 4 + (entry.lift or 0)
                    x = math.max(6, math.min(x, width - 26 - size))
                end
                if entry.wave then y = y - math.sin(entry.fraction * math.pi * 4) * 3 end
            elseif entry.motion == "train" then
                anchor, x, y = "BOTTOMLEFT", 28, 4
                item.travelLimit = math.max(0, travelRoom(host, width, size) - x)
            elseif entry.motion == "heart" then x, y = width * entry.fraction, 12
            elseif entry.motion == "fly" then x, y = 44, height * 0.5
            elseif entry.motion == "firework" then x, y = width * 0.3, height * 0.25
            elseif entry.motion == "hop" then
                x, y = 12, 3
                item.travelLimit = travelRoom(host, width, size)
                if entry.reverse then x = x + item.travelLimit end
            elseif anchor == "TOPLEFT" or anchor == "TOPRIGHT" then y = entry.top or -2
            else y = bottomInset(host, anchor, x, size, y) end
            local right = anchor == "BOTTOMRIGHT" or anchor == "TOPRIGHT"
            local top = anchor == "TOPLEFT" or anchor == "TOPRIGHT"
            x = x + (right and 1 or -1) * (viewport - 1) * size / 2
            y = y + (top and 1 or -1) * (viewport - 1) * tall / 2
            item.anchor, item.relative, item.x, item.y = anchor, entry.header and "TOPLEFT" or anchor, x, y
            frame:SetPoint(anchor, host, item.relative, x, y)
            item.spec, item.failed, item.reduced, item.waiting = entry, false, reduced, false
            frame:Show()
            motion(item, entry, width, height, reduced)
            if model then
                local actor = item.actor
                actor:SetAlpha(0)
                actor:Show()
                if item.file ~= entry.file or item.displayID ~= entry.displayID or item.itemID ~= entry.itemID then
                    actor:ClearModel()
                    item.file, item.displayID, item.itemID = entry.file, entry.displayID, entry.itemID
                    local loaded
                    if entry.itemID then loaded = call(actor, "SetModelByHyperlink", "item:" .. entry.itemID)
                    elseif entry.displayID then loaded = call(actor, "SetModelByCreatureDisplayID", entry.displayID)
                    else loaded = call(actor, "SetModelByFileID", entry.file) end
                    if not loaded then
                        item.file, item.displayID, item.itemID = nil, nil, nil
                        failSlot(item)
                    end
                end
                if not item.failed then pose(item) end
                if item.failed then frame:Hide() end
            else
                item.texture:SetTexture(entry.texture)
                item.texture:SetVertexColor(1, 1, 1, 0.75)
                item.texture:Show()
                item.posed = true
                animateSlot(item)
            end
            if entry.tether and not item.failed then tether(host, item) end
        end
    end
    for index, entry in ipairs(entries) do
        local target = entry.alignTo and host.cornerSlots[entry.alignTo]
        local slot = host.cornerSlots[index]
        local item, parent = slot and slot.model, target and target.model
        if item and parent and item.frame and parent.frame and item ~= parent
            and not item.unavailable and not parent.unavailable and not item.failed and not parent.failed then
            item.frame:ClearAllPoints()
            item.frame:SetPoint("CENTER", parent.frame, "CENTER", 0, 0)
        end
    end
    if spec.railway then railway(host, travelRoom(host, width, 0)) end
end
