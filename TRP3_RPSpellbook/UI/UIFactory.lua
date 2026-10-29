local _, addon = ...

addon.UIFactory = {}

local dialogOrder = 0
local dialogs = setmetatable({}, { __mode = "k" })
local spellIconEffectFrames = setmetatable({}, { __mode = "k" })
local FANCY_BOOK_FONT = "Fonts\\MORPHEUS.TTF"

function addon.UIFactory.GetTutorialWindows()
    local result = {}
    for frame in pairs(dialogs) do
        if frame:IsVisible() then result[#result + 1] = frame end
    end
    return result
end

local function unpackColor(color)
    return color[1], color[2], color[3], color[4]
end

function addon.UIFactory.CreateBackdropFrame(parent, backgroundColor, borderColor)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpackColor(backgroundColor))
    frame:SetBackdropBorderColor(unpackColor(borderColor))
    return frame
end

function addon.UIFactory.CreateLabel(parent, fontObject, text, color)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject)
    label:SetText(text or "")
    if color then
        label:SetTextColor(unpackColor(color))
    end
    return label
end

function addon.UIFactory.ApplyBookFont(region, fancy, sizeOffset)
    if not region or type(region.GetFont) ~= "function"
        or type(region.SetFont) ~= "function"
    then
        return false
    end
    local original = region.spellbookOriginalFont
    if not original then
        local success, path, size, flags = pcall(region.GetFont, region)
        if not success or type(path) ~= "string" or not tonumber(size) then
            return false
        end
        original = {
            path = path,
            size = size,
            flags = flags or "",
        }
        region.spellbookOriginalFont = original
    end
    local path = fancy and FANCY_BOOK_FONT or original.path
    local size = fancy
        and math.max(8, original.size + (tonumber(sizeOffset) or 0))
        or original.size
    local flags = fancy and "" or original.flags
    return pcall(region.SetFont, region, path, size, flags)
end

function addon.UIFactory.ApplyBookFieldStyle(field, fancy)
    if not field then
        return false
    end
    local visual = field.spellbookBookFieldVisual
    if not visual then
        visual = { nativeTextures = {} }
        if type(field.GetRegions) == "function" then
            for _, region in ipairs({ field:GetRegions() }) do
                if region and type(region.IsObjectType) == "function" then
                    local success, isTexture = pcall(
                        region.IsObjectType, region, "Texture"
                    )
                    if success and isTexture then
                        visual.nativeTextures[#visual.nativeTextures + 1] = {
                            alpha = type(region.GetAlpha) == "function"
                                and region:GetAlpha() or 1,
                            texture = region,
                        }
                    end
                end
            end
        end
        if type(field.GetTextColor) == "function" then
            visual.textColor = { field:GetTextColor() }
        end
        local placeholder = field.placeholder
        if placeholder and type(placeholder.GetTextColor) == "function" then
            visual.placeholderColor = { placeholder:GetTextColor() }
        end
        if type(field.CreateTexture) == "function" then
            visual.underline = field:CreateTexture(nil, "BORDER")
            visual.underline:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", 2, 0)
            visual.underline:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -2, 0)
            visual.underline:SetHeight(1)
            visual.underline:SetColorTexture(0.22, 0.12, 0.05, 0.44)
        end
        field.spellbookBookFieldVisual = visual
    end

    for _, native in ipairs(visual.nativeTextures) do
        if type(native.texture.SetAlpha) == "function" then
            native.texture:SetAlpha(fancy and 0 or native.alpha)
        end
    end
    if visual.underline and type(visual.underline.SetShown) == "function" then
        visual.underline:SetShown(fancy)
    elseif visual.underline and fancy and type(visual.underline.Show) == "function" then
        visual.underline:Show()
    elseif visual.underline and type(visual.underline.Hide) == "function" then
        visual.underline:Hide()
    end
    if type(field.SetTextColor) == "function" then
        if fancy then
            field:SetTextColor(0.10, 0.045, 0.015, 1)
        elseif visual.textColor then
            field:SetTextColor(unpackColor(visual.textColor))
        end
    end
    local placeholder = field.placeholder
    if placeholder and type(placeholder.SetTextColor) == "function" then
        if fancy then
            placeholder:SetTextColor(0.18, 0.09, 0.035, 0.88)
        elseif visual.placeholderColor then
            placeholder:SetTextColor(unpackColor(visual.placeholderColor))
        end
    end
    return true
