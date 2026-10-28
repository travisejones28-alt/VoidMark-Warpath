local _, W = ...
local D = { plates = {}, states = {}, acquired = nil }
W.Detection = D
function D:Reset() self.states, self.acquired = {}, nil; W.Alerts.last = {} end
function D:Forget(key) self.states[key] = nil end
function D:Match(s)
    if W.DB.data.settings.hostileOnly and s.hostile ~= true then return nil end
    if s.kind == 'npc' and not W.DB.data.settings.npcs then return nil end
    local key = s.kind .. ':' .. string.lower(s.name)
    if s.kind == 'player' then key = key .. '-' .. s.realm end
    local e = W.DB:Get(key)
    if e and e.enabled then return e end
end
function D:Tick()
    if not W.DB.data then return end
    local now, visible = GetTime(), {}
    local tokens = { 'target', 'mouseover' }
    for token in pairs(self.plates) do tokens[#tokens + 1] = token end
    local targetGUID
    -- Target first: acquisition replaces the redundant initial Seen alert.
    for _, unit in ipairs(tokens) do
        local s = W.Compat:Snapshot(unit)
        local e = s and self:Match(s)
        if e then
            visible[e.key] = true
            local state = self.states[e.key]
            local continuous = state and state.guid == s.guid and now - state.last <= 2
            local sameObservation = continuous and state.present
            local acquired = unit == 'target' and self.acquired ~= s.guid
            if unit == 'target' then targetGUID = s.guid end
            if acquired then W.Alerts:Notify(e, 'acquired', s)
            elseif not continuous then W.Alerts:Notify(e, 'seen', s) end
            -- Only consecutive observable identity/state is evidence of a transition.
            if sameObservation and state.dead == true and s.dead == false then W.Alerts:Notify(e, 'alive', s) end
            self.states[e.key] = { guid = s.guid, dead = s.dead, present = true, last = now, unit = unit }
        end
    end
    self.acquired = targetGUID
    for key, state in pairs(self.states) do
        if not visible[key] then
            state.present = false
            if now - state.last > 300 then self.states[key] = nil end
        end
    end
    W:Refresh()
end
function D:Seed()
    self.plates = {}
    for _, plate in pairs(W.Compat:Plates()) do
        local token = plate.namePlateUnitToken
        if not (issecretvalue and issecretvalue(token)) and type(token) == 'string' then self.plates[token] = true end
    end
end
function D:Status(key)
    local state = self.states[key]
    if state and state.present then
        return (state.guid == self.acquired and 'Target Acquired' or 'Seen') .. (state.dead == true and ' • dead' or '')
    end
    return key == W.Macros.armed and 'Armed' or 'Watching'
end
