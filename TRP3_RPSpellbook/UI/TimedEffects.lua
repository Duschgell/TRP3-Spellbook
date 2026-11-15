local _, addon = ...
addon.TimedEffectsView = {}
local view, factory, theme = addon.TimedEffectsView, addon.UIFactory, addon.Theme
local manager, castDialog
local page, viewedPlayer = 1, nil
local offerLinks = {}
local offerLinkPrefix = "addon:rpspellbook:offer:"

local function plain(value) return tostring(value or ""):gsub("|", "||") end
local function label(parent, text, x, y, width)
    local item = factory.CreateLabel(parent, theme.Fonts.body, text, theme.Colors.text)
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    item:SetWidth(width)
    item:SetJustifyH("LEFT")
    return item
end
local function button(parent, text, width, x, y, callback)
    local item = factory.CreateButton(parent, text, width)
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    item:SetScript("OnClick", callback)
    return item
end
local function me() return addon.GameMasterRoster.GetLocalPlayerID() end
local function isSelf()
    return addon.Runtime.NormalizePlayerID(viewedPlayer) == addon.Runtime.NormalizePlayerID(me())
end
local function kind(spell) return addon.L(spell.effects.debuff and "TIMED_DEBUFF" or "TIMED_BUFF") end
local function sourceName(playerID)
    local name, color = addon.TRP3Bridge.GetPlayerDisplayIdentity(playerID)
    return color and ("|cff" .. color .. name .. "|r") or name
end

local function liveOffers()
    local offers, live = addon.TimedEffects.Offers(), {}
    for _, offer in ipairs(offers) do if offer.entry then live[offer] = true end end
    for link, offer in pairs(offerLinks) do
        if not live[offer] then offerLinks[link] = nil end
    end
    return offers
end

function view.NotifyOffer(offer)
    local found = false
    for _, current in ipairs(liveOffers()) do if current == offer and current.entry then found = true end end
    if not found then return false end
    for _, current in pairs(offerLinks) do if current == offer then return false end end
    local link = offerLinkPrefix .. offer.id
    offerLinks[link] = offer
    local spell = offer.entry.spell
    local texture = addon.TRP3Bridge.ResolveIconTexture(spell.icon)
    local icon = texture and ("|T" .. tostring(texture):gsub("[%c|:]", "") .. ":20:20|t ") or ""
    local name = addon.ChatLinks.SanitizeDisplayName(spell.name)
    local red, green, blue = factory.GetColorRGB(spell.nameColor)
    local color = string.format("ff%02x%02x%02x", math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5))
    local title = "|c" .. color .. "|H" .. link .. "|h[" .. name .. "]|h|r"
    local message = addon.L("TIMED_OFFER", sourceName(offer.sender), kind(spell), title, offer.minutes)
    if offer.entry.hidden then message = message .. " - " .. addon.L("TIMED_HIDDEN") end
    addon.Logger.Info(icon .. addon.L("TIMED_INCOMING", message))
    return true
end