end

function addon.UIFactory.CreateButton(parent, text, width)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, theme.Sizes.buttonHeight)
    button:SetText(text)
    return button
end

function addon.UIFactory.CreateTextureButton(parent, texturePath, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local normal = button:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    normal:SetTexture(texturePath)
    button:SetNormalTexture(normal)

    local pushed = button:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetTexture(texturePath)
    pushed:SetVertexColor(0.72, 0.72, 0.72, 1)
    button:SetPushedTexture(pushed)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(texturePath)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.45)
    button:SetHighlightTexture(highlight)
    return button
end

function addon.UIFactory.ConfigureGuardedClose(frame, shouldGuard)
    if not frame or not frame.closeButton then
        return false
    end
    local closeButton = frame.closeButton
    closeButton:SetScript("OnClick", function()
        local guarded = type(shouldGuard) == "function"
            and shouldGuard() == true
        if not guarded then
            frame:Hide()
            return
        end

        local now = addon.Runtime.GetMonotonicTime()
        if frame.closeGuardUntil and now <= frame.closeGuardUntil then
            frame.closeGuardUntil = nil
            GameTooltip:Hide()
            frame:Hide()
            return
        end

        frame.closeGuardUntil = now + 2
        GameTooltip:SetOwner(closeButton, "ANCHOR_BOTTOM")
        GameTooltip:SetText(addon.L("WINDOW_CLOSE_CONFIRM_HINT"))
        GameTooltip:Show()
    end)
    closeButton:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:HookScript("OnHide", function()
        frame.closeGuardUntil = nil
        GameTooltip:Hide()
    end)
    return true
end

local function setTextureAlpha(texture, alpha)
    if texture and type(texture.SetAlpha) == "function" then
        texture:SetAlpha(alpha)
    end
end

local function updateMinimalButtonVisual(button)
    local visual = button and button.spellbookMinimalVisual
    if not visual or not visual.active then
        return
    end

    local style = visual.style
    local background = style.buttonBackground
    if type(button.IsEnabled) == "function" and not button:IsEnabled() then
        background = style.buttonBackgroundDisabled
    elseif visual.pressed then
        background = style.buttonBackgroundPressed
    elseif type(button.IsMouseOver) == "function" and button:IsMouseOver() then
        background = style.buttonBackgroundHover
    end
    visual.background:SetColorTexture(unpackColor(background))
end

