local _, addon = ...

addon.Cache = {}

local BoundedCache = {}
BoundedCache.__index = BoundedCache

local function compactConsumedOrder(self)
    if self.firstOrderIndex <= 64 or self.firstOrderIndex <= (self.lastOrderIndex / 2) then
        return
    end

    local compacted = {}
    for index = self.firstOrderIndex, self.lastOrderIndex do
        compacted[#compacted + 1] = self.order[index]
    end
    self.order = compacted
    self.firstOrderIndex = 1
    self.lastOrderIndex = #compacted
end

local function rebuildOrder(self)
    local rebuilt = {}
    for index = self.firstOrderIndex, self.lastOrderIndex do
        local ordered = self.order[index]
        local current = ordered and self.entries[ordered.key] or nil
        if current and current.token == ordered.token then
            rebuilt[#rebuilt + 1] = ordered
        end
    end
    self.order = rebuilt
    self.firstOrderIndex = 1
    self.lastOrderIndex = #rebuilt
end

local function evictOverflow(self)
    while self.size > self.maximum do
        local ordered = self.order[self.firstOrderIndex]
        self.order[self.firstOrderIndex] = nil
        self.firstOrderIndex = self.firstOrderIndex + 1

        if ordered then
            local current = self.entries[ordered.key]
            if current and current.token == ordered.token then
                self.entries[ordered.key] = nil
                self.size = self.size - 1
            end
        end
    end
    compactConsumedOrder(self)
end

local function compactStaleOrder(self)
    local retainedOrderEntries = self.lastOrderIndex - self.firstOrderIndex + 1
    if retainedOrderEntries > self.maximum * 4 then
        rebuildOrder(self)
    end
end

function BoundedCache:Get(key)
    local entry = self.entries[key]
    if not entry then
        return nil
    end
    return entry.value
end

function BoundedCache:Set(key, value)
    if key == nil then
        return false
    end

    local existing = self.entries[key]
    self.nextToken = self.nextToken + 1
    self.entries[key] = {
        token = self.nextToken,
        value = value,
    }
    self.lastOrderIndex = self.lastOrderIndex + 1
    self.order[self.lastOrderIndex] = {
        key = key,
        token = self.nextToken,
    }
    if not existing then
        self.size = self.size + 1
    end

    evictOverflow(self)
    compactStaleOrder(self)
    return true
end

function BoundedCache:Remove(key)
    if self.entries[key] == nil then
        return false
    end
    self.entries[key] = nil
    self.size = self.size - 1
    return true
end

function BoundedCache:Clear()
    self.entries = {}
    self.order = {}
    self.firstOrderIndex = 1
    self.lastOrderIndex = 0
    self.nextToken = 0
    self.size = 0
end

function BoundedCache:GetSize()
    return self.size
end

function addon.Cache.NewBounded(maximum)
    maximum = tonumber(maximum)
    if not maximum
        or maximum ~= maximum
        or maximum == math.huge
    then
        maximum = 1
    end
    maximum = math.max(1, math.floor(maximum))
    return setmetatable({
        entries = {},
        firstOrderIndex = 1,
        lastOrderIndex = 0,
        maximum = maximum,
        nextToken = 0,
        order = {},
        size = 0,
    }, BoundedCache)
end
