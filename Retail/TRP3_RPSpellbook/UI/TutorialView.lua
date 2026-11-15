local _, addon = ...
local view = {}
addon.TutorialView = view
local card, highlight, displayed, hubRows
local connector, halos, fitted, dockSide = nil, {}, {}, nil
local GOLD = { 0.88, 0.71, 0.39, 1 }
local CREAM = { 0.95, 0.91, 0.81, 1 }
local MUTED = { 0.69, 0.72, 0.70, 1 }

local function label(parent, font, color)
    local region = addon.UIFactory.CreateLabel(parent, font, "", color)
    region:SetJustifyH("LEFT")
    region:SetWordWrap(true)
    return region
end

local function button(parent, text, width, callback)
    local control = addon.UIFactory.CreateButton(parent, text, width)
    control:SetScript("OnClick", callback)
    return control
end

local function start(id, replay)
    local ok, err = addon.Onboarding.Start(id, replay)
    if not ok then card.status:SetText(err or addon.L("TUTORIAL_RETRY")) end
end

local function create()
    if card then return end
    card = addon.UIFactory.CreateBackdropFrame(UIParent, { 0.035, 0.065, 0.065, 0.98 }, GOLD)
    card:SetFrameStrata("TOOLTIP")
    card:SetSize(360, 286)
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(0.27, 0.64, 0.58, 1)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(3)
    card.chapter = label(card, "GameFontHighlightSmall", GOLD)
    card.chapter:SetPoint("TOPLEFT", 20, -20)
    card.chapter:SetWidth(288)
    card.tour = label(card, "GameFontHighlightSmall", MUTED)
    card.tour:SetPoint("TOPLEFT", 20, -40)
    card.tour:SetWidth(320)
    card.tour:SetHeight(18)
    card.title = label(card, "GameFontNormalLarge", CREAM)
    card.title:SetPoint("TOPLEFT", 20, -67)
    card.title:SetWidth(320)
    card.body = label(card, "GameFontHighlight", CREAM)
    card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -14)
    card.body:SetWidth(320)
    card.body:SetSpacing(3)
    card.status = label(card, "GameFontHighlightSmall", MUTED)
    card.status:SetPoint("BOTTOMLEFT", 20, 48)
    card.status:SetWidth(320)
    card.status:SetHeight(34)
    card.close = button(card, "x", 22, function() addon.Onboarding.Defer() end)
    card.close:SetPoint("TOPRIGHT", -8, -9)
    card.back = button(card, addon.L("TUTORIAL_BACK"), 72, function() addon.Onboarding.Back() end)
    card.back:SetPoint("BOTTOMLEFT", 20, 18)
    card.later = button(card, addon.L("TUTORIAL_LATER"), 92, function() addon.Onboarding.Defer() end)
    card.later:SetPoint("BOTTOMLEFT", 102, 18)
    card.next = button(card, addon.L("TUTORIAL_NEXT"), 126, function() addon.Onboarding.Next() end)
    card.next:SetPoint("BOTTOMRIGHT", -20, 18)
    card.returnToStep = button(card, addon.L("TUTORIAL_RETURN_CONTROL"), 320,
        function() addon.Onboarding.ReturnToStep() end)
    card.returnToStep:SetPoint("BOTTOMLEFT", 20, 86)
    card.returnToStep:Hide()
    card.progress = card:CreateTexture(nil, "ARTWORK")
    card.progress:SetColorTexture(0.27, 0.64, 0.58, 0.9)
    card.progress:SetPoint("BOTTOMLEFT", 1, 1)
    card.progress:SetHeight(3)
    highlight = addon.UIFactory.CreateBackdropFrame(UIParent, { 0, 0, 0, 0 }, GOLD)
    highlight:SetFrameStrata("TOOLTIP")
    highlight:EnableMouse(false)
    for i = 1, 4 do
        local halo = addon.UIFactory.CreateBackdropFrame(highlight, { 0, 0, 0, 0 }, GOLD)
        halo:SetPoint("TOPLEFT", -i * 2, i * 2)
        halo:SetPoint("BOTTOMRIGHT", i * 2, -i * 2)
        halo:EnableMouse(false)
        halos[i] = halo
    end
    local phase = 0
    highlight:SetScript("OnUpdate", function(_, elapsed)
        phase = (phase + elapsed) % 1.5
        local pulse = 0.5 + 0.5 * math.sin(phase / 1.5 * math.pi * 2)
        highlight:SetBackdropColor(1, 0.75, 0.25, 0.035 + pulse * 0.07)
        highlight:SetBackdropBorderColor(1, 0.8 + pulse * 0.16, 0.4 + pulse * 0.3, 1)
        for i, halo in ipairs(halos) do halo:SetAlpha((0.25 + pulse * 0.45) / i) end
    end)
    connector = CreateFrame("Frame", nil, UIParent)
    connector:SetAllPoints(UIParent)
    connector:SetFrameStrata("TOOLTIP")
    connector:EnableMouse(false)
    connector.lines = {}
    for i = 1, 3 do
        local line = connector:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 0.81, 0.44, 0.85)
        connector.lines[i] = line
    end
    connector:Hide()
    highlight:Hide()
    card:Hide()
    hubRows = {}