local function createMinimalButtonVisual(button)
    local visual = { nativeTextures = {} }
    local captured = {}
    local function capture(texture)
        if not texture or captured[texture] then
            return
        end
        captured[texture] = true
        visual.nativeTextures[#visual.nativeTextures + 1] = {
            alpha = type(texture.GetAlpha) == "function"
                and texture:GetAlpha()
                or 1,
            texture = texture,
        }
    end
    local function captureFrameTextures(frame, depth)
        if type(frame.GetRegions) == "function" then
            for _, region in ipairs({ frame:GetRegions() }) do
                if type(region.IsObjectType) == "function"
                    and region:IsObjectType("Texture")
                then
                    capture(region)
                end
            end
        end
        if depth < 3 and type(frame.GetChildren) == "function" then
            for _, child in ipairs({ frame:GetChildren() }) do
                captureFrameTextures(child, depth + 1)
            end
        end
    end
    captureFrameTextures(button, 0)
    capture(button:GetNormalTexture())
    capture(button:GetPushedTexture())
    capture(button:GetDisabledTexture())
    capture(button:GetHighlightTexture())

    visual.background = button:CreateTexture(nil, "BACKGROUND")
    visual.background:SetAllPoints()
    visual.background:Hide()

    visual.border = {}
    for index = 1, 4 do
        local line = button:CreateTexture(nil, "BORDER")
        visual.border[index] = line
        line:Hide()
    end
    visual.border[1]:SetPoint("TOPLEFT")
    visual.border[1]:SetPoint("TOPRIGHT")
    visual.border[1]:SetHeight(1)
    visual.border[2]:SetPoint("BOTTOMLEFT")
    visual.border[2]:SetPoint("BOTTOMRIGHT")
    visual.border[2]:SetHeight(1)
    visual.border[3]:SetPoint("TOPLEFT")
    visual.border[3]:SetPoint("BOTTOMLEFT")
    visual.border[3]:SetWidth(1)
    visual.border[4]:SetPoint("TOPRIGHT")
    visual.border[4]:SetPoint("BOTTOMRIGHT")
    visual.border[4]:SetWidth(1)

    local fontString = type(button.GetFontString) == "function"
        and button:GetFontString()
        or nil
    if fontString and type(fontString.GetTextColor) == "function" then
        visual.fontString = fontString
        visual.textColor = { fontString:GetTextColor() }
    end

    button.spellbookMinimalVisual = visual
    button:HookScript("OnEnter", updateMinimalButtonVisual)
    button:HookScript("OnLeave", updateMinimalButtonVisual)
    button:HookScript("OnEnable", updateMinimalButtonVisual)
    button:HookScript("OnDisable", updateMinimalButtonVisual)
    button:HookScript("OnMouseDown", function(self)
        local current = self.spellbookMinimalVisual
        if current then
            current.pressed = true
            updateMinimalButtonVisual(self)
        end
    end)
    button:HookScript("OnMouseUp", function(self)
        local current = self.spellbookMinimalVisual
        if current then
            current.pressed = false
            updateMinimalButtonVisual(self)
        end
    end)
    return visual
end

function addon.UIFactory.ApplyButtonStyle(button, styleName, glyph)
    if not button then
        return
    end
    local visual = button.spellbookMinimalVisual
        or createMinimalButtonVisual(button)
    local minimal = styleName == "minimal"
    local custom = minimal or styleName == "book" or glyph == nil
    visual.active = custom
    visual.style = addon.Theme.GetGameMasterStyle(styleName)

    for _, native in ipairs(visual.nativeTextures) do
        setTextureAlpha(
            native.texture,
            custom and 0 or native.alpha
        )
    end
    visual.background:SetShown(custom)
    for _, line in ipairs(visual.border) do
        line:SetShown(custom)
        if custom then
            line:SetColorTexture(unpackColor(visual.style.buttonBorder))
        end
    end

    if glyph and not visual.glyph then
        visual.glyph = addon.UIFactory.CreateLabel(
            button,
            addon.Theme.Fonts.body,
            glyph,
            visual.style.buttonText
        )
        visual.glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    if visual.glyph then
        visual.glyph:SetText(glyph or "")
        visual.glyph:SetShown(minimal)
        visual.glyph:SetTextColor(unpackColor(visual.style.buttonText))
    end
    if visual.fontString then
        if custom then
            visual.fontString:SetTextColor(unpackColor(visual.style.buttonText))
        elseif visual.textColor then
            visual.fontString:SetTextColor(unpackColor(visual.textColor))
        end
    end
    if custom then
        updateMinimalButtonVisual(button)
    end
end

