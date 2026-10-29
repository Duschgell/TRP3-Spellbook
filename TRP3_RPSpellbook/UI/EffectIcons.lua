local _, addon = ...
addon.EffectIcons = {}
local icons = addon.EffectIcons
local strips = setmetatable({}, { __mode = "k" })
local activity = {}

local function readable(value)
    return type(canaccessvalue) ~= "function" or canaccessvalue(value)
end

local function active(callback, ...)
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback, ...)
     
    return not ok or not readable(value) or value == true or value == 1
end

function icons.IsSuppressed()
    if activity.combat or activity.pet or activity.vehicle or activity.challenge
        or active(_G.InCombatLockdown) or active(_G.UnitAffectingCombat, "player")
        or active(_G.UnitInVehicle, "player") or active(_G.UnitHasVehicleUI, "player")
        or active(_G.C_PetBattles and C_PetBattles.IsInBattle)
        or active(_G.C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive) then return true end
    if type(GetInstanceInfo) == "function" then
        local ok, _, _, difficulty = pcall(GetInstanceInfo)
        if not ok or not readable(difficulty) or difficulty == 8 then return true end
    end
    return false
end

function icons.ActivityChanged(event, unit)
    if event == "PLAYER_REGEN_DISABLED" then activity.combat = true
    elseif event == "PLAYER_REGEN_ENABLED" then activity.combat = nil
    elseif event == "PET_BATTLE_OPENING_START" then activity.pet = true
    elseif event == "PET_BATTLE_CLOSE" then activity.pet = nil
    elseif event == "CHALLENGE_MODE_START" then activity.challenge = true
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then activity.challenge = nil
    elseif event == "PLAYER_ENTERING_WORLD" then activity = {}
    elseif readable(unit) and unit == "player" then
        if event == "UNIT_ENTERING_VEHICLE" or event == "UNIT_ENTERED_VEHICLE" then activity.vehicle = true
        elseif event == "UNIT_EXITED_VEHICLE" then activity.vehicle = nil end
    end
end

function icons.HideAll()
    for strip in pairs(strips) do strip:Hide() end
    local tooltip = _G.GameTooltip
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if owner and owner.effectStrip then tooltip:Hide() end
end

function icons.Plan(count, options)
    count = math.max(0, math.floor(count))
    local gap = options.gap or 5
    local minimum, maximum = options.minSize, options.maxSize
    local function plan(size)
        local columns = math.max(0, math.floor((options.width + gap) / (size + gap)))
        local capacity = columns * math.max(0, math.floor((options.maxHeight + gap) / (size + gap)))
        local visible = math.min(count, capacity)
        if visible == 0 then return { size = size, columns = 1, rows = 0, visible = 0, width = 0, height = 0, gap = gap } end
        columns = math.min(columns, visible)
        local rows = math.ceil(visible / columns)
        return { size = size, columns = columns, rows = rows, visible = visible, gap = gap,
            width = columns * (size + gap) - gap, height = rows * (size + gap) - gap }
    end
    for size = maximum, minimum, -1 do
        local result = plan(size)
        if result.visible == count then return result end
    end
    return plan(minimum)
end

function icons.Configure(strip, options)
    strip.layout = options
end

function icons.Create(parent, size, columns, maximum, passive)
    local strip = CreateFrame("Frame", nil, parent)
    strip.buttons, strip.size, strip.columns, strip.maximum, strip.passive = {}, size, columns, maximum, passive
    strips[strip] = true
    strip:SetSize(columns * (size + 5), size)
    strip:EnableMouse(false)
    for index = 1, maximum do
        local button = CreateFrame("Button", nil, strip, "BackdropTemplate")
        button:SetSize(size, size)
        button:SetPoint("TOPLEFT", ((index - 1) % columns) * (size + 5), -math.floor((index - 1) / columns) * (size + 9))
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        button:SetBackdropColor(0.12, 0.085, 0.04, 0.65)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.duration = button:CreateFontString(nil, "OVERLAY")
        button.duration:SetFont(addon.BookLayout.Font, math.max(9, math.min(11, size / 3)), "OUTLINE")
        button.duration:SetPoint("BOTTOM", 0, 2)
        button.duration:SetTextColor(1, 0.9, 0.66)
        button.effectStrip = strip
        button:EnableMouse(not passive)
        if not passive then
            button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:SetScript("OnClick", function(_, mouse)
                if mouse == "LeftButton" and button.effectBarDragged then
                    button.effectBarDragged = nil
                    return
                end
                if icons.IsSuppressed() or strip.profile ~= addon.Database.GetActiveProfileKey() then return end
                if button.overflow then addon.TimedEffectsView.Open(strip.player); return end
                if mouse == "LeftButton" and button.entry and not button.entry.native
                    and addon.EffectDisplay.IsSelf(strip.player) and IsShiftKeyDown and IsShiftKeyDown() then
                    local spell = button.entry.spell
                    local ok, message = addon.ChatInsert.InsertSpell(spell.ownerKey, spell, button.entry.id)
                    if not ok then addon.Logger.Error(message) end
                    return
                end
                if mouse == "RightButton" and addon.EffectDisplay.IsSelf(strip.player) and button.entry then
                    if not addon.EffectDisplay.Remove(button.entry) then addon.Logger.Error(addon.L("AURA_REMOVE_FAILED")) end
                    icons.Update(strip, strip.player)
                    if addon.EffectSurfaces then addon.EffectSurfaces.Refresh() end
                end
            end)
            button:SetScript("OnEnter", function()
                local entry = button.entry
                if icons.IsSuppressed() or not entry then return end
                local own = addon.EffectDisplay.IsSelf(strip.player)
                addon.SpellTooltip.Show(button, entry.spell, false, "ANCHOR_RIGHT", {
                    effect = entry, showChatHint = own and not entry.native,
                    showDismissHint = own and (not entry.native or entry.cancellable),
                })
            end)
            button:SetScript("OnLeave", function() addon.SpellTooltip.Hide() end)
        end
        strip.buttons[index] = button
        button:Hide()
    end
    return strip