end

local function reset(mode)
    create()
    displayed = mode
    card:SetSize(360, 286)
    card:SetScale(math.min(1, UIParent:GetWidth() / 390, UIParent:GetHeight() / 520))
    card:ClearAllPoints()
    card:SetPoint("CENTER")
    for _, row in ipairs(hubRows) do row:Hide() end
    card.back:Hide()
    card.returnToStep:Hide()
    card.next:Show()
    card.later:Show()
    card.status:SetText("")
    card.tour:Hide()
    card.title:ClearAllPoints()
    card.title:SetPoint("TOPLEFT", 20, -43)
    card.progress:SetWidth(1)
    highlight:Hide()
    connector:Hide()
    card:Show()
end

local function rect(region)
    if not region or not region:IsVisible() then return nil end
    local l, b, w, h = region:GetRect()
    if not l or not b or not w or not h or w <= 0 or h <= 0 then return nil end
    local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * scale, b * scale, w * scale, h * scale
end

function view.IsTargetVisible(region)
    if not region or not region.IsVisible or not region:IsVisible() then return false end
     
    if not region.GetRect or not region.GetParent then return true end
    local l, b, w, h = rect(region)
    if not l then return false end
    local parent = region:GetParent()
    while parent and parent ~= UIParent do
        if parent.DoesClipChildren and parent:DoesClipChildren() then
            local pl, pb, pw, ph = rect(parent)
            if not pl or l + w <= pl or l >= pl + pw or b + h <= pb or b >= pb + ph then return false end
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return true
end

