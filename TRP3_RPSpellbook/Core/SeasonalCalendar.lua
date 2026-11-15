local _, addon = ...

addon.SeasonalCalendar = {}
local calendar = addon.SeasonalCalendar
local themeOrder = {
    "winterveil", "lunar", "love", "noblegarden", "children", "midsummer",
    "brewfest", "harvest", "hallowsend", "dayofthedead", "pilgrim",
}
local textures, textureNames = {}, {}
local function addTextures(theme, directory, entries)
    for id, name in pairs(entries) do
        textures[id] = theme
        textureNames[directory .. name] = theme
    end
end
local holidayDirectory = "interface/calendar/holidays/"
addTextures("winterveil", holidayDirectory, {
    [235482] = "calendar_winterveilend", [235483] = "calendar_winterveiliend",
    [235484] = "calendar_winterveilongoing", [235485] = "calendar_winterveilstart",
})
addTextures("lunar", holidayDirectory, {
    [235469] = "calendar_lunarfestivalend", [235470] = "calendar_lunarfestivalongoing",
    [235471] = "calendar_lunarfestivalstart",
})
addTextures("love", holidayDirectory, {
    [235466] = "calendar_loveintheairend", [235467] = "calendar_loveintheairongoing",
    [235468] = "calendar_loveintheairstart",
})
addTextures("noblegarden", holidayDirectory, {
    [235475] = "calendar_noblegardenend", [235476] = "calendar_noblegardenongoing",
    [235477] = "calendar_noblegardenstart",
})
addTextures("children", holidayDirectory, {
    [235443] = "calendar_childrensweekend", [235444] = "calendar_childrensweekongoing",
    [235445] = "calendar_childrensweekstart",
})
addTextures("midsummer", holidayDirectory, {
    [235472] = "calendar_midsummerend", [235473] = "calendar_midsummerongoing",
    [235474] = "calendar_midsummerstart",
})
addTextures("brewfest", holidayDirectory, {
    [235439] = "calendar_brewfest", [235440] = "calendar_brewfestend",
    [235441] = "calendar_brewfestongoing", [235442] = "calendar_brewfeststart",
})
addTextures("harvest", holidayDirectory, {
    [235463] = "calendar_harvestfestivalend", [235464] = "calendar_harvestfestivalongoing",
    [235465] = "calendar_harvestfestivalstart",
})
addTextures("hallowsend", holidayDirectory, {
    [235460] = "calendar_hallowsendend", [235461] = "calendar_hallowsendongoing",
    [235462] = "calendar_hallowsendstart",
})
addTextures("dayofthedead", holidayDirectory, {
    [307364] = "calendar_dayofthedeadend", [307365] = "calendar_dayofthedeadstart",
    [840588] = "calendar_dayofthedead", [840589] = "calendar_dayofthedeadongoing",
})
addTextures("pilgrim", "interface/icons/", {
    [236708] = "achievement_worldevent_thanksgiving", [237043] = "inv_holiday_thanksgiving_cornucopia",
})

local enabled, refreshing = false, false
local frame, retryTimer, boundaryTimer
local retries, generation = 0, 0
local retryDelays = { 1, 3, 10 }
local records, cachedDay, cachedAt
local active, listeners = {}, {}
local refresh