function view.HandleOfferLink(link, mouseButton)
    if type(link) ~= "string" or link:sub(1, #offerLinkPrefix) ~= offerLinkPrefix then return false end
    if mouseButton and mouseButton ~= "LeftButton" then return true end
    if IsShiftKeyDown and IsShiftKeyDown() then return true end
    liveOffers()
    local offer = offerLinks[link]
    if not offer then addon.Logger.Info(addon.L("TIMED_OFFER_EXPIRED")); return true end
     
     
    view.Open(me(), offer.id)
    return true
end

local function refresh()
    if not manager or not manager:IsShown() then return end
    local entries, own = {}, isSelf()
    if not own then addon.TimedEffects.RequestSnapshot(viewedPlayer) end
    if own then
        for _, offer in ipairs(addon.TimedEffects.Offers()) do
            if offer.entry then entries[#entries + 1] = { offer = offer, entry = offer.entry } end
        end
    end
    local count = addon.EffectIcons.Update(manager.icons, viewedPlayer)
    local top = 66 + (count > 0 and manager.icons:GetHeight() or 36)
    manager:SetHeight(math.max(230, top + math.min(3, #entries) * 96 + 76))
    page = math.max(1, math.min(page, math.ceil(#entries / 3)))
    manager.empty:SetShown(count == 0)
    manager.empty:SetText(addon.L(addon.EffectIcons.IsSuppressed() and "AURA_GAMEPLAY_HIDDEN" or "TIMED_EMPTY"))
    manager.policy:SetShown(own)
    manager.policy:SetText(addon.L(addon.TimedEffectsStore.AllowsOffers() and "TIMED_BLOCK" or "TIMED_ALLOW"))
    manager.previous:SetEnabled(page > 1)
    manager.next:SetEnabled(page * 3 < #entries)
    manager.previous:SetShown(#entries > 3)
    manager.next:SetShown(#entries > 3)
    for index, row in ipairs(manager.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 18, -top - (index - 1) * 96)
        local value = entries[(page - 1) * 3 + index]
        row:SetShown(value ~= nil)
        if value then
            local entry, offer = value.entry, value.offer
            addon.BookLayout.SetSpellIcon(row.icon, entry.spell, addon.Constants.DEFAULT_SPELL_ICON, true)
            row.title:SetText(plain(entry.spell.name))
            factory.SetFontColor(row.title, entry.spell.nameColor)
            row.text:SetText(addon.L("TIMED_OFFER_DETAILS", kind(entry.spell), sourceName(offer.sender), offer.minutes)
                .. (entry.hidden and " - " .. addon.L("TIMED_HIDDEN") or ""))
            row.accept:Show()
            row.remove:SetShown(own)
            row.remove:SetText(addon.L("TIMED_DECLINE"))
            row.accept:SetScript("OnClick", function()
                if not addon.TimedEffects.Decide(offer.id, true) then addon.Logger.Error(addon.L("TIMED_FULL")) end
                refresh()
            end)
            row.remove:SetScript("OnClick", function()
                addon.TimedEffects.Decide(offer.id, false)
                refresh()
            end)
            row:SetScript("OnEnter", function()
                addon.SpellTooltip.Show(row, entry.spell, false, "ANCHOR_RIGHT", {
                    effect = entry, sourcePlayerID = offer.sender, minutes = offer.minutes, review = true,
                })
            end)
            row:SetScript("OnLeave", addon.SpellTooltip.Hide)
        end
    end
end

function view.Open(target, offerID)
    viewedPlayer, page = target or me(), 1
    if not manager then
        manager = factory.CreateDialog(addon.L("TIMED_TITLE"), 570, 530)
        manager.icons = addon.EffectIcons.Create(manager, 24, 16, 128)
        addon.EffectIcons.Configure(manager.icons, { width = 520, maxHeight = 260, minSize = 20, maxSize = 48, gap = 5 })
        manager.icons:SetPoint("TOP", 0, -48)
        manager.empty = label(manager, addon.L("TIMED_EMPTY"), 18, -48, 530)
        manager.rows = {}
        for index = 1, 3 do
            local row = CreateFrame("Frame", nil, manager)
            row:SetSize(532, 94)
            row:SetPoint("TOPLEFT", 18, -100 - (index - 1) * 96)
            row:EnableMouse(true)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(40, 40)
            row.icon:SetPoint("TOPLEFT", 0, -2)
            row.title = label(row, "", 50, 0, 480)
            row.title:SetHeight(20)
            row.text = label(row, "", 50, -24, 480)
            row.text:SetHeight(34)
            row.accept = button(row, addon.L("TIMED_ACCEPT"), 100, 50, -62, function() end)
            row.remove = button(row, addon.L("TIMED_REMOVE"), 100, 158, -62, function() end)
            manager.rows[index] = row
        end
        manager.policy = button(manager, "", 200, 18, -480, function()
            local setAllowsOffers = addon.TimedEffects.SetAllowsOffers or addon.TimedEffectsStore.SetAllowsOffers
            setAllowsOffers(not addon.TimedEffectsStore.AllowsOffers())
            refresh()
        end)
        manager.previous = button(manager, "<", 45, 420, -480, function() page = page - 1; refresh() end)
        manager.next = button(manager, ">", 45, 475, -480, function() page = page + 1; refresh() end)
        manager.policy:ClearAllPoints()
        manager.policy:SetPoint("BOTTOMLEFT", 18, 18)
        manager.previous:ClearAllPoints()
        manager.previous:SetPoint("BOTTOMRIGHT", -86, 18)
        manager.next:ClearAllPoints()
        manager.next:SetPoint("BOTTOMRIGHT", -24, 18)
        manager:SetScript("OnShow", refresh)
        addon.TimedEffects.RegisterListener(refresh)
    end
    addon.TimedEffects.RequestSnapshot(viewedPlayer)
    manager:Show()
    if offerID and isSelf() then
        local index = 0
        for _, offer in ipairs(liveOffers()) do
            if offer.entry then
                index = index + 1
                if offer.id == offerID then page = math.ceil(index / 3); break end
            end
        end
    end
    refresh()
    factory.BringToFront(manager)
end

function view.Cast(spellID)
    if not addon.TimedEffects.CanCast(spellID) then addon.Logger.Error(addon.L("TIMED_INVALID")); return end
    if not castDialog then
        castDialog = factory.CreateDialog(addon.L("TIMED_CAST"), 430, 414)
        castDialog.spellName = label(castDialog, "", 18, -42, 390)
        castDialog.selector = addon.GameMasterWidgets.CreateSelector(castDialog, 390, addon.L("TIMED_SELF"))
        castDialog.selector:SetPoint("TOPLEFT", 18, -75)
        castDialog.selector:SetOnValueChanged(function(value) castDialog.target = value end)
        label(castDialog, addon.L("TIMED_MINUTES"), 18, -118, 390)
        castDialog.minutes = factory.CreateEditBox(castDialog, false)
        castDialog.minutes:SetSize(100, 24)
        castDialog.minutes:SetPoint("TOPLEFT", 18, -142)
        castDialog.minutes:SetMaxLetters(4)
        castDialog.minutes:SetNumeric(true)
        castDialog.hidden = CreateFrame("CheckButton", nil, castDialog, "UICheckButtonTemplate")
        castDialog.hidden:SetSize(26, 26)
        castDialog.hidden:SetPoint("TOPLEFT", 16, -213)
        local hiddenLabel = label(castDialog, addon.L("TIMED_HIDDEN"), 46, -219, 360)
        hiddenLabel:ClearAllPoints()
        hiddenLabel:SetPoint("LEFT", castDialog.hidden, "RIGHT", 4, 0)
        castDialog.hiddenHelp = label(castDialog, addon.L("TIMED_HIDDEN_HELP"), 18, -249, 390)
        castDialog.apply = button(castDialog, addon.L("TIMED_CAST"), 140, 268, -372, function()
            if castDialog.profile ~= addon.Database.GetActiveProfileKey() then castDialog:Hide(); return end
            local success, message = addon.TimedEffects.Cast(castDialog.spellID, castDialog.target, castDialog.minutes:GetText(), castDialog.hidden:GetChecked())
            if success then
                if addon.QuickAccess then addon.QuickAccess.SetMinutes(castDialog.minutes:GetText()) end
                local profileData = addon.Database.GetActiveProfileData()
                if profileData then profileData.quickEffectHidden = castDialog.hidden:GetChecked() == true end
                addon.Logger.Info(message); castDialog:Hide()
            else addon.Logger.Error(message) end
        end)
        castDialog.combatHint = label(castDialog, "", 18, -181, 390)
        castDialog.help = label(castDialog, addon.L("TIMED_HELP"), 18, -310, 390)
    end
    local options = { { value = me(), label = addon.L("TIMED_SELF") } }
    for _, member in ipairs(addon.GameMasterRoster.GetMembers()) do
        if member.playerKey ~= addon.Runtime.NormalizePlayerID(me()) and member.online then
            options[#options + 1] = { value = member.playerID, label = plain(member.rpName) }
        end
    end
    castDialog.profile, castDialog.spellID, castDialog.target = addon.Database.GetActiveProfileKey(), spellID, me()
    castDialog.spellName:SetText(plain(addon.Database.GetSpell(spellID).name))
    local effects = addon.Database.GetSpell(spellID).effects
    castDialog.combatHint:SetText(addon.L(effects.durationRounds ~= nil and "TIMED_ROUNDS" or "TIMED_NO_ROUNDS"))
    castDialog.selector:SetOptions(options, me())
    castDialog.minutes:SetText(tostring(addon.QuickAccess and addon.QuickAccess.Minutes() or 30))
    local profileData = addon.Database.GetActiveProfileData()
    castDialog.hidden:SetChecked(profileData and profileData.quickEffectHidden == true)
    local top = 181 + castDialog.combatHint:GetStringHeight() + 12
    castDialog.hidden:ClearAllPoints(); castDialog.hidden:SetPoint("TOPLEFT", 16, -top)
    top = top + 34
    castDialog.hiddenHelp:ClearAllPoints(); castDialog.hiddenHelp:SetPoint("TOPLEFT", 18, -top)
    top = top + castDialog.hiddenHelp:GetStringHeight() + 18
    castDialog.help:ClearAllPoints(); castDialog.help:SetPoint("TOPLEFT", 18, -top)
    top = top + castDialog.help:GetStringHeight() + 20
    castDialog.apply:ClearAllPoints(); castDialog.apply:SetPoint("TOPLEFT", 268, -top)
    castDialog:SetHeight(top + 42)
    castDialog:Show()
    factory.BringToFront(castDialog)
end

function view.Initialize()
    if addon.EffectSurfaces then addon.EffectSurfaces.Initialize() end
end
