local _, addon = ...

addon.SpellTooltip = {}

local function getMagicSummary(spell)
    return addon.SpellPresentation.GetClassificationSummary(spell.tags, spell.effects)
end

local function effectContext(entry, options)
    local source = options.sourcePlayerID or entry.source
    if source then
        local name, color = addon.TRP3Bridge.GetPlayerDisplayIdentity(source)
        if color then name = "|cff" .. color .. name .. "|r" end
        GameTooltip:AddLine(addon.L("AURA_SOURCE", name), 0.8, 0.8, 0.8, true)
    end
    local rounds = entry.spell.effects.durationRounds
    if rounds ~= nil and (entry.combat or options.review) then
        local permanent = rounds == 0
        if entry.combat and rounds ~= 0 and entry.expiresRound then
            local context = addon.GameMasterService.GetSubmissionContext()
            if context then rounds = math.max(0, entry.expiresRound - context.roundNumber) end
        end
        GameTooltip:AddLine(addon.L("TIMED_COMBAT_DURATION", permanent and "\226\136\158" or tostring(rounds)), 0.9, 0.85, 0.7)
    end
    if not entry.combat or rounds == nil then
        local minutes = options.minutes
        if not minutes and not entry.permanent and entry.expiresAt and entry.expiresAt < math.huge then
            minutes = math.max(1, math.ceil((entry.expiresAt - addon.Runtime.GetTimestamp()) / 60))
        end
        if minutes then GameTooltip:AddLine(addon.L("AURA_MINUTES", minutes), 0.9, 0.85, 0.7) end
    end
    if entry.hidden then
        GameTooltip:AddLine(addon.L(options.review and "TIMED_HIDDEN_HELP" or "TIMED_HIDDEN"), 0.8, 0.7, 0.55, true)
    end
end

function addon.SpellTooltip.Show(owner, spell, canEdit, anchor, options)
    if not owner or type(spell) ~= "table" then
        return false
    end

    options = type(options) == "table" and options or {}
    local effect = type(options.effect) == "table" and options.effect or nil
    local function text(value)
        if effect then return tostring(value or ""):gsub("|", "||") end
        return value
    end
    local red, green, blue = addon.UIFactory.GetColorRGB(spell.nameColor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text(spell.name or addon.L("UNKNOWN_ABILITY")), red, green, blue)

    local magicSummary = getMagicSummary(spell)
    if magicSummary then
        GameTooltip:AddLine(text(magicSummary), 0.65, 0.72, 0.82)
    end

    local hasResource = type(spell.resource) == "string" and spell.resource ~= ""
    local hasRange = type(spell.range) == "string" and spell.range ~= ""
    if hasResource or hasRange then
        GameTooltip:AddDoubleLine(hasResource and text(spell.resource) or "",
            hasRange and (addon.L("FIELD_RANGE") .. ": " .. text(spell.range)) or "", 1, 1, 1, 1, 1, 1)
    end
    local castTime, cooldown = addon.SpellPresentation.GetTooltipTiming(spell)
    if castTime or cooldown then
         
        GameTooltip:AddDoubleLine(text(castTime or " "), text(cooldown or ""), 1, 1, 1, 1, 1, 1)
    end
    local effectText = addon.SpellPresentation.GetEffectTooltipText(spell)
    if effect then effectContext(effect, options)
    elseif effectText then GameTooltip:AddLine(effectText, 1, 1, 1) end
    if type(spell.description) == "string" and spell.description ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(text(spell.description), 1, 0.82, 0, true)
    end

    if effect then
        if options.showChatHint then GameTooltip:AddLine(addon.L("TIMED_SHARE"), 0.7, 0.7, 0.7) end
        if options.showDismissHint then GameTooltip:AddLine(addon.L("AURA_DISMISS"), 0.7, 0.7, 0.7) end
        GameTooltip:Show()
        return true
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(addon.L("LEFT_CLICK_DETAILS"), 0.76, 0.69, 0.56)
    if options.showChatHint ~= false then
        GameTooltip:AddLine(addon.L("SHIFT_CLICK_CHAT"), 0.76, 0.69, 0.56)
    end
    if canEdit then
        GameTooltip:AddLine(addon.L("RIGHT_CLICK_EDIT"), 0.76, 0.69, 0.56)
    end
    GameTooltip:Show()
    return true
end

function addon.SpellTooltip.ShowUnknown(owner, displayName, anchor)
    if not owner then
        return false
    end

    GameTooltip:SetOwner(owner, anchor or "ANCHOR_CURSOR")
    GameTooltip:SetText(addon.ChatLinks.SanitizeDisplayName(displayName), 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(addon.L("UNKNOWN_LINK_MESSAGE"), 1, 1, 1, true)
    GameTooltip:Show()
    return true
end

local function showRemoteStatus(owner, displayName, message, includeClickHint, anchor)
    if not owner then
        return false
    end

    GameTooltip:SetOwner(owner, anchor or "ANCHOR_CURSOR")
    GameTooltip:SetText(addon.ChatLinks.SanitizeDisplayName(displayName), 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(message, 1, 1, 1, true)
    if includeClickHint then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(addon.L("LEFT_CLICK_DETAILS"), 0.76, 0.69, 0.56)
    end
    GameTooltip:Show()
    return true
end

function addon.SpellTooltip.ShowRemoteLoading(owner, displayName, anchor)
    return showRemoteStatus(owner, displayName, addon.L("CHAT_HOVER_LOADING"), false, anchor)
end

function addon.SpellTooltip.ShowRemoteUnavailable(owner, displayName, anchor)
    return showRemoteStatus(owner, displayName, addon.L("CHAT_HOVER_UNAVAILABLE"), true, anchor)
end

function addon.SpellTooltip.Hide()
    GameTooltip:Hide()
end