local function windows()
    local result, seen = {}, {}
    local function add(frame)
        if frame and not seen[frame] and frame:IsVisible() then
            seen[frame] = true
            result[#result + 1] = frame
        end
    end
    for _, frame in ipairs(addon.TRP3Bridge.GetTutorialWindows()) do add(frame) end
    for _, frame in ipairs(addon.UIFactory.GetTutorialWindows()) do add(frame) end
    if addon.GameMasterLayoutEditor and addon.GameMasterLayoutEditor.GetTutorialContext then
        local editor, options, previews = addon.GameMasterLayoutEditor.GetTutorialContext()
        add(editor); add(options)
        for _, preview in pairs(previews or {}) do add(preview) end
    end
    add(addon.TutorialPractice.GetFrame())
    if addon.TutorialPractice.GetWindows then
        for _, frame in ipairs(addon.TutorialPractice.GetWindows()) do add(frame) end
    end
     
    local function depth(frame)
        local count = 0
        while frame and frame ~= UIParent do count = count + 1; frame = frame:GetParent() end
        return count
    end
    table.sort(result, function(a, b) return depth(a) < depth(b) end)
    return result
end

local function remember(frame)
    if fitted[frame] then return end
    local record = { scale = frame:GetScale(), points = {} }
    for i = 1, frame:GetNumPoints() do record.points[i] = { frame:GetPoint(i) } end
    fitted[frame] = record
end

local function fit(frame, left, right, height)
    local x, y, w, h = rect(frame)
    if not x or (frame.IsProtected and frame:IsProtected()) then return end
    local overhang = 0
    local panel = addon.TRP3Integration.GetSpellbookPanel()
    local bookmarks = panel and panel.fancyControls and panel.fancyControls.bookmarkHost
    local ancestor = bookmarks
    while ancestor and ancestor ~= frame and ancestor ~= UIParent do ancestor = ancestor:GetParent() end
    if ancestor == frame then
        local bx, _, bw = rect(bookmarks)
        if bx then overhang = math.max(0, bx + bw - x - w) end
    end
    local ratio = math.min(1, (right - left) / (w + overhang), (height - 24) / h)
    local nx = math.max(left, math.min(right - (w + overhang) * ratio, x))
    local ny = math.max(12, math.min(height - 12 - h * ratio, y))
    if ratio > 0.999 and math.abs(nx - x) < 0.5 and math.abs(ny - y) < 0.5 then return end
    remember(frame)
    frame:SetScale(frame:GetScale() * ratio)
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nx / scale, ny / scale)
end

local function restoreWindows()
    for frame, record in pairs(fitted) do
        frame:SetScale(record.scale)
        frame:ClearAllPoints()
        for _, point in ipairs(record.points) do frame:SetPoint(unpack(point)) end
    end
    fitted, dockSide = {}, nil
end

local function segment(index, x1, y1, x2, y2)
    local line = connector.lines[index]
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.min(x1, x2), math.min(y1, y2))
    line:SetSize(math.max(2, math.abs(x2 - x1)), math.max(2, math.abs(y2 - y1)))
end

