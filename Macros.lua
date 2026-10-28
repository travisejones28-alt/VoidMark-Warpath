local _, W = ...
local M = {}
W.Macros = M
M.limit = 255 -- conservative native macro byte budget on both clients
function M:ValidateSpell(raw)
    if type(raw) ~= 'string' then return nil, 'Enter a spell name.' end
    local s = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' or #s > 100 or s:find('[%c/\\%[%];#|]') then return nil, 'Invalid spell name or macro control characters.' end
    return s
end
function M:Build()
    local d = W.DB.data
    local e = W.DB:Get(d.active)
    if not e or not e.enabled or (e.kind == 'npc' and not d.settings.npcs) then return '#showtooltip\n/stopmacro', nil end
    local text
    if d.settings.mode == 'spell' then
        local spell, err = self:ValidateSpell(d.settings.spell)
        if not spell then return nil, nil, err end
        -- A failed /targetexact preserves the old target. Clear first in spell mode.
        -- Explicit @target prevents auto-self-cast/focus/mouseover fallback.
        text = '#showtooltip ' .. spell .. '\n/cleartarget\n/targetexact ' .. (e.targetName or e.name) ..
            '\n/stopmacro [noexists]\n/cast [@target,harm,nodead] ' .. spell
    else
        text = '#showtooltip\n/targetexact ' .. (e.targetName or e.name)
    end
    if #text > self.limit then return nil, nil, 'Macro exceeds 255 bytes; shorten the realm or spell name.' end
    return text, e.key
end
function M:OwnedIndex()
    local saved = W.DB.data.macro
    if not saved or type(saved.name) ~= 'string' or type(saved.body) ~= 'string' then return nil end
    -- IDs shift when macros are deleted; resolve by unique name AND last-owned body.
    if not GetMacroInfo then return nil end
    local accountMax, charMax = W.Compat:MacroLimits()
    local count = accountMax + charMax
    for i = 1, count do
        local name, _, body = GetMacroInfo(i)
        if name == saved.name and body == saved.body then return i end
    end
end
function M:Restore()
    local saved = W.DB.data.macro
    if saved and self:OwnedIndex() then
        self.armed, self.armedName = saved.targetKey, saved.targetName
        self.appliedMode, self.appliedSpell = saved.mode, saved.spell
        self.index = self:OwnedIndex()
    end
end
function M:Apply()
    if W.Compat:Combat() then self.pending = true; self.message = 'COMBAT: change queued; existing action-bar macro unchanged'; return end
    self.pending, self.error = false, nil
    local body, key, err = self:Build()
    if not body then self.error = err; self.message = err; return end
    if not (GetMacroInfo and GetMacroIndexByName and GetNumMacros and CreateMacro and EditMacro) then
        self.error = 'Native macro APIs unavailable; use Copy Macro.'; self.message = self.error; return
    end
    local index = self:OwnedIndex()
    local name
    if index then
        name = W.DB.data.macro.name
        self.applying = true
        local ok, result = pcall(EditMacro, index, name, 136116, body)
        self.applying = false
        if not ok or not result then self.error = 'Cannot update macro; use Copy Macro.'; self.message = self.error; return end
        index = result
    elseif key then
        local _, chars = GetNumMacros()
        local _, charMax = W.Compat:MacroLimits()
        if chars >= charMax then self.error = 'Character macros full; free a slot, then Arm. Copy Macro is available.'; self.message = self.error; return end
        for n = 1, 99 do
            local candidate = n == 1 and 'Warpath' or ('Warpath' .. n)
            if GetMacroIndexByName(candidate) == 0 then name = candidate; break end
        end
        if not name then self.error = 'No free Warpath macro name.'; self.message = self.error; return end
        self.applying = true
        local ok, result = pcall(CreateMacro, name, 136116, body, true)
        self.applying = false
        if not ok or not result or result == 0 then self.error = 'Cannot create character macro; use Copy Macro.'; self.message = self.error; return end
        index = result
    end
    if index then
        local entry = W.DB:Get(key)
        W.DB.data.macro = { name = name, body = body, targetKey = key, targetName = entry and entry.name,
            mode = W.DB.data.settings.mode, spell = W.DB.data.settings.spell }
        self.index = index
    else self.index = nil end
    local entry = W.DB:Get(key)
    self.armedName = entry and entry.name
    self.armed, self.appliedMode, self.appliedSpell = key, W.DB.data.settings.mode, W.DB.data.settings.spell
    self.message = key and ('Macro: ' .. name .. ' — place on an action bar') or 'Select an enabled target to arm'
end
function M:Pickup()
    if W.Compat:Combat() then return nil, 'Cannot move macros in combat.' end
    self:Apply()
    if self.error then return nil, self.error end
    if not self.armed or not self.index then return nil, 'Arm a target first.' end
    PickupMacro(self.index)
    return true
end