function addon.UIFactory.BringToFront(frame)
    if not frame then
        return
    end
    dialogOrder = dialogOrder + 1
    frame.spellbookDialogOrder = dialogOrder

    local visible = {}
    for dialog in pairs(dialogs) do
        if dialog:IsShown() then
            visible[#visible + 1] = dialog
        end
    end
    table.sort(visible, function(left, right)
        return (left.spellbookDialogOrder or 0)
            < (right.spellbookDialogOrder or 0)
    end)
    for index, dialog in ipairs(visible) do
        dialog:SetFrameLevel(100 + (index * 50))
    end
    if type(frame.Raise) == "function" then
        frame:Raise()
    end
end

function addon.UIFactory.ConfigureInformationWindow(frame)
    if not frame then
        return false
    end
    frame:SetFrameStrata("LOW")
    if type(frame.SetFixedFrameStrata) == "function" then
        frame:SetFixedFrameStrata(true)
    end
    return true
end

function addon.UIFactory.CreateWindowMinimizeButton(frame, callback)
    if not frame or not frame.closeButton then
        return nil
    end
    frame.closeButton:Hide()
    if type(frame.closeButton.EnableMouse) == "function" then
        frame.closeButton:EnableMouse(false)
    end

    local button = addon.UIFactory.CreateButton(frame, "-", 30)
    button:SetHeight(22)
    button:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -addon.Theme.Spacing.xs,
        -addon.Theme.Spacing.xs
    )
    button:SetScript("OnClick", function()
        if type(callback) == "function" then callback() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.L(
            self.windowMinimized and "WINDOW_RESTORE" or "WINDOW_MINIMIZE"
        ))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.minimizeButton = button
    return button
end

function addon.UIFactory.SetWindowMinimizeState(button, minimized)
    if not button then return end
    button.windowMinimized = minimized == true
    button:SetText(button.windowMinimized and "+" or "-")
end

local function configureEditFont(editBox)
    editBox:SetFontObject(addon.Theme.Fonts.body)
     
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetShadowColor(0, 0, 0, 1)
    editBox:SetShadowOffset(1, -1)
    editBox:SetBlinkSpeed(0.5)
end

function addon.UIFactory.CreateSearchBox(parent, placeholderKey)
    local theme = addon.Theme
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    configureEditFont(editBox)
    editBox:SetHeight(theme.Sizes.inputHeight)
    editBox:SetTextInsets(theme.Spacing.sm, theme.Spacing.sm, 0, 0)

    local placeholder = addon.UIFactory.CreateLabel(editBox, theme.Fonts.body, addon.L(placeholderKey or "SEARCH_PLACEHOLDER"), theme.Colors.textMuted)
    placeholder:SetPoint("LEFT", editBox, "LEFT", theme.Spacing.sm, 0)
    editBox.placeholder = placeholder

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    return editBox
end

function addon.UIFactory.CreateEditBox(parent, multiline)
    local theme = addon.Theme
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    configureEditFont(editBox)
    editBox:SetHeight(multiline and theme.Sizes.editorTextAreaHeight or theme.Sizes.inputHeight)
    editBox:SetTextInsets(theme.Spacing.sm, theme.Spacing.sm, theme.Spacing.xs, theme.Spacing.xs)
    if multiline then
        editBox:SetMultiLine(true)
        editBox:SetJustifyH("LEFT")
        editBox:SetJustifyV("TOP")
    end
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return editBox
end

