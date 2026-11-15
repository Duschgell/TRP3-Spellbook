local _, addon = ...
addon.CurrentlyEffectsEditor = {}
local editor = addon.CurrentlyEffectsEditor
local state, initialized, failedInstall, buildingFrame
local refresh, layout, finishDrag

local function model() return addon.CurrentlyEffects.GetEditorModel() end
local function safe(callback)
    return function(...)
        local ok, failure = pcall(callback, ...)
        if not ok and addon.Logger then addon.Logger.Error(tostring(failure)) end
    end
end
local function copyNativeFont(target, source)
    if not source then return end
    local object = source:GetFontObject()
    if target:GetFontObject() ~= object then target:SetFontObject(object) end
    local path, size, flags = source:GetFont()
    local oldPath, oldSize, oldFlags = target:GetFont()
    if path and size and target.SetFont and (path ~= oldPath or size ~= oldSize or flags ~= oldFlags) then
        target:SetFont(path, size, flags)
    end
    if source.GetShadowColor and target.SetShadowColor then target:SetShadowColor(source:GetShadowColor()) end
    if source.GetShadowOffset and target.SetShadowOffset then target:SetShadowOffset(source:GetShadowOffset()) end
    if source.GetSpacing and target.SetSpacing then target:SetSpacing(source:GetSpacing()) end
end
local function noteAppearance(field)
    local box = field:GetEditBox()
    local source = field.nativeFontSource
    if source then box.fontName = source:GetFontObject(); copyNativeFont(box, source) end
    local white = _G.WHITE_FONT_COLOR or _G.HIGHLIGHT_FONT_COLOR
     
    if box.ApplyTextColor and white and type(white.GetRGB) == "function" then box:ApplyTextColor(white) end
    if source and source.GetTextColor then box:SetTextColor(source:GetTextColor()) else box:SetTextColor(1, 1, 1, 1) end
    box:SetAlpha(1)
    field:SetAlpha(1)
end
local function setText(field, text)
    if field:GetInputText() == text then return end
    local box = field:GetEditBox()
    if box.ApplyText then
        box:ApplyText(field.escapeSanitized and text:gsub("|", "||") or text)
    else field:SetText(text) end
    noteAppearance(field)
end
local function inlineText(current)
    local before, after = current.before:GetInputText(), current.after:GetInputText()
     
    local separator = ""
    if not current.splitWithinLine and before ~= "" and after ~= "" and before:sub(-1) ~= "\n"
        and after:sub(1, 1) ~= "\n" and after:sub(1, 2) ~= "\r\n" then
        separator = (before:find("\r\n", 1, true) or after:find("\r\n", 1, true)) and "\r\n" or "\n"
    end
    return before .. separator .. after, #before + #separator
end
local function personal(current)
    if current.inline then return (inlineText(current)) end
    return current.plain:GetInputText()
end
local function position(current)
    if current.inline then local _, offset = inlineText(current); return offset end
    return current.position
end
local function splitNotes(current, text, offset)
    local before, after = text:sub(1, offset), text:sub(offset + 1)
    current.splitWithinLine = before ~= "" and after ~= "" and before:sub(-1) ~= "\n"
        and after:sub(1, 1) ~= "\n" and after:sub(1, 2) ~= "\r\n"
    setText(current.before, before)
    setText(current.after, after)
end
local function rowFeedback(current)
    local target = current.drag and current.drag.index and current.keys[current.drag.index]
    for _, row in ipairs(current.rows) do
        local selected = row.key ~= nil and current.selectedKey == row.key
        local hovered = row.key ~= nil and current.hoverKey == row.key
        local receiving = target ~= nil and target == row.key and not selected
        row.feedback:SetShown(selected or hovered or receiving)
        row.accent:SetShown(selected or receiving)
        if receiving then row.feedback:SetColorTexture(0.40, 0.58, 0.64, 0.40)
        elseif selected then row.feedback:SetColorTexture(0.28, 0.43, 0.52, 0.48)
        else row.feedback:SetColorTexture(0.55, 0.59, 0.64, 0.22) end
        local color = current.colors and current.colors[row.key]
        row.label:SetTextColor(color and color[1] or 0.69, color and color[2] or 0.70, color and color[3] or 0.72)
    end