local function accessible(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(canaccessvalue, value)
        if not ok or not allowed then return false end
    end
    return true
end

local function field(object, key)
    if not accessible(object) then return nil end
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if not ok or not accessible(value) then return nil end
    return value
end

local function call(object, key, ...)
    local fn = field(object, key)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not accessible(value) then return nil end
    return value
end

local function integer(value, minimum, maximum)
    return accessible(value) and type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value == math.floor(value)
end

local monthDays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local function daysInMonth(year, month)
    if month == 2 and year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then return 29 end
    return monthDays[month]
end

local function dateValue(value)
    local year, month = field(value, "year"), field(value, "month")
    local day, hour, minute = field(value, "monthDay"), field(value, "hour"), field(value, "minute")
    if not integer(year, 1, 9999) or not integer(month, 1, 12)
        or not integer(day, 1, daysInMonth(year, month))
        or not integer(hour, 0, 23) or not integer(minute, 0, 59) then return nil end
    local previousYear = year - 1
    local days = previousYear * 365 + math.floor(previousYear / 4)
        - math.floor(previousYear / 100) + math.floor(previousYear / 400) + day - 1
    for index = 1, month - 1 do days = days + daysInMonth(year, index) end
    return days * 1440.0 + hour * 60 + minute, year, month, day
end

local function textureTheme(value)
    if integer(value, 1, 4294967295) then return textures[value] end
    if not accessible(value) or type(value) ~= "string" or #value > 160 then return nil end
    local name = value:lower():gsub("\\", "/"):gsub("%.blp$", "")
    return textureNames[name]
end

local function snapshot()
    local result = {}
    for index, theme in ipairs(active) do result[index] = theme end
    return result
end

local function publish(themes)
    local changed = #themes ~= #active
    for index, theme in ipairs(themes) do
        if active[index] ~= theme then changed = true end
    end
    if not changed then return end
    active = themes
    local callbacks, version = {}, generation
    for fn in pairs(listeners) do callbacks[#callbacks + 1] = fn end
    for _, fn in ipairs(callbacks) do
        if generation ~= version then break end
        if listeners[fn] then pcall(fn, snapshot()) end
    end
end

local function cancel(timer)
    local fn = field(timer, "Cancel")
    if type(fn) == "function" then pcall(fn, timer) end
end

local function newTimer(delay, callback)
    return call(C_Timer, "NewTimer", delay, callback)
end

local function readRecords(year, month, day)
    local viewed = call(C_Calendar, "GetMonthInfo", 0)
    local viewedYear, viewedMonth = field(viewed, "year"), field(viewed, "month")
    if not integer(viewedYear, 1, 9999) or not integer(viewedMonth, 1, 12) then return {}, true end
    local offset = (year - viewedYear) * 12 + month - viewedMonth
    local count = call(C_Calendar, "GetNumDayEvents", offset, day)
    if not integer(count, 0, 128) then return {}, true end
    local result, pending = {}, count == 0
    for index = 1, count do
        local event = call(C_Calendar, "GetDayEvent", offset, day, index)
        local kind = field(event, "calendarType")
        if kind == "HOLIDAY" then
            local theme = textureTheme(field(event, "iconTexture"))
            if theme then
                local phase = field(event, "sequenceType")
                local first = dateValue(field(event, "startTime"))
                local last = dateValue(field(event, "endTime"))
                if (phase == "START" or phase == "ONGOING" or phase == "END" or phase == "")
                    and first and last and first < last then
                    result[#result + 1] = { theme = theme, first = first, last = last }
                else
                    pending = true
                end
            end
        elseif kind == nil then
            pending = true
        end
    end
    return result, pending
end

local function scheduleBoundary(now)
    cancel(boundaryTimer)
    boundaryTimer = nil
    local delay = 300
    if now then
        local nextCheck = (math.floor(now / 1440) + 1) * 1440.0
        if cachedAt then delay = math.max(1, math.min(delay, (cachedAt + 5 - now) * 60)) end
        for _, record in ipairs(records or {}) do
            if record.first > now then nextCheck = math.min(nextCheck, record.first) end
            if record.last > now then nextCheck = math.min(nextCheck, record.last) end
        end
        delay = math.max(1, math.min(delay, (nextCheck - now - 1) * 60))
    end
    local version = generation
    local timer
    timer = newTimer(delay, function()
        if not enabled or generation ~= version or boundaryTimer ~= timer then return end
        boundaryTimer = nil
        refresh(false)
    end)
    boundaryTimer = timer
end

local function scheduleRetry(pending)
    if not pending then
        cancel(retryTimer)
        retryTimer = nil
        return
    end
    if retryTimer or retries >= #retryDelays then return end
    local version = generation
    local timer
    timer = newTimer(retryDelays[retries + 1], function()
        if not enabled or generation ~= version or retryTimer ~= timer then return end
        retryTimer = nil
        retries = retries + 1
        call(C_Calendar, "OpenCalendar")
        refresh(true)
    end)
    retryTimer = timer
end

refresh = function(force)
    if not enabled or refreshing then return end
    refreshing = true
    local now, year, month, day = dateValue(call(C_DateAndTime, "GetCurrentCalendarTime"))
    local scanned, pending = false, false
    if now then
        local currentDay = math.floor(now / 1440)
        if force or not records or cachedDay ~= currentDay or now < cachedAt or now >= cachedAt + 5 then
            records, pending = readRecords(year, month, day)
            cachedDay, cachedAt, scanned = currentDay, now, true
        end
    else
        records, cachedDay, cachedAt = nil, nil, nil
        scanned, pending = true, true
    end
    local found, themes = {}, {}
    if now then
        for _, record in ipairs(records or {}) do
            if record.first <= now and now < record.last then found[record.theme] = true end
        end
    end
    for _, theme in ipairs(themeOrder) do
        if found[theme] then themes[#themes + 1] = theme end
    end
    if scanned then scheduleRetry(pending) end
    if scanned or not boundaryTimer then scheduleBoundary(now) end
    refreshing = false
    publish(themes)
end

local function startRequest()
    generation = generation + 1
    cancel(retryTimer)
    cancel(boundaryTimer)
    retryTimer, boundaryTimer = nil, nil
    records, cachedDay, cachedAt = nil, nil, nil
    retries = 0
    call(C_Calendar, "OpenCalendar")
    refresh(true)
end

local function onEvent(_, event)
    if not enabled then return end
    if event == "PLAYER_ENTERING_WORLD" then startRequest()
    elseif event == "CALENDAR_UPDATE_EVENT_LIST" then refresh(true) end
end

local function registerFrame()
    if not frame and type(CreateFrame) == "function" then
        local ok, value = pcall(CreateFrame, "Frame")
        if ok and accessible(value) then frame = value end
    end
    call(frame, "SetScript", frame, "OnEvent", onEvent)
    call(frame, "RegisterEvent", frame, "CALENDAR_UPDATE_EVENT_LIST")
    call(frame, "RegisterEvent", frame, "PLAYER_ENTERING_WORLD")
end

function calendar.SetEnabled(value)
    if not accessible(value) or type(value) ~= "boolean" then return end
    if value == enabled then return end
    enabled = value
    if enabled then
        registerFrame()
        startRequest()
    else
        generation = generation + 1
        cancel(retryTimer)
        cancel(boundaryTimer)
        retryTimer, boundaryTimer = nil, nil
        records, cachedDay, cachedAt = nil, nil, nil
        call(frame, "UnregisterAllEvents", frame)
        call(frame, "SetScript", frame, "OnEvent", nil)
        publish({})
    end
end

function calendar.GetActiveThemes()
    refresh(false)
    return snapshot()
end

function calendar.RegisterListener(fn)
    if not accessible(fn) or type(fn) ~= "function" then return nil end
    listeners[fn] = true
    return function() listeners[fn] = nil end
end