function addon.UIFactory.CreateTextArea(parent)
    local theme = addon.Theme
    local container = addon.UIFactory.CreateBackdropFrame(parent, theme.Colors.dark, theme.Colors.border)
    container:SetHeight(theme.Sizes.editorTextAreaHeight)
    container:SetClipsChildren(true)

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", theme.Spacing.sm, -theme.Spacing.sm)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -theme.Spacing.xl, theme.Spacing.sm)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    configureEditFont(editBox)
    editBox:SetMultiLine(true)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    editBox:SetSize(1, 1)
    scrollFrame:SetScrollChild(editBox)

    local function updateMouseBounds()
        if type(editBox.SetHitRectInsets) ~= "function" then
            return
        end
        local height = math.max(1, editBox:GetHeight())
        local viewportHeight = math.max(1, scrollFrame:GetHeight())
        local offset = math.max(0, math.min(scrollFrame:GetVerticalScroll(), height - viewportHeight))
        local hiddenBelow = math.max(0, height - offset - viewportHeight)
        editBox:SetHitRectInsets(0, 0, offset, hiddenBelow)
    end

    local function updateSize()
        local width = math.max(1, scrollFrame:GetWidth())
        editBox:SetWidth(width)
        local _, fontHeight = editBox:GetFont()
        local lineHeight = fontHeight + editBox:GetSpacing()
        editBox:SetHeight(math.max(scrollFrame:GetHeight(),
            math.max(1, editBox:GetNumLines()) * lineHeight + theme.Spacing.md))
        scrollFrame:UpdateScrollChildRect()
        updateMouseBounds()
    end
    local cursorPosition, cursorText = nil, editBox:GetText()
    editBox:HookScript("OnCursorChanged", function(self, x, y, width, height)
        local position = self:GetCursorPosition()
        if position == cursorPosition then
            return
        end
        cursorPosition = position
        local top = math.max(0, -y)
        local bottom = top + height
        local viewport = math.max(1, scrollFrame:GetHeight())
        self:SetHeight(math.max(self:GetHeight(), bottom + theme.Spacing.xs))
        scrollFrame:UpdateScrollChildRect()
        local offset = scrollFrame:GetVerticalScroll()
        if top < offset then
            scrollFrame:SetVerticalScroll(top)
        elseif bottom > offset + viewport then
            scrollFrame:SetVerticalScroll(math.max(0, bottom - viewport))
        end
        updateMouseBounds()
    end)
    container:SetScript("OnSizeChanged", updateSize)
    editBox:SetScript("OnTextChanged", updateSize)
    editBox:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text ~= cursorText then
            cursorPosition = nil
            cursorText = text
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:HookScript("OnVerticalScroll", updateMouseBounds)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - (delta * theme.Sizes.inputHeight)
        self:SetVerticalScroll(math.max(0, math.min(target, self:GetVerticalScrollRange())))
    end)

    editBox.textAreaContainer = container
    editBox.scrollFrame = scrollFrame
    return editBox, container
end
function addon.UIFactory.CreateIconButton(parent)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(theme.Sizes.editorIcon, theme.Sizes.editorIcon)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(unpackColor(theme.Colors.parchmentDark))
    button:SetBackdropBorderColor(unpackColor(theme.Colors.gold))

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", theme.Spacing.xs, -theme.Spacing.xs)
    texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -theme.Spacing.xs, theme.Spacing.xs)
    button.iconTexture = texture
    return button
end

function addon.UIFactory.SetIconTexture(texture, icon, fallbackIcon)
    local selectedIcon = icon
    if selectedIcon == nil or selectedIcon == "" then
        selectedIcon = fallbackIcon
    end

    local success = addon.TRP3Bridge.SetIconTexture(texture, selectedIcon)
    if not success then
        addon.TRP3Bridge.SetIconTexture(texture, fallbackIcon)
    end
end

local function hideEffectSegments(frame)
    for _, segment in ipairs(frame.segments) do
        segment:Hide()
        segment:ClearAllPoints()
    end
    frame:Hide()
end

local function getEffectFrame(icon)
    local frame = spellIconEffectFrames[icon]
    if frame then return frame end
    if not icon or type(icon.GetParent) ~= "function" then return nil end
    local parent = icon:GetParent()
    if not parent then return nil end
    frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(icon)
    frame:EnableMouse(false)
    if type(frame.SetClipsChildren) == "function" then
        frame:SetClipsChildren(true)
    end
    if type(parent.GetFrameLevel) == "function"
        and type(frame.SetFrameLevel) == "function"
    then
        frame:SetFrameLevel(parent:GetFrameLevel() + 8)
    end
    frame.segments = {}
    for index = 1, 12 do
        frame.segments[index] = frame:CreateTexture(nil, "OVERLAY")
    end
    spellIconEffectFrames[icon] = frame
    return frame
end

local function colorSegment(segment, color)
    segment:SetColorTexture(addon.UIFactory.GetColorRGB(color))
    segment:Show()
end

local function setSolidEffectFrame(frame, color, thickness)
    local top, right, bottom, left = frame.segments[1], frame.segments[2],
        frame.segments[3], frame.segments[4]
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)
    for index = 1, 4 do colorSegment(frame.segments[index], color) end
end