end
local function cancelDrag(current)
    current.drag = nil
    current.ghost:Hide()
    current.indicator:Hide()
    current.block:SetAlpha(1)
    current.frame:SetScript("OnUpdate", nil)
    current.frame:EnableKeyboard(false)
    rowFeedback(current)
end
local function commit(current, profileID)
    local view = not current.readOnly and model() or nil
    if not view or view.profileID ~= profileID then return false end
    local saved = addon.CurrentlyEffects.CommitPersonalText(personal(current), position(current), profileID, current.keys)
    if saved then
        current.dirty = false
        current.original:TriggerEvent("OnTextChanged", true)
    end
    return saved
end
local function changed(current, userInput)
    if not userInput or current.readOnly or current.rendering then return end
    local view = model()
    if not view then
        current.personalText = personal(current)
        current.original:TriggerEvent("OnTextChanged", true)
        return
    end
    if current.profileID and view.profileID ~= current.profileID then refresh(); return end
    current.personalText, current.position = personal(current), position(current)
    current.dirty, current.profileID = true, view.profileID
    current.editSerial = current.editSerial + 1
    local serial, profileID = current.editSerial, current.profileID
    layout(current)
    local function run()
        if state ~= current or serial ~= current.editSerial or current.readOnly then return end
        commit(current, profileID)
        refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, safe(run)) else run() end
end
local function cursor(current)
    local x, y = GetCursorPosition()
    local scale = current.scroll:GetEffectiveScale()
    local left, top = current.scroll:GetLeft(), current.scroll:GetTop()
    if not left or not top or not scale or scale <= 0 then return nil end
    x, y = x / scale - left, top - y / scale
    return x, y, x >= 0 and x <= current.scroll:GetWidth() and y >= 0 and y <= current.scroll:GetHeight()
end
local function measure(current, text, width)
    current.measure:SetWidth(math.max(1, width))
    current.measure:SetText(text == "" and " " or text)
    return math.max(current.lineHeight, current.measure:GetStringHeight())
end
local function hitBounds(current)
    if not current.inline or not current.geometryReady or current.layingOut or current.rendering then return end
    if type(current.before.documentY) ~= "number" or type(current.after.documentY) ~= "number" then return end
    local offset, height = current.scroll:GetVerticalScroll(), current.scroll:GetHeight()
    for _, field in ipairs({ current.before, current.after }) do
        local top = math.max(0, offset - field.documentY)
        local bottom = math.max(0, field.documentY + field:GetHeight() - offset - height)
        for _, region in ipairs({ field.EditBox, field.FocusCapture }) do
            if region.SetHitRectInsets then region:SetHitRectInsets(0, 0, top, bottom) end
        end
    end
end
local function setScroll(current, value)
    if not current.inline or not current.geometryReady or current.layingOut or current.rendering then return end
    local range = math.max(0, current.content:GetHeight() - current.scroll:GetHeight())
    current.scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
    hitBounds(current)