end

function icons.Update(strip, player)
    if icons.IsSuppressed() then strip:Hide(); return 0 end
    strip.player, strip.profile = player, addon.Database.GetActiveProfileKey()
    local entries = addon.EffectDisplay.List(player)
    local options = strip.layout or { width = strip.columns * (strip.size + 5) - 5,
        maxHeight = math.ceil(strip.maximum / strip.columns) * (strip.size + 9), minSize = strip.size, maxSize = strip.size }
    local plan = icons.Plan(math.min(#entries, strip.maximum), options)
    local count = plan.visible
    local previous = strip.plan
    local layoutChanged = not previous or previous.size ~= plan.size or previous.columns ~= plan.columns
        or previous.visible ~= plan.visible or previous.width ~= plan.width or previous.gap ~= plan.gap
    strip.plan = plan
    if not previous or previous.width ~= plan.width or previous.height ~= plan.height then
        strip:SetSize(math.max(1, plan.width), math.max(1, plan.height))
    end
    for index, button in ipairs(strip.buttons) do
        local entry = index <= count and entries[index] or nil
        button.entry, button.overflow = entry, index == count and #entries > count
        button:SetShown(entry ~= nil)
        if entry then
            local row, column = math.floor((index - 1) / plan.columns), (index - 1) % plan.columns
            local rowCount = math.min(plan.columns, count - row * plan.columns)
            local rowWidth = rowCount * (plan.size + plan.gap) - plan.gap
            if layoutChanged then
                button:ClearAllPoints()
                button:SetSize(plan.size, plan.size)
                button:SetPoint("TOPLEFT", (plan.width - rowWidth) / 2 + column * (plan.size + plan.gap), -row * (plan.size + plan.gap))
            end
            if layoutChanged or button.effectFont ~= addon.BookLayout.Font then
                button.effectFont = addon.BookLayout.Font
                button.duration:SetFont(button.effectFont, math.max(9, math.min(13, math.floor(plan.size / 3))), "OUTLINE")
            end
            local spell, effects = entry.spell, entry.spell.effects
            local tags = spell.tags or {}
            local magicType = tags[addon.Constants.MAGIC_TAG_TYPE] or tags.Magieart
            local school = tags[addon.Constants.MAGIC_TAG_SCHOOL] or tags.Magieschule
            local style = button.effectStyle
             
            if not style or style.icon ~= spell.icon or style.buff ~= effects.buff or style.debuff ~= effects.debuff
                or style.debuffType ~= effects.debuffType or style.magicType ~= magicType or style.school ~= school
                or style.size ~= plan.size then
                addon.BookLayout.SetSpellIcon(button.icon, spell, addon.Constants.DEFAULT_SPELL_ICON, true, true)
                if effects.debuff then button:SetBackdropBorderColor(0.64, 0.24, 0.23, 0.9)
                else button:SetBackdropBorderColor(0.69, 0.57, 0.32, 0.9) end
                button.effectStyle = { icon = spell.icon, buff = effects.buff, debuff = effects.debuff,
                    debuffType = effects.debuffType, magicType = magicType, school = school, size = plan.size }
            end
            local duration = ""
            if entry.pending then duration = "..."
            elseif entry.permanent or (not entry.combat and entry.expiresAt == math.huge) then duration = "\226\136\158"
            elseif entry.combat and entry.spell.effects.durationRounds ~= nil then
                local rounds = entry.spell.effects.durationRounds
                local current = addon.GameMasterService.GetSubmissionContext()
                if entry.expiresRound and current then rounds = math.max(0, entry.expiresRound - current.roundNumber) end
                duration = entry.spell.effects.durationRounds == 0 and "\226\136\158" or tostring(rounds or "")
            elseif entry.expiresAt and entry.expiresAt < math.huge then
                local minutes = math.max(1, math.ceil((entry.expiresAt - addon.Runtime.GetTimestamp()) / 60))
                duration = minutes >= 60 and (math.floor(minutes / 60) .. "h") or (minutes .. "m")
            end
            local text = strip.passive and "" or button.overflow and ("+" .. (#entries - count + 1)) or duration
            if button.durationText ~= text then button.duration:SetText(text); button.durationText = text end
        else button.entry = nil end
    end
    strip:SetShown(count > 0)
    return count
end