local function setElementalEffectFrame(frame, colors, thickness, width, height)
    local horizontal = math.max(1, width / 3)
    local vertical = math.max(1, height / 3)
    for index = 1, 3 do
        local top = frame.segments[index]
        top:SetPoint("TOPLEFT", frame, "TOPLEFT", (index - 1) * horizontal, 0)
        top:SetSize(index == 3 and math.max(1, width - horizontal * 2) or horizontal, thickness)
        colorSegment(top, colors[index])

        local bottom = frame.segments[index + 3]
        bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (index - 1) * horizontal, 0)
        bottom:SetSize(index == 3 and math.max(1, width - horizontal * 2) or horizontal, thickness)
        colorSegment(bottom, colors[index])

        local left = frame.segments[index + 6]
        left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -((index - 1) * vertical))
        left:SetSize(thickness, index == 3 and math.max(1, height - vertical * 2) or vertical)
        colorSegment(left, colors[index])

        local right = frame.segments[index + 9]
        right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -((index - 1) * vertical))
        right:SetSize(thickness, index == 3 and math.max(1, height - vertical * 2) or vertical)
        colorSegment(right, colors[index])
    end
end

function addon.UIFactory.ClearSpellIconEffectFrame(icon)
    local frame = icon and spellIconEffectFrames[icon]
    if frame then
        hideEffectSegments(frame)
        frame.presentation, frame.referenceScale = nil, nil
    end
end

local function paintEffectFrame(icon, frame, colors, thickness)
    hideEffectSegments(frame)
    frame:ClearAllPoints()
    frame:SetAllPoints(icon)
    frame:SetAlpha(1)
    if #colors == 3 then
        local width = type(icon.GetWidth) == "function" and tonumber(icon:GetWidth()) or nil
        local height = type(icon.GetHeight) == "function" and tonumber(icon:GetHeight()) or nil
        if width and width > 0 and height and height > 0 then
            setElementalEffectFrame(frame, colors, thickness, width, height)
        else
            setSolidEffectFrame(frame, "0070DD", thickness)
        end
    else
        setSolidEffectFrame(frame, colors[1], thickness)
    end
    frame:Show()
end

local function effectScale(icon)
    local scale = icon.GetEffectiveScale and icon:GetEffectiveScale() or 1
    return type(scale) == "number" and scale > 0 and scale < math.huge and scale or 1
end

 
 
function addon.UIFactory.RefreshSpellIconEffectFrame(icon, referenceScale)
    local frame = icon and spellIconEffectFrames[icon]
    if not frame or not frame.presentation then return false end
    if referenceScale ~= nil then
        if type(referenceScale) ~= "number" or not (referenceScale > 0 and referenceScale < math.huge) then return false end
        frame.referenceScale = referenceScale
    end
    if not icon:IsShown() then hideEffectSegments(frame); return false end
    local presentation = frame.presentation
    local thickness = presentation.thickness
    if frame.referenceScale then thickness = thickness * frame.referenceScale / effectScale(icon) end
    paintEffectFrame(icon, frame, presentation.colors, thickness)
    return true
end

function addon.UIFactory.CopySpellIconEffectFrame(source, target)
    local original = source and spellIconEffectFrames[source]
    if not original or not original:IsShown() or not original.presentation then
        addon.UIFactory.ClearSpellIconEffectFrame(target)
        return false
    end
    local frame = getEffectFrame(target)
    if not frame then return false end
    local colors = {}
    for i, color in ipairs(original.presentation.colors) do colors[i] = color end
    frame.presentation = { colors = colors, thickness = original.presentation.thickness }
    frame.referenceScale = original.referenceScale or effectScale(source)
    frame:SetFrameLevel(target:GetParent():GetFrameLevel() + 1)
    return addon.UIFactory.RefreshSpellIconEffectFrame(target)
end

