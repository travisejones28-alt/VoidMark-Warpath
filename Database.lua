local _, W = ...
local D = {}
W.DB = D
local defaults = { hostileOnly = true, npcs = false, sound = true, acquiredSound = true,
    pulse = true, center = false, cooldown = 10, historyLimit = 50, resurrection = false,
    mode = 'target', spell = '', collapsed = false, shown = true, minimapAngle = 220 }
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
function D:Normalize(raw, kind)
    if type(raw) ~= 'string' then return nil, 'Enter an exact player name.' end
    local name = trim(raw)
    if name == '' or #name > 100 or name:find('[%c/\\%[%];#|]') then return nil, 'Invalid name or macro control characters.' end
    if kind == 'npc' then
        if not name:find('[%a\128-\255]') then return nil, 'Enter an exact NPC name.' end
        return { key = 'npc:' .. string.lower(name), name = name, kind = 'npc', enabled = true }
    end
    local character, realm = name:match('^([^%-]+)%-(.+)$')
    character = character or name
    if #character < 2 or #character > 48 or character:find('[^%a\128-\255]') then return nil, 'Use Character or Character-Realm (letters only for the character).' end
    if realm and (realm:find('[^%w%s%-%\'\128-\255]') or not realm:find('[%a\128-\255]')) then return nil, 'Invalid realm.' end
    realm = W.Compat:Realm(realm)
    if realm == '' then return nil, 'Your realm is not available yet.' end
    return { key = 'player:' .. string.lower(character) .. '-' .. realm,
        name = name, targetName = character .. '-' .. realm, character = character, realm = realm, kind = 'player', enabled = true }
end
function D:Init()
    if type(WarpathCharDB) ~= 'table' then WarpathCharDB = {} end
    self.data = WarpathCharDB
    local d = self.data
    d.schema = 1
    if type(d.settings) ~= 'table' then d.settings = {} end
    for key, value in pairs(defaults) do
        if type(d.settings[key]) ~= type(value) then d.settings[key] = value end
    end
    local s = d.settings
    s.cooldown = math.max(1, math.min(120, tonumber(s.cooldown) or 10))
    s.historyLimit = math.max(0, math.min(200, math.floor(tonumber(s.historyLimit) or 50)))
    if s.mode ~= 'spell' then s.mode = 'target' end
    if type(d.entries) ~= 'table' then d.entries = {} end
    local entries, seen = {}, {}
    for _, old in ipairs(d.entries) do
        if type(old) == 'table' then
            local e = self:Normalize(old.name, old.kind)
            if e and not seen[e.key] then e.enabled = old.enabled ~= false; entries[#entries + 1] = e; seen[e.key] = true end
        end
    end
    d.entries = entries
    if type(d.history) ~= 'table' then d.history = {} end
    while #d.history > s.historyLimit do table.remove(d.history, 1) end
    if not self:Get(d.active) then d.active = nil end
    if type(d.macro) ~= 'table' then d.macro = nil end
end
function D:Get(key)
    for _, e in ipairs(self.data.entries) do if e.key == key then return e end end
end
function D:Find(name, kind)
    local normalized = self:Normalize(name, kind)
    return normalized and self:Get(normalized.key)
end
function D:Add(name, kind)
    local e, err = self:Normalize(name, kind)
    if not e then return nil, err end
    if self:Get(e.key) then return nil, 'Already on your watchlist.' end
    self.data.entries[#self.data.entries + 1] = e
    if not self.data.active and e.enabled then self.data.active = e.key end
    W:Changed()
    if W.Detection then W.Detection:Tick() end
    return e
end
function D:Select(key)
    local e = self:Get(key)
    if not e then return nil, 'Player is not on your watchlist.' end
    if not e.enabled then return nil, 'Enable this entry before arming it.' end
    if e.kind == 'npc' and not self.data.settings.npcs then return nil, 'Enable NPC tracking in Settings first.' end
    self.data.active = key
    W:Changed()
    return true
end
function D:Remove(key)
    for i, e in ipairs(self.data.entries) do
        if e.key == key then
            table.remove(self.data.entries, i)
            if self.data.active == key then self.data.active = nil end
            W:Changed()
            return true
        end
    end
end
function D:Enable(key, value)
    local e = self:Get(key)
    if not e then return end
    e.enabled = value
    if not value and self.data.active == key then self.data.active = nil end
    if W.Detection then W.Detection:Forget(key) end
    W:Changed()
end
function D:Reset()
    self.data.entries, self.data.active, self.data.history = {}, nil, {}
    if W.Detection then W.Detection:Reset() end
    W:Changed()
end