local function place(anchor)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    card:SetScale(math.min(1, sw / 720, (sh - 24) / card:GetHeight()))
    local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cw, ch = card:GetWidth() * scale, card:GetHeight() * scale
    local visible = windows()
    local blockers = {}
    for _, frame in ipairs(visible) do blockers[#blockers + 1] = frame end
    local panel = addon.TRP3Integration.GetSpellbookPanel()
    local bookmarks = panel and panel.fancyControls and panel.fancyControls.bookmarkHost
    if bookmarks and bookmarks:IsVisible() then blockers[#blockers + 1] = bookmarks end
    local al, ab, aw, ah = rect(anchor)
    local ax, ay = al and al + aw / 2 or sw / 2, ab and ab + ah / 2 or sh / 2
    local candidates = {}
    local function candidate(x, y, side)
        y = math.max(12, math.min(sh - ch - 12, y))
        if x < 12 or x + cw > sw - 12 then return end
        for _, frame in ipairs(blockers) do
            local l, b, w, h = rect(frame)
            if l and x < l + w + 12 and x + cw > l - 12
                and y < b + h + 12 and y + ch > b - 12 then return end
        end
        local dx, dy = x + cw / 2 - ax, y + ch / 2 - ay
        candidates[#candidates + 1] = { x = x, y = y, side = side,
            score = dx * dx + dy * dy + (dockSide and side ~= dockSide and 2500 or 0) }
    end
    for _, frame in ipairs(blockers) do
        local l, b, w, h = rect(frame)
        if l then
            candidate(l + w + 18, ay - ch / 2, "right")
            candidate(l - cw - 18, ay - ch / 2, "left")
            candidate(math.max(12, math.min(sw - cw - 12, ax - cw / 2)), b + h + 18, "right")
            candidate(math.max(12, math.min(sw - cw - 12, ax - cw / 2)), b - ch - 18, "left")
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    local nearby = candidates[1]
    if nearby then dockSide = nearby.side end
    if not dockSide then
        local leftSpace, rightSpace = sw, sw
        for _, frame in ipairs(visible) do
            local x, _, width = rect(frame)
            if x then leftSpace = math.min(leftSpace, x); rightSpace = math.min(rightSpace, sw - x - width) end
        end
        dockSide = leftSpace > rightSpace and "left" or "right"
    end
    local cardX = nearby and nearby.x or (dockSide == "right" and sw - cw - 12 or 12)
    local cardY = nearby and nearby.y or math.max(12, (sh - ch) / 2)
    card:ClearAllPoints()
    card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cardX / scale, cardY / scale)
     
    local workLeft = dockSide == "right" and 12 or cw + 36
    local workRight = dockSide == "right" and sw - cw - 36 or sw - 12
    if not nearby then
        for _, frame in ipairs(visible) do fit(frame, workLeft, workRight, sh) end
    end
    local l, b, w, h = rect(anchor)
    if not l then highlight:Hide(); connector:Hide(); return end
    local left, bottom = math.max(4, l - 4), math.max(4, b - 4)
    local right, top = math.min(sw - 4, l + w + 4), math.min(sh - 4, b + h + 4)
    if right <= left or top <= bottom then highlight:Hide(); connector:Hide(); return end
    highlight:ClearAllPoints()
    highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    highlight:SetSize(right - left, top - bottom)
    highlight:Show()
    local sourceX = dockSide == "right" and cardX or cardX + cw
    local targetX = dockSide == "right" and right or left
    local sourceY, targetY = cardY + ch / 2, bottom + (top - bottom) / 2
    local elbow = dockSide == "right" and cardX - 12 or cardX + cw + 12
    segment(1, sourceX, sourceY, elbow, sourceY)
    segment(2, elbow, sourceY, elbow, targetY)
    segment(3, elbow, targetY, targetX, targetY)
    connector:Show()
end

function view.RevealScrollChild(scroll, region)
    local _, bottom, _, height = rect(scroll)
    local _, childBottom, _, childHeight = rect(region)
    if not bottom or not childBottom then return false end
    local delta = 0
    if childBottom < bottom + 8 then delta = bottom + 8 - childBottom
    elseif childBottom + childHeight > bottom + height - 8 then
        delta = bottom + height - 8 - childBottom - childHeight
    end
    local scale = scroll:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local offset = math.max(0, math.min(scroll:GetVerticalScrollRange(),
        scroll:GetVerticalScroll() + delta / scale))
    scroll:SetVerticalScroll(offset)
    return true
end

function view.ShowWelcome()
    reset("welcome")
    card.chapter:SetText("TRP3 RP SPELLBOOK")
    card.title:SetText(addon.L("TUTORIAL_WELCOME_TITLE"))
    card.body:SetText(addon.L("TUTORIAL_WELCOME_TEXT"))
    card:SetHeight(math.max(300, card.body:GetStringHeight() + card.title:GetStringHeight() + 194))
    card.status:SetText(addon.L("TUTORIAL_ACCOUNT"))
    card.next:SetText(addon.L("TUTORIAL_START"))
    card.next:SetScript("OnClick", function() start("spellbook", false) end)
    card.later:SetText(addon.L("TUTORIAL_LATER"))
    card.later:SetScript("OnClick", function() addon.Onboarding.Defer() end)
    card.later:ClearAllPoints()
    card.later:SetPoint("BOTTOMLEFT", 20, 18)
    card.close:Hide()
end

function view.ShowHub(entries)
    reset("hub")
    card:SetHeight(456)
    card.chapter:SetText("TRP3 RP SPELLBOOK")
    card.title:SetText(addon.L("TUTORIAL_TITLE"))
    card.body:SetText(addon.L("TUTORIAL_HUB_TEXT"))
    local rowTop = math.max(126, 43 + card.title:GetStringHeight() + card.body:GetStringHeight() + 34)
    card:SetHeight(rowTop + #entries * 52 + 100)
    card.next:Hide()
    card.close:Hide()
    card.later:SetText(addon.L("CLOSE"))
    card.later:SetScript("OnClick", view.Hide)
    card.later:ClearAllPoints()
    card.later:SetPoint("BOTTOMLEFT", 20, 18)
    for i, entry in ipairs(entries) do
        local row = hubRows[i]
        if not row then
            row = button(card, "", 320, function(self) start(self.tourID, true) end)
            row:SetHeight(44)
            hubRows[i] = row
        end
        row.tourID = entry.id
        row:SetPoint("TOPLEFT", 20, -rowTop - (i - 1) * 52)
        local suffix = entry.complete and addon.L("TUTORIAL_DONE_SHORT") or ""
        if not entry.available then suffix = addon.L("TUTORIAL_MODULE_DISABLED") end
        row:SetText(entry.title .. suffix)
        row:SetEnabled(entry.available)
        row:Show()
    end
end

function view.ShowStep(run, step)
    local key = run.id .. ":" .. step.id
    local position, total = 0, 0
    for index, candidate in ipairs(run.tour.steps) do
        if not candidate.skip or not candidate.skip(run.context) then
            total = total + 1
            if index <= run.index then position = total end
        end
    end
    if displayed ~= key then
        reset(key)
        for _, entry in ipairs(addon.Onboarding.GetTours()) do
            if entry.id == run.id then card.tour:SetText(entry.title); break end
        end
        card.tour:Show()
        card.title:ClearAllPoints()
        card.title:SetPoint("TOPLEFT", 20, -67)
        card.title:SetText(addon.L(step.title))
        card.next:SetScript("OnClick", function() addon.Onboarding.Next() end)
        card.later:Hide()
        card.close:Show()
    end
    card.chapter:SetText(addon.L("TUTORIAL_STEP", position, total))
    card.next:SetText(addon.L(position == total and "TUTORIAL_FINISH" or "TUTORIAL_NEXT"))
    card.progress:SetWidth(358 * math.max(0, position - 1) / math.max(1, total))
    card.back:SetShown(#run.visited > 1)
    card.next:SetEnabled(run.ready)
    local navigation = run.navigation
    local key = navigation and navigation.key or step.guidance and step.guidance(run.context) or step.text
    card.body:SetText(addon.L(key, unpack(navigation and navigation.args or step.textArgs and step.textArgs(run.context) or {})))
    local returning = navigation and navigation.recover ~= nil
    card.returnToStep:SetShown(returning == true)
    local expectedIndex = run.index
    card.returnToStep:SetScript("OnClick", function()
        if addon.Onboarding.GetActive() == run and run.index == expectedIndex then addon.Onboarding.ReturnToStep() end
    end)
    card:SetHeight(math.max(256, card.body:GetStringHeight() + card.title:GetStringHeight() + 176 + (returning and 34 or 0)))
    card.status:SetText(run.failed and addon.L("TUTORIAL_RETRY")
        or (run.ready and addon.L(position == total and "TUTORIAL_READY_FINISH"
                or run.autoPending and "TUTORIAL_READY_AUTO" or "TUTORIAL_READY_NEXT")
            or addon.L(run.rewinding and "TUTORIAL_REPEAT_ACTION" or step.waitText or "TUTORIAL_WAIT_ACTION")))
    card:Show()
    place(run.anchor)
end

function view.Suspend()
    if card then card:Hide(); highlight:Hide(); connector:Hide() end
end

function view.UpdateIdle(blocked)
    if displayed == "welcome" or displayed == "hub" then
        card:SetShown(not blocked)
    end
end

function view.Hide()
    view.Suspend()
    restoreWindows()
    displayed = nil
end

function view.GetFrame() return card end
function view.GetHighlight() return highlight, connector end