function addon.UIFactory.ApplySpellIconEffectFrame(icon, spell, visible)
    local presentation = addon.SpellPresentation.GetEffectPresentation(spell)
    local colors = presentation and presentation.colors or nil
    if not colors or #colors == 0 or visible == false
        or (visible == nil and type(icon.IsShown) == "function" and not icon:IsShown()) then
        addon.UIFactory.ClearSpellIconEffectFrame(icon)
        return false, presentation
    end
    local frame = getEffectFrame(icon)
    if not frame then return false, presentation end
    local copiedColors = {}
    for i, color in ipairs(colors) do copiedColors[i] = color end
    frame.presentation = { colors = copiedColors, thickness = presentation.thickness }
    frame.referenceScale = nil
    paintEffectFrame(icon, frame, colors, presentation.thickness)
    return true, presentation
end

function addon.UIFactory.SetSpellIcon(texture, spell, fallbackIcon, visible)
    addon.UIFactory.SetIconTexture(
        texture,
        type(spell) == "table" and spell.icon or nil,
        fallbackIcon
    )
    return addon.UIFactory.ApplySpellIconEffectFrame(texture, spell, visible)
end

 
 
function addon.UIFactory.SetNPCPortrait(owner, anchor, creatureID, icon, size)
    local composed = type(owner.AttachFrame) == "function"
    local model = not composed and owner.npcPortraitModel or nil
    local secret = type(issecretvalue) == "function" and issecretvalue(creatureID)
    local accessible = not secret and (type(canaccessvalue) ~= "function" or canaccessvalue(creatureID))
    local id = accessible and (type(creatureID) == "number" and creatureID
        or type(creatureID) == "string" and creatureID:match("^%d+$") and tonumber(creatureID)) or nil
    if (icon ~= nil and icon ~= "") or not id or id < 1 or id > 2147483647 or id ~= math.floor(id) then
        if model then
            model:Hide()
            if model.portraitCreatureID then pcall(model.ClearModel, model) end
            model.portraitCreatureID = nil
        end
        return false
    end
    if not model then
        local ok, created
        if composed then
             
             
            ok, created = pcall(owner.AttachFrame, owner, "PlayerModel")
        else
            ok, created = pcall(CreateFrame, "PlayerModel", nil, owner)
        end
        if not ok or not created then return false end
        model = created
        if not composed then owner.npcPortraitModel = model end
        model:Hide()
        if type(model.SetCreature) ~= "function" or type(model.ClearModel) ~= "function" then
            return false
        end
        model:EnableMouse(false)
        if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, not composed) end
        model:SetScript("OnModelLoaded", function(self)
            if not self.portraitCreatureID then return end
            if self.SetPortraitZoom then pcall(self.SetPortraitZoom, self, 1) end
            if self.FreezeAnimation then pcall(self.FreezeAnimation, self, 0, 0, 0) end
        end)
    end
    if type(model.SetCreature) ~= "function" or type(model.ClearModel) ~= "function" then return false end
    model:ClearAllPoints()
    if size == nil then
        model:SetAllPoints(anchor)
    else
        model:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        size = math.max(1, math.min(56, tonumber(size) or 16))
        model:SetSize(size, size)
    end
    if model.portraitCreatureID ~= id then
        model:ClearModel()
        model.portraitCreatureID = id
        local ok = pcall(model.SetCreature, model, id)
        model.portraitFailed = not ok
        if not ok then model:Hide(); return false end
        if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 1) end
    end
    if model.portraitFailed then return false end
    model:Show()
    return true
end

function addon.UIFactory.GetColorRGB(colorHex)
    local color = type(colorHex) == "string" and colorHex:gsub("#", "") or "FFFFFF"
    if not color:match("^%x%x%x%x%x%x$") then color = "FFFFFF" end
    return (tonumber(color:sub(1, 2), 16) or 255) / 255,
        (tonumber(color:sub(3, 4), 16) or 255) / 255,
        (tonumber(color:sub(5, 6), 16) or 255) / 255
end

function addon.UIFactory.SetFontColor(fontString, colorHex, fallbackColor)
    if colorHex then
        fontString:SetTextColor(addon.UIFactory.GetColorRGB(colorHex))
    elseif fallbackColor then
        fontString:SetTextColor(unpackColor(fallbackColor))
    else
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