end
local function addAnchors(current, text, base, y, width)
    local offset = 0
    current.anchors[#current.anchors + 1] = { offset = base, y = y }
    while offset < #text do
        local newline = text:find("\n", offset + 1, true)
        if not newline then break end
        local line = text:sub(offset + 1, newline - 1):gsub("\r$", "")
        y = y + measure(current, line, width)
        offset = newline
        current.anchors[#current.anchors + 1] = { offset = base + offset, y = y }
    end
end
local function tooltip(current, owner, key)
    if current.readOnly then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.L(key))
    GameTooltip:Show()
end
local function dragTick(current, delta, freshView)
    if not current.geometryReady or current.layingOut or current.rendering then cancelDrag(current); return end
    local drag = current.drag
    local view = freshView or (drag and drag.view)
    if not freshView and addon.TRP3Bridge and addon.TRP3Bridge.GetActiveProfileID then
        if not drag or addon.TRP3Bridge.GetActiveProfileID() ~= drag.profileID then cancelDrag(current); return end
    elseif not freshView then view = model() end
    if not drag or current.readOnly or not view or view.profileID ~= drag.profileID
        or not view.enabled or #view.lines == 0 then cancelDrag(current); return end
    if drag.kind == "row" then
        local present = false
        for _, key in ipairs(view.keys) do if key == drag.key then present = true; break end end
        if not present then cancelDrag(current); return end
    end
    local x, y, inside = cursor(current)
    drag.inside = inside
    if not x or not inside then
        drag.index = nil
        current.indicator:Hide(); current.ghost:Hide(); rowFeedback(current); return
    end
    current.ghost:Show()
    local ghostWidth = current.ghost:GetWidth()
    current.ghost:ClearAllPoints()
    current.ghost:SetPoint("TOPLEFT", current.scroll, "TOPLEFT",
        math.max(0, math.min(current.scroll:GetWidth() - ghostWidth, x - 12)), -math.max(0, y - 8))
    if y < 18 then setScroll(current, current.scroll:GetVerticalScroll() - delta * 100)
    elseif y > current.scroll:GetHeight() - 18 then setScroll(current, current.scroll:GetVerticalScroll() + delta * 100) end
    local documentY = y + current.scroll:GetVerticalScroll()
    local markerY
    if drag.kind == "block" then
        local best, distance
        for _, anchor in ipairs(current.anchors) do
            local nextDistance = math.abs(documentY - anchor.y)
            if not distance or nextDistance < distance then best, distance = anchor, nextDistance end
        end
        drag.offset, markerY = best.offset, best.y
    else
        drag.index = nil
        for index, row in ipairs(current.rows) do
            if row:IsShown() and documentY >= current.blockY + row.documentY
                and documentY <= current.blockY + row.documentY + row:GetHeight() then
                drag.index, markerY = index, current.blockY + row.documentY
                break
            end
        end
        if not drag.index then current.indicator:Hide(); rowFeedback(current); return end
    end
    current.indicator:ClearAllPoints()
    current.indicator:SetPoint("TOPLEFT", current.content, "TOPLEFT", 2, -markerY)
    current.indicator:SetWidth(math.max(1, current.scroll:GetWidth() - 4))
    current.indicator:Show()
    rowFeedback(current)
end
local function beginDrag(current, kind, key)
    local view = not current.readOnly and model() or nil
    if not current.inline or not current.geometryReady or current.layingOut or current.rendering
        or not view or view.profileID ~= current.profileID then return end
    current.before:ClearFocus(); current.after:ClearFocus()
    current.editSerial = current.editSerial + 1
    current.drag = { kind = kind, key = key, profileID = view.profileID, view = view }
    if kind == "row" then current.selectedKey = key end
    local label = key
    if kind == "row" then
        for index, candidate in ipairs(current.keys) do if candidate == key then label = current.lines[index]; break end end
    end
    current.ghostLabel:SetText(kind == "row" and label or table.concat(current.lines, "\n", 1, math.min(4, #current.lines)))
    local color = kind == "row" and current.colors and current.colors[key]
    current.ghostLabel:SetTextColor(color and color[1] or 0.74, color and color[2] or 0.76, color and color[3] or 0.78)
    current.ghost:SetSize(math.max(1, math.min(220, current.scroll:GetWidth())),
        kind == "row" and current.lineHeight + 12 or math.min(4, #current.lines) * current.lineHeight + 12)
    current.block:SetAlpha(kind == "block" and 0.45 or 1)
    current.frame:EnableKeyboard(true)
    current.frame:SetScript("OnUpdate", safe(function(_, delta) dragTick(current, math.min(delta, 0.1)) end))
    dragTick(current, 0, view)
end
finishDrag = function(current)
    local drag, view = current.drag, not current.readOnly and model() or nil
    if not drag then return end
    if not view then cancelDrag(current); return end
    dragTick(current, 0, view)
    if current.drag ~= drag then return end
    cancelDrag(current)
    if not drag.inside or not view or view.profileID ~= drag.profileID or not view.enabled then return end
    if drag.kind == "block" and drag.offset ~= nil then
        current.personalText = personal(current)
        current.position = drag.offset
        current.rendering = true
        splitNotes(current, current.personalText, drag.offset)
        current.rendering = false
    elseif drag.kind == "row" and drag.index then
        local source
        for index, key in ipairs(current.keys) do if key == drag.key then source = index; break end end
        if not source then return end
        local key = table.remove(current.keys, source)
        table.insert(current.keys, drag.index, key)
    else return end
    current.dirty = true
    commit(current, drag.profileID)
    refresh()
end

local function buildGeometry(current, width, before, after)
    current.content:SetWidth(width)
    local ok, height = pcall(current.before.GetFontHeight, current.before)
    if not ok or type(height) ~= "number" or height ~= height or height <= 0 or height == math.huge then
        local _, size = current.measure:GetFont()
        height = tonumber(size) or 12
    end
    current.lineHeight = math.max(1, height)
    local beforeHeight = measure(current, before, width) + 2
    current.before.documentY = 0
    current.before:SetPoint("TOPLEFT", current.content, "TOPLEFT", 0, 0)
    current.before:SetSize(width, beforeHeight)
    local blockY, rowY = beforeHeight + 3, 10
    current.block:SetPoint("TOPLEFT", current.content, "TOPLEFT", 0, -blockY)
    current.block:SetWidth(width)
    for index, line in ipairs(current.lines) do
        local row = current.rows[index]
        if not row then
            row = CreateFrame("Button", nil, current.block)
            row.feedback = row:CreateTexture(nil, "BACKGROUND")
            row.feedback:SetAllPoints(row)
            row.accent = row:CreateTexture(nil, "OVERLAY")
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.accent:SetWidth(2)
            row.accent:SetColorTexture(0.73, 0.85, 0.91, 0.95)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            copyNativeFont(row.label, current.fontSource)
            row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 7, 0)
            row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -7, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetJustifyV("TOP")
            row.label:SetTextColor(0.69, 0.70, 0.72)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", safe(function(self) beginDrag(current, "row", self.key) end))
            row:SetScript("OnDragStop", safe(function() finishDrag(current) end))
            row:SetScript("OnClick", function(self) current.selectedKey = self.key; rowFeedback(current) end)
            row:SetScript("OnEnter", function(self)
                current.hoverKey = self.key; rowFeedback(current); tooltip(current, self, "CURRENTLY_EDITOR_SORT")
            end)
            row:SetScript("OnLeave", function(self)
                if current.hoverKey == self.key then current.hoverKey = nil end
                rowFeedback(current); GameTooltip:Hide()
            end)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) setScroll(current, current.scroll:GetVerticalScroll() - delta * 28) end)
            current.rows[index] = row
        end
        row.key, row.documentY = current.keys[index], rowY
        copyNativeFont(row.label, current.fontSource)
        row.label:SetText(line)
        local rowHeight = measure(current, line, math.max(1, width - 14)) + 3
        row:SetPoint("TOPLEFT", current.block, "TOPLEFT", 0, -rowY)
        row:SetSize(width, rowHeight)
        row:Show()
        rowY = rowY + rowHeight
    end
    for index = #current.lines + 1, #current.rows do current.rows[index]:Hide() end
    local blockHeight = rowY + 4
    current.block:SetHeight(blockHeight)
    current.blockY = blockY
    local afterY = blockY + blockHeight + 3
    local afterHeight = math.max(measure(current, after, width) + 2, current.scroll:GetHeight() - afterY)
    current.after.documentY = afterY
    current.after:SetPoint("TOPLEFT", current.content, "TOPLEFT", 0, -afterY)
    current.after:SetSize(width, afterHeight)
    current.content:SetHeight(math.max(current.scroll:GetHeight(), afterY + afterHeight))
    current.scroll:UpdateScrollChildRect()
    current.anchors = {}
    addAnchors(current, before, 0, 0, width)
    current.anchors[#current.anchors + 1] = { offset = #before, y = blockY }
    local afterOffset = position(current)
    addAnchors(current, after, afterOffset, afterY, width)
    current.anchors[#current.anchors + 1] = { offset = afterOffset + #after, y = afterY + measure(current, after, width) }
end

layout = function(current)
    if current.layingOut then return end
    local width = math.max(1, current.scroll:GetWidth())
    local before, after = current.before:GetInputText(), current.after:GetInputText()
    local signature = table.concat(current.lines, "\n")
    local keySignature = table.concat(current.keys, "\n")
    if current.geometryReady and current.layoutWidth == width and current.layoutBefore == before and current.layoutAfter == after
        and current.layoutLines == signature and current.layoutKeys == keySignature
        and current.layoutViewport == current.scroll:GetHeight() then return end
     
    current.layingOut, current.geometryReady = true, false
    local ok, failure = pcall(buildGeometry, current, width, before, after)
    current.layingOut = false
    if not ok then current.layoutWidth = nil; cancelDrag(current); error(failure, 0) end
    current.layoutWidth, current.layoutBefore, current.layoutAfter = width, before, after
    current.layoutLines, current.layoutViewport, current.layoutKeys = signature, current.scroll:GetHeight(), keySignature
    current.geometryReady = true
    rowFeedback(current)
    setScroll(current, current.scroll:GetVerticalScroll())
end

refresh = function()
    local current = state
    if not current or current.rendering then return end
    local view = not current.readOnly and model() or nil
    if view and current.profileID and view.profileID ~= current.profileID then
        current.selectedKey, current.hoverKey = nil, nil
        cancelDrag(current)
        current.dirty, current.editSerial, current.keys = false, current.editSerial + 1, {}
    end
    local text = current.dirty and personal(current) or view and view.personalText or current.personalText or ""
    if current.drag and (not view or view.profileID ~= current.drag.profileID or #view.lines == 0) then cancelDrag(current) end
    local inline = view ~= nil and view.enabled and #view.lines > 0
    if view then
        current.profileID = view.profileID
        current.colors = view.colors or {}
        if not current.dirty and not current.drag then current.position, current.keys = view.position, view.keys end
        local available, keys, lines, used = {}, {}, {}, {}
        for index, key in ipairs(view.keys) do available[key] = view.lines[index] end
        for _, key in ipairs(current.keys) do
            if available[key] and not used[key] then
                keys[#keys + 1], lines[#lines + 1], used[key] = key, available[key], true
            end
        end
        for index, key in ipairs(view.keys) do
            if not used[key] then keys[#keys + 1], lines[#lines + 1], used[key] = key, view.lines[index], true end
        end
        current.keys, current.lines = keys, lines
    else current.lines, current.colors = {}, {} end
    current.position = addon.CurrentlyEffects.PositionOffset(text, current.position)
    current.personalText = text
    current.rendering = true
    local ok, failure = pcall(function()
        local path, size, flags = current.fontSource:GetFont()
        local spacing = current.fontSource.GetSpacing and current.fontSource:GetSpacing() or 0
        local fontSignature = table.concat({ tostring(path), tostring(size), tostring(flags), tostring(spacing) }, "\031")
        if current.fontSignature ~= fontSignature then current.fontSignature, current.layoutWidth = fontSignature, nil end
        copyNativeFont(current.measure, current.fontSource)
        for _, field in ipairs({ current.plain, current.before, current.after }) do noteAppearance(field) end
        current.inline = inline
        current.plain:SetShown(not inline)
        current.inset:SetShown(inline)
        current.scroll:SetShown(inline)
        if inline then
            splitNotes(current, text, current.position)
            layout(current)
        else setText(current.plain, text) end
    end)
    current.rendering = false
    if not ok then current.geometryReady, current.layoutWidth = false, nil; error(failure, 0) end
    for _, field in ipairs({ current.plain, current.before, current.after }) do noteAppearance(field) end
    if current.inline then setScroll(current, current.scroll:GetVerticalScroll()) end
    rowFeedback(current)
end
editor.Refresh = refresh

local function install()
    if state then return true end
    local original = _G.TRP3_RegisterMiscViewCurrentlyIC
    if not original or not original.GetInputText or not original.TriggerEvent or not original.GetParent then return false end
    local frame = CreateFrame("Frame", nil, original:GetParent())
    buildingFrame = frame
    frame:SetAllPoints(original)
    frame:SetFrameLevel(original:GetFrameLevel())
    local current = { frame = frame, original = original, readOnly = original:IsReadOnly(),
        editSerial = 0, position = "bottom", lines = {}, keys = {}, rows = {} }
    current.plain = CreateFrame("Frame", nil, frame, "TRP3_InsetScrollingEditBoxTemplate")
    current.plain:SetAllPoints(frame)
    current.inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    current.inset:SetAllPoints(frame)
     
    current.inset:SetFrameLevel(frame:GetFrameLevel())
    current.scroll = CreateFrame("ScrollFrame", nil, current.inset)
    current.scroll:SetFrameLevel(current.inset:GetFrameLevel() + 1)
    current.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    current.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 4)
    current.scroll:SetClipsChildren(true)
    current.content = CreateFrame("Frame", nil, current.scroll)
    current.content:SetPoint("TOPLEFT", current.scroll, "TOPLEFT", 0, 0)
    current.scroll:SetScrollChild(current.content)
    current.before = CreateFrame("Frame", nil, current.content, "TRP3_ScrollingEditBoxTemplate")
    current.after = CreateFrame("Frame", nil, current.content, "TRP3_ScrollingEditBoxTemplate")
    for _, field in ipairs({ current.before, current.after }) do
         
        field.ScrollFrame:ClearAllPoints()
        field.ScrollFrame:SetAllPoints(field)
        field.ScrollBox:ClearAllPoints()
        field.ScrollBox:SetAllPoints(field.ScrollFrame)
        field:SetClipsChildren(true)
    end
    current.measure = current.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    current.measure:SetAlpha(0)
    local originalBox = original:GetEditBox()
    local native = _G.TRP3_RegisterMiscViewCurrentlyOOC
    current.fontSource = native and native.GetEditBox and native:GetEditBox() or originalBox
    local font = current.fontSource:GetFontObject()
    copyNativeFont(current.measure, current.fontSource)
    current.measure:SetJustifyH("LEFT")
    current.block = CreateFrame("Button", nil, current.content)
    current.block.background = current.block:CreateTexture(nil, "BACKGROUND")
    current.block.background:SetAllPoints(current.block)
    current.block.background:SetColorTexture(0.29, 0.30, 0.32, 0.48)
    current.block:RegisterForDrag("LeftButton")
    current.block:SetScript("OnDragStart", safe(function() beginDrag(current, "block") end))
    current.block:SetScript("OnDragStop", safe(function() finishDrag(current) end))
    current.grip = CreateFrame("Button", nil, current.block)
    current.grip:SetPoint("TOPLEFT", current.block, "TOPLEFT", 0, 0)
    current.grip:SetPoint("TOPRIGHT", current.block, "TOPRIGHT", 0, 0)
    current.grip:SetHeight(10)
    current.grip:RegisterForDrag("LeftButton")
    current.grip:SetScript("OnDragStart", safe(function() beginDrag(current, "block") end))
    current.grip:SetScript("OnDragStop", safe(function() finishDrag(current) end))
    current.grip:SetScript("OnEnter", function(self)
        current.block.background:SetColorTexture(0.33, 0.34, 0.36, 0.62)
        tooltip(current, self, "CURRENTLY_EDITOR_DRAG")
    end)
    current.grip:SetScript("OnLeave", function()
        current.block.background:SetColorTexture(0.29, 0.30, 0.32, 0.48); GameTooltip:Hide()
    end)
    for index = 1, 5 do
        local dot = current.grip:CreateTexture(nil, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetPoint("CENTER", current.grip, "CENTER", (index - 3) * 4, 0)
        dot:SetColorTexture(0.64, 0.66, 0.69, 0.65)
    end
    current.indicator = CreateFrame("Frame", nil, current.content)
    current.indicator:SetHeight(3)
    current.indicator:SetFrameLevel(current.block:GetFrameLevel() + 3)
    current.indicator:EnableMouse(false)
    local marker = current.indicator:CreateTexture(nil, "OVERLAY")
    marker:SetAllPoints(current.indicator)
    marker:SetColorTexture(0.73, 0.85, 0.91, 0.95)
    current.indicator:Hide()
    current.ghost = CreateFrame("Frame", nil, current.scroll)
    current.ghost:SetFrameLevel(current.scroll:GetFrameLevel() + 20)
    local shade = current.ghost:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(current.ghost); shade:SetColorTexture(0.25, 0.27, 0.29, 0.9)
    current.ghostLabel = current.ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    current.ghostLabel:SetPoint("TOPLEFT", current.ghost, "TOPLEFT", 6, -6)
    current.ghostLabel:SetPoint("BOTTOMRIGHT", current.ghost, "BOTTOMRIGHT", -6, 6)
    current.ghostLabel:SetJustifyH("LEFT"); current.ghostLabel:SetJustifyV("TOP")
    current.ghostLabel:SetTextColor(0.74, 0.76, 0.78)
    current.ghost:Hide()
    frame.EffectsBlock, frame.BeforeNotes, frame.AfterNotes = current.block, current.before, current.after
    frame.Notes, frame.documentScroll = current.plain, current.scroll
    frame.DropIndicator = current.indicator

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, 10)
    frame.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, 10)
    frame.Title:SetText(original.Title and original.Title:GetText() or addon.L("CURRENTLY_EDITOR_TITLE"))
    frame.Title:SetTextColor(0.95, 0.75, 0.1)
    frame.HelpButton = CreateFrame("Button", nil, frame, "TRP3_HelpButton")
    frame.HelpButton:SetSize(14, 14); frame.HelpButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 13)
    if original.HelpButton then
        for _, script in ipairs({ "OnEnter", "OnLeave", "OnClick" }) do frame.HelpButton:SetScript(script, original.HelpButton:GetScript(script)) end
    end
    local function restoreMenu(_, button)
        if button ~= "RightButton" or current.readOnly then return end
        local view = model()
        local menu = _G.TRP3_MenuUtil or _G.MenuUtil
        if not view or not view.enabled or view.suppressedCount == 0
            or not menu or type(menu.CreateContextMenu) ~= "function" then return end
        menu.CreateContextMenu(frame, function(_, root)
            root:CreateButton(addon.L("CURRENTLY_EDITOR_RESTORE"), function()
                if not current.readOnly and current.profileID == view.profileID then
                    addon.CurrentlyEffects.RestorePublication(view.profileID); refresh()
                end
            end)
        end)
    end
    for _, field in ipairs({ current.plain, current.before, current.after }) do
        field.nativeFontSource = current.fontSource
        field.EditBox.fontName = font
        field:SetFontObject(font)
        noteAppearance(field)
        local restoreAppearance = function() noteAppearance(field) end
        field.ScrollFrame:HookScript("OnShow", restoreAppearance)
        field.EditBox:HookScript("OnShow", restoreAppearance)
        field.EditBox:HookScript("OnTextChanged", restoreAppearance)
        field:SetEscapeSanitized(original.escapeSanitized)
        field:SetHighlightOnFocus(original.highlightOnFocus)
        field:RegisterCallback("OnTextChanged", safe(function(_, userInput) changed(current, userInput) end))
        field.EditBox:HookScript("OnMouseUp", safe(restoreMenu))
        field.FocusCapture:HookScript("OnMouseUp", safe(restoreMenu))
        local function clearSelection()
            current.selectedKey, current.hoverKey = nil, nil
            rowFeedback(current)
        end
        field.EditBox:HookScript("OnMouseDown", clearSelection)
        field.FocusCapture:HookScript("OnMouseDown", clearSelection)
        for _, event in ipairs({ "OnCursorChanged", "OnEditFocusGained", "OnEditFocusLost", "OnEscapePressed", "OnTabPressed" }) do
            field:RegisterCallback(event, safe(function(_, ...)
                if event == "OnCursorChanged" and current.inline and current.geometryReady
                    and not current.rendering and not current.layingOut and type(field.documentY) == "number" then
                    local _, y, _, height = ...
                    if type(y) == "number" and type(height) == "number" then
                        local top = field.documentY + math.abs(y)
                        local offset = current.scroll:GetVerticalScroll()
                        if top < offset then setScroll(current, top)
                        elseif top + height > offset + current.scroll:GetHeight() then
                            setScroll(current, top + height - current.scroll:GetHeight())
                        end
                    end
                end
                if event == "OnEditFocusLost" and current.dirty and not current.drag then commit(current, current.profileID); refresh() end
                if event == "OnEscapePressed" then cancelDrag(current) end
                current.original:TriggerEvent(event, ...)
            end))
        end
        if field ~= current.plain then
            local wheel = function(_, delta) setScroll(current, current.scroll:GetVerticalScroll() - delta * 28) end
            field:EnableMouseWheel(true)
            field:SetScript("OnMouseWheel", wheel)
            field:GetScrollBox():HookScript("OnMouseWheel", wheel)
        end
    end
    current.scroll:EnableMouseWheel(true)
    current.scroll:SetScript("OnMouseWheel", function(_, delta) setScroll(current, current.scroll:GetVerticalScroll() - delta * 28) end)
    current.scroll:HookScript("OnVerticalScroll", safe(function() hitBounds(current) end))
    frame:SetScript("OnKeyDown", function(_, key)
        frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then cancelDrag(current) end
    end)
    frame:EnableKeyboard(false)
    for _, name in ipairs({ "ClearText", "SetDefaultText", "SetDefaultTextColor", "SetDefaultTextEnabled",
        "SetFontObject", "SetTextColor", "SetEscapeSanitized", "SetHighlightOnFocus", "SetEnabled" }) do
        frame[name] = function(_, ...)
            for _, field in ipairs({ current.plain, current.before, current.after }) do field[name](field, ...) end
            if name == "SetFontObject" then
                current.measure:SetFontObject(...)
                for _, field in ipairs({ current.plain, current.before, current.after }) do field.EditBox.fontName = ... end
                for _, row in ipairs(current.rows) do row.label:SetFontObject(...) end
            end
            current.layoutWidth = nil
        end
    end
    for _, name in ipairs({ "RegisterCallback", "UnregisterCallback", "TriggerEvent" }) do
        frame[name] = function(_, ...) return original[name](original, ...) end
    end
    function frame:GetEditBox() return (current.inline and current.after or current.plain):GetEditBox() end
    function frame:GetScrollBox() return current.inline and current.scroll or current.plain:GetScrollBox() end
    function frame:GetFontHeight() return current.plain:GetFontHeight() end
    function frame:SetFocus() (current.inline and current.after or current.plain):SetFocus() end
    function frame:ClearFocus() current.plain:ClearFocus(); current.before:ClearFocus(); current.after:ClearFocus() end
    function frame:IsReadOnly() return current.readOnly end
    function frame:SetReadOnly(value)
        local view = not value and model() or nil
        local keep = current.dirty and view and view.profileID == current.profileID
        current.readOnly = value == true
        if current.readOnly then current.selectedKey, current.hoverKey = nil, nil end
        if current.readOnly or (view and view.profileID ~= current.profileID) then cancelDrag(current) end
        for _, field in ipairs({ current.plain, current.before, current.after }) do field:SetReadOnly(current.readOnly) end
        if not keep then current.editSerial, current.dirty = current.editSerial + 1, false end
        refresh()
    end
    function frame:SetText(text)
        local view = not current.readOnly and model() or nil
        if current.dirty and view and view.profileID == current.profileID then refresh(); return end
        current.dirty, current.editSerial = false, current.editSerial + 1
        current.personalText = view and view.publishedText == text and view.personalText or text or ""
        refresh()
    end
    function frame:GetInputText()
        local text = personal(current)
        if current.readOnly then return text end
        local view = model()
        if not view then return text end
        if current.profileID ~= view.profileID then return view.publishedText end
        return addon.CurrentlyEffects.ComposePersonalText(text, position(current), view.profileID, current.keys) or view.publishedText
    end
    frame:HookScript("OnSizeChanged", safe(function()
        current.layoutWidth = nil
        if current.inline then layout(current) end
    end))
    frame:HookScript("OnHide", safe(function()
        cancelDrag(current)
        if current.dirty then commit(current, current.profileID) end
        current.editSerial = current.editSerial + 1
    end))
    state = current
    local text = original:GetInputText()
    _G.TRP3_RegisterMiscViewCurrentlyIC = frame
    original:Hide(); frame:SetText(text); frame:Show()
    buildingFrame = nil
    return true
end

function editor.Install()
    if state then return true end
    if failedInstall then return false end
    local ok, installed = pcall(install)
    if not ok then
        failedInstall = true
        if state then
            _G.TRP3_RegisterMiscViewCurrentlyIC = state.original
            state.original:Show(); state = nil
        end
        if buildingFrame then buildingFrame:Hide(); buildingFrame = nil end
        if addon.Logger then addon.Logger.Error(tostring(installed)) end
        return false
    end
    return installed
end
function editor.Initialize()
    if initialized then return end
    initialized = true
    local update = safe(function() if editor.Install() then refresh() end end)
    addon.TimedEffects.RegisterListener(update)
    addon.GameMasterService.RegisterListener(update)
    addon.SpellCreationSettings.RegisterListener(update)
    local api = _G.TRP3_API
    if api and api.RegisterCallback and _G.TRP3_Addon then
        for _, event in ipairs({ "WORKFLOW_ON_LOADED", "REGISTER_PROFILES_LOADED", "REGISTER_DATA_UPDATED" }) do
            api.RegisterCallback(TRP3_Addon, event, update)
        end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, update) end
    update()
end
