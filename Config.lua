local addonName, W = ...
StaticPopupDialogs.WARPATH_RESET = {
    text = 'Clear this character’s Warpath watchlist and detection history? The native macro will be disarmed when combat ends.',
    button1 = 'Clear', button2 = 'Cancel', timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() W.DB:Reset() end,
    preferredIndex = 3,
}
function W:History()
    local history = self.DB.data.history
    if #history == 0 then self:Print('No confirmed encounters recorded.'); return end
    for _, item in ipairs(history) do
        if type(item) == 'table' and type(item.time) == 'number' and type(item.name) == 'string' then
            self:Print(date('%m/%d %H:%M', item.time) .. ' ' .. item.name .. ' — ' .. tostring(item.kind) .. ' (' .. tostring(item.source) .. ')')
        end
    end
end
function W:Command(message)
    local command, arg = (message or ''):match('^%s*(%S*)%s*(.-)%s*$'); command = string.lower(command)
    local ok, err
    if command == '' then self.UI:Toggle()
    elseif command == 'add' then ok, err = self.DB:Add(arg)
    elseif command == 'npc' then ok, err = self.DB:Add(arg, 'npc')
    elseif command == 'remove' or command == 'target' then
        local e = self.DB:Find(arg) or self.DB:Find(arg, 'npc')
        if not e then self:Print('Name is not on your watchlist.'); return end
        if command == 'remove' then ok, err = self.DB:Remove(e.key) else ok, err = self.DB:Select(e.key) end
    elseif command == 'list' then
        if #self.DB.data.entries == 0 then self:Print('Watchlist empty.') end
        for _, e in ipairs(self.DB.data.entries) do self:Print(e.name .. ' — ' .. (e.enabled and self.Detection:Status(e.key) or 'Disabled')) end
    elseif command == 'reset' then StaticPopup_Show('WARPATH_RESET')
    elseif command == 'settings' then self.UI:Settings()
    elseif command == 'macro' then self.UI:CopyMacro()
    elseif command == 'history' then self:History()
    elseif command == 'status' then
        self:Print(self.Macros.message or 'No macro armed.')
        local e = self.DB:Get(self.Macros.armed)
        self:Print('Applied target: ' .. (e and e.name or self.Macros.armedName or 'none') .. '; client interface: ' .. self.Compat.interface)
    else self:Print('/warpath [add NAME | remove NAME | target NAME | list | reset | settings | macro | history | status | npc NAME]') end
    if err then self:Print(err) end
end
SLASH_WARPATH1 = '/warpath'
SlashCmdList.WARPATH = function(message) if W.DB.data then W:Command(message) end end
W.events:SetScript('OnEvent', function(_, event, arg)
    if event == 'ADDON_LOADED' then
        if arg ~= addonName then return end
        W.DB:Init(); W.Macros:Restore(); W.UI:Create(); W.Minimap:Create()
        W:Print('Alpha 1.0 — arm a name, Place Macro, then bind its action-bar slot.')
        if not W.Compat.era and not W.Compat.forever then W:Print('This client is unverified. Use /warpath macro for a native macro fallback.') end
        return
    end
    if not W.DB.data then return end
    if event == 'UNIT_FLAGS' or event == 'UNIT_HEALTH' or event == 'UNIT_NAME_UPDATE' then
        if issecretvalue and issecretvalue(arg) then return end
        if arg ~= 'target' and arg ~= 'mouseover' and not W.Detection.plates[arg] then return end
    end
    if event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then
        W.Detection:Seed(); W:Changed()
    elseif event == 'PLAYER_REGEN_ENABLED' then W:Changed()
    elseif event == 'PLAYER_REGEN_DISABLED' then W:Refresh()
    elseif event == 'NAME_PLATE_UNIT_ADDED' then
        if not (issecretvalue and issecretvalue(arg)) and type(arg) == 'string' then W.Detection.plates[arg] = true end
    elseif event == 'NAME_PLATE_UNIT_REMOVED' then
        if not (issecretvalue and issecretvalue(arg)) and type(arg) == 'string' then W.Detection.plates[arg] = nil end
    elseif event == 'UPDATE_MACROS' then
        -- Verify ownership without editing during a macro update callback.
        if not W.Macros.applying and W.Macros.armed and not W.Macros:OwnedIndex() then
            W.Macros.error = 'Warpath macro was edited/deleted. Arm again to create a separate macro.'
            W.Macros.message = W.Macros.error
        end
    end
    W.Detection:Tick()
end)
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_TARGET_CHANGED',
    'UPDATE_MOUSEOVER_UNIT', 'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED', 'UNIT_FLAGS', 'UNIT_HEALTH',
    'UNIT_NAME_UPDATE', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED', 'UPDATE_MACROS' }) do W.Compat:Register(event) end
local elapsed = 0
W.events:SetScript('OnUpdate', function(_, dt)
    if not W.DB.data then return end
    W.UI:Animate()
    elapsed = elapsed + dt
    if elapsed >= .25 then elapsed = 0; W.Detection:Tick() end
end)