function addon.UIFactory.CreateColorButton(parent)
    local theme = addon.Theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(theme.Sizes.inputHeight, theme.Sizes.inputHeight)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    button:SetBackdropBorderColor(unpackColor(theme.Colors.gold))
    button.colorTexture = button:CreateTexture(nil, "ARTWORK")
    button.colorTexture:SetPoint("TOPLEFT", button, "TOPLEFT", theme.Spacing.xs, -theme.Spacing.xs)
    button.colorTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -theme.Spacing.xs, theme.Spacing.xs)
    return button
end

function addon.UIFactory.SetColorButton(button, colorHex)
    button.colorTexture:SetColorTexture(addon.UIFactory.GetColorRGB(colorHex))
end
function addon.UIFactory.CreateDialog(titleText, width, height)
    local theme = addon.Theme
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    if type(frame.SetToplevel) == "function" then
        frame:SetToplevel(true)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    dialogs[frame] = true
    frame:HookScript("OnShow", function(self)
        addon.UIFactory.BringToFront(self)
    end)
    frame:HookScript("OnMouseDown", function(self)
        addon.UIFactory.BringToFront(self)
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpackColor(theme.Colors.dark))
    frame:SetBackdropBorderColor(unpackColor(theme.Colors.gold))

    local title = addon.UIFactory.CreateLabel(frame, theme.Fonts.header, titleText, theme.Colors.gold)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.md)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -theme.Spacing.xs, -theme.Spacing.xs)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.title = title
    frame.closeButton = closeButton
    frame:Hide()
    return frame
end

local confirmationDialog

local function cancelConfirmation()
    if not confirmationDialog then
        return
    end

    local onCancel = confirmationDialog.onCancel
    confirmationDialog.onCancel = nil
    confirmationDialog:Hide()
    if type(onCancel) == "function" then
        onCancel()
    end
end

function addon.UIFactory.ShowConfirmation(titleText, message, onConfirm, onCancel)
    local theme = addon.Theme
    if not confirmationDialog then
        confirmationDialog = addon.UIFactory.CreateDialog("", theme.Sizes.confirmationDialogWidth, theme.Sizes.confirmationDialogHeight)

        local messageLabel = addon.UIFactory.CreateLabel(confirmationDialog, theme.Fonts.body, "", theme.Colors.text)
        messageLabel:SetPoint("TOPLEFT", confirmationDialog, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.xl - theme.Spacing.lg)
        messageLabel:SetPoint("TOPRIGHT", confirmationDialog, "TOPRIGHT", -theme.Spacing.lg, -theme.Spacing.xl - theme.Spacing.lg)
        messageLabel:SetJustifyH("LEFT")
        messageLabel:SetJustifyV("TOP")
        messageLabel:SetWordWrap(true)

        local confirmButton = addon.UIFactory.CreateButton(confirmationDialog, addon.L("CONFIRM"), theme.Sizes.dialogButtonWidth)
        confirmButton:SetPoint("BOTTOMRIGHT", confirmationDialog, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)

        local cancelButton = addon.UIFactory.CreateButton(confirmationDialog, addon.L("CANCEL"), theme.Sizes.dialogButtonWidth)
        cancelButton:SetPoint("RIGHT", confirmButton, "LEFT", -theme.Spacing.sm, 0)
        cancelButton:SetScript("OnClick", cancelConfirmation)
        confirmationDialog.closeButton:SetScript("OnClick", cancelConfirmation)

        confirmationDialog.message = messageLabel
        confirmationDialog.confirmButton = confirmButton
    end

    confirmationDialog.title:SetText(titleText or addon.L("CONFIRM"))
    confirmationDialog.message:SetText(message or "")
    confirmationDialog.onCancel = onCancel
    confirmationDialog.confirmButton:SetScript("OnClick", function()
        confirmationDialog.onCancel = nil
        confirmationDialog:Hide()
        if type(onConfirm) == "function" then
            onConfirm()
        end
    end)
    confirmationDialog:Show()
    addon.UIFactory.BringToFront(confirmationDialog)
end
