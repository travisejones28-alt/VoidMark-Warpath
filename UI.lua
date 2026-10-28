local _, W = ...
local U = { page = 1 }
W.UI = U
local violet = { .58, .31, .88 }
local function skin(f)
    f:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
    f:SetBackdropColor(.035, .03, .05, .97)
    f:SetBackdropBorderColor(.39, .20, .60, .95)
end
local function label(parent, text, x, y, size)
    local t = parent:CreateFontString(nil, 'OVERLAY', size or 'GameFontHighlightSmall')
    t:SetPoint('TOPLEFT', x, y); t:SetText(text); t:SetJustifyH('LEFT')
    return t
end
local function tip(f, title, text)
    f:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(title, .75, .55, 1)
        GameTooltip:AddLine(text, .85, .85, .85, true); GameTooltip:Show()
    end)
    f:SetScript('OnLeave', function() GameTooltip:Hide() end)
end
local function button(parent, text, x, y, width, action)
    local b = CreateFrame('Button', nil, parent, 'BackdropTemplate')
    b:SetSize(width, 25); b:SetPoint('TOPLEFT', x, y); skin(b)
    b.text = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall'); b.text:SetPoint('CENTER'); b.text:SetText(text)
    b:SetScript('OnClick', action)
    b:SetScript('OnEnter', function(self) self:SetBackdropBorderColor(.8, .5, 1) end)
    b:SetScript('OnLeave', function(self) self:SetBackdropBorderColor(.39, .20, .60) end)
    return b
end
local function edit(parent, x, y, width, placeholder)
    local e = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    e:SetAutoFocus(false); e:SetSize(width, 26); e:SetPoint('TOPLEFT', x, y)
    e:SetMaxLetters(100); e:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    tip(e, placeholder, 'Use the exact spelling. Player names may include -Realm. Press Enter to apply.')
    return e
end
local function report(ok, err) if not ok then W:Print(err or 'Unable to complete action.') end end
function U:Create()
    local f = CreateFrame('Frame', 'WarpathWindow', UIParent, 'BackdropTemplate')
    self.frame = f; f:SetSize(350, 410); skin(f)
    f:SetFrameStrata('MEDIUM'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    local p = W.DB.data.position
    if type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' then
        f:SetPoint('CENTER', UIParent, 'CENTER', p.x, p.y)
    else f:SetPoint('CENTER', UIParent, 'CENTER', 320, 80) end
    local header = CreateFrame('Frame', nil, f); header:SetPoint('TOPLEFT'); header:SetPoint('TOPRIGHT', -60, 0); header:SetHeight(30)
    header:EnableMouse(true); header:RegisterForDrag('LeftButton')
    header:SetScript('OnDragStart', function() f:StartMoving() end)
    header:SetScript('OnDragStop', function()
        f:StopMovingOrSizing()
        local x, y = f:GetCenter(); local px, py = UIParent:GetCenter()
        W.DB.data.position = { x = x - px, y = y - py }
    end)
    local title = label(header, 'WARPATH  |cff9477adTARGET WATCH|r', 12, -10)
    title:SetTextColor(.79, .61, 1)
    button(f, '−', 290, -5, 25, function() W.DB.data.settings.collapsed = not W.DB.data.settings.collapsed; self:Refresh() end)
    button(f, '×', 319, -5, 25, function() self:Toggle() end)
    self.active = label(f, '', 12, -37, 'GameFontNormal')
    self.active:SetWidth(326); self.active:SetWordWrap(false)
    self.status = label(f, '', 12, -59); self.status:SetWidth(326); self.status:SetWordWrap(false)
    local body = CreateFrame('Frame', nil, f); self.body = body; body:SetAllPoints()
    self.mode = button(body, 'Target Only', 12, -86, 154, function()
        if W.DB.data.settings.mode == 'spell' then report(W.Targeting:SetMode('target'))
        else self:Settings(); self.settings:Show(); self.spell:SetFocus() end
    end)
    tip(self.mode, 'Targeting mode', 'Target Only: /targetexact, preserving the old target on failure. Target + Spell: clears the old target, attempts the exact name, then casts only at a living hostile target. Set a spell in Settings. Changes wait until combat ends.')
    self.res = button(body, 'Resurrection Watch', 175, -86, 163, function()
        local s = W.DB.data.settings; s.resurrection = not s.resurrection; self:Refresh()
    end)
    tip(self.res, 'Resurrection Watch', 'Keeps the selected player armed for repeated manual keypresses. Alerts use visible unit evidence. Only a continuously observed dead-to-alive transition is labeled as such. Never scans for hidden players.')
    label(body, 'WATCHLIST', 12, -125):SetTextColor(.65, .57, .76)
    self.counter = label(body, '', 230, -125)
    self.rows = {}
    for i = 1, 5 do
        local y = -143 - (i - 1) * 35
        local row = CreateFrame('Frame', nil, body); row:SetSize(326, 33); row:SetPoint('TOPLEFT', 12, y)
        row.check = CreateFrame('CheckButton', nil, row, 'UICheckButtonTemplate'); row.check:SetSize(24, 24); row.check:SetPoint('LEFT', -3, 0)
        row.check:SetScript('OnClick', function(b) if row.key then W.DB:Enable(row.key, b:GetChecked()) end end)
        tip(row.check, 'Watch entry', 'Enable or disable detection for this entry. Disabling an armed entry queues macro disarming in combat.')
        row.select = button(row, '', 25, 0, 270, function() if row.key then report(W.DB:Select(row.key)) end end)
        row.select:SetHeight(33); row.select.text:SetPoint('CENTER', 0, 6)
        row.name = row.select.text; row.name:SetWidth(250); row.name:SetWordWrap(false)
        row.status = label(row.select, '', 9, -19); row.status:SetTextColor(.65, .62, .71)
        row.remove = button(row, '×', 299, -4, 27, function() if row.key then W.DB:Remove(row.key) end end)
        self.rows[i] = row
    end
    button(body, '‹', 12, -322, 27, function() self.page = math.max(1, self.page - 1); self:Refresh() end)
    button(body, '›', 43, -322, 27, function() self.page = self.page + 1; self:Refresh() end)
    button(body, '+ Current Target', 80, -322, 143, function() report(W.Targeting:AddCurrent()) end)
    button(body, 'Settings', 231, -322, 107, function() self:Settings() end)
    self.input = edit(body, 19, -354, 235, 'Enter Player Name')
    local function add()
        local e, err = W.DB:Add(self.input:GetText()); report(e, err)
        if e then self.input:SetText(''); self.input:ClearFocus(); self.page = math.ceil(#W.DB.data.entries / 5); self:Refresh() end
    end
    self.input:SetScript('OnEnterPressed', add)
    button(body, 'Add', 265, -354, 73, add)
    button(body, 'Arm', 12, -385, 62, function() W:Changed(); if W.Macros.error then W:Print(W.Macros.error) end end)
    button(body, 'Place Macro', 81, -385, 119, function() report(W.Macros:Pickup()) end)
    button(body, 'Copy Macro', 207, -385, 131, function() self:CopyMacro() end)
    tip(f, 'Warpath', 'Drag the header to move. Place Macro picks up the native character macro: drop it onto an action-bar slot and bind that slot normally. Every targeting attempt requires your keypress.')
    self:CreateCenterAlert()
    self:Refresh()
end
function U:Refresh()
    local s, d = W.DB.data.settings, W.DB.data
    local e, armed = W.DB:Get(d.active), W.DB:Get(W.Macros.armed)
    local name = e and e.name or 'None selected'
    self.active:SetText('Active: |cffd2afff' .. name .. '|r')
    local text = e and W.Detection:Status(e.key) or 'Watching'
    if s.resurrection then text = 'RES WATCH • ' .. text end
    if W.Macros.pending then
        text = 'COMBAT QUEUED • Macro: ' .. (armed and armed.name or W.Macros.armedName or 'none')
    elseif W.Macros.error then text = 'MACRO ERROR • See /warpath status'
    elseif armed then text = text .. (W.Macros.appliedMode == 'spell' and ' • + Spell' or ' • Target Only') end
    self.status:SetText(text); self.status:SetTextColor(.72, .62, .88)
    self.frame:SetHeight(s.collapsed and 81 or 418); self.body:SetShown(not s.collapsed)
    self.frame:SetShown(s.shown)
    self.mode.text:SetText(s.mode == 'spell' and 'Target + Spell' or 'Target Only')
    self.res.text:SetText(s.resurrection and '|cffd2afffRes Watch: ON|r' or 'Res Watch: OFF')
    local pages = math.max(1, math.ceil(#d.entries / 5)); self.page = math.max(1, math.min(self.page, pages))
    self.counter:SetText(#d.entries .. ' • ' .. self.page .. '/' .. pages)
    for i, row in ipairs(self.rows) do
        local entry = d.entries[(self.page - 1) * 5 + i]; row:SetShown(entry ~= nil)
        if entry then
            row.key = entry.key; row.check:SetChecked(entry.enabled)
            row.name:SetText((entry.key == d.active and '|cffd2afff' or '|cffdddddd') .. entry.name .. '|r')
            local status = not entry.enabled and 'Disabled' or (entry.kind == 'npc' and not s.npcs and 'NPC tracking off') or W.Detection:Status(entry.key)
            if entry.key == d.active then status = 'ACTIVE • ' .. status end
            row.status:SetText(status)
            row.select:SetBackdropBorderColor(entry.key == d.active and .68 or .22, .18, entry.key == d.active and .94 or .3)
        end
    end
end
function U:Toggle() W.DB.data.settings.shown = not W.DB.data.settings.shown; self:Refresh() end
function U:CopyMacro()
    local text, _, err = W.Macros:Build()
    if not text then W:Print(err); return end
    if not self.copy then
        local f = CreateFrame('Frame', 'WarpathMacroCopy', UIParent, 'BackdropTemplate'); self.copy = f
        f:SetSize(410, 235); f:SetPoint('CENTER'); f:SetFrameStrata('DIALOG'); skin(f); f:EnableMouse(true)
        label(f, 'GENERATED MACRO • Ctrl+C to copy', 14, -14, 'GameFontNormal')
        label(f, 'Preview of requested configuration. Native macro may be queued.', 14, -36)
        local e = CreateFrame('EditBox', nil, f); self.copyText = e; e:SetMultiLine(true); e:SetFontObject(ChatFontNormal)
        e:SetPoint('TOPLEFT', 16, -60); e:SetSize(378, 130); e:SetAutoFocus(false)
        e:SetScript('OnEscapePressed', function() f:Hide() end)
        button(f, 'Close', 311, -200, 85, function() f:Hide() end)
    end
    self.copy:Show(); self.copyText:SetText(text); self.copyText:SetFocus(); self.copyText:HighlightText()
end
function U:Settings()
    if self.settings then self.settings:SetShown(not self.settings:IsShown()); return end
    local f = CreateFrame('Frame', 'WarpathSettings', UIParent, 'BackdropTemplate'); self.settings = f
    f:SetSize(350, 455); f:SetPoint('CENTER'); f:SetFrameStrata('DIALOG'); skin(f); f:EnableMouse(true)
    label(f, 'WARPATH • SETTINGS', 14, -15, 'GameFontNormal')
    button(f, '×', 311, -8, 26, function() f:Hide() end)
    local s = W.DB.data.settings
    local items = {
        { 'hostileOnly', 'Hostile units only' }, { 'npcs', 'Allow optional NPC tracking' },
        { 'sound', 'Sound on detection / observed alive' }, { 'acquiredSound', 'Sound on newly acquired target' },
        { 'pulse', 'Brief violet window pulse' }, { 'center', 'Screen-center notification' },
    }
    for i, item in ipairs(items) do
        local b = CreateFrame('CheckButton', nil, f, 'UICheckButtonTemplate'); b:SetSize(26, 26); b:SetPoint('TOPLEFT', 11, -40 - (i - 1) * 28)
        label(b, item[2], 29, -8); b:SetChecked(s[item[1]])
        b:SetScript('OnClick', function(self)
            s[item[1]] = not not self:GetChecked()
            W.Detection:Reset(); W:Changed(); W.Detection:Tick()
        end)
    end
    label(f, 'Optional spell (localized name)', 14, -222)
    self.spell = edit(f, 20, -240, 245, 'Spell name'); self.spell:SetText(s.spell)
    button(f, 'Apply', 275, -240, 61, function()
        report(W.Targeting:SetMode('spell', self.spell:GetText()))
        if not W.Compat:SpellName(self.spell:GetText()) then W:Print('Spell is not recognized by this client; confirm spelling and that it is learned.') end
    end)
    self.spell:SetScript('OnEnterPressed', function() report(W.Targeting:SetMode('spell', self.spell:GetText())); self.spell:ClearFocus() end)
    button(f, 'Target Only', 14, -273, 112, function() report(W.Targeting:SetMode('target')) end)
    label(f, 'Spell mode clears the prior target on EVERY keypress.', 14, -307)
    label(f, 'Alert cooldown (1–120 sec)', 14, -330)
    local cooldown = edit(f, 273, -323, 60, 'Cooldown'); cooldown:SetText(tostring(s.cooldown))
    cooldown:SetScript('OnEnterPressed', function(self)
        s.cooldown = math.max(1, math.min(120, tonumber(self:GetText()) or 10)); self:SetText(tostring(s.cooldown)); self:ClearFocus()
    end)
    label(f, 'History entries (0–200)', 14, -365)
    local history = edit(f, 273, -357, 60, 'History length'); history:SetText(tostring(s.historyLimit))
    history:SetScript('OnEnterPressed', function(self)
        s.historyLimit = math.max(0, math.min(200, math.floor(tonumber(self:GetText()) or 50)))
        while #W.DB.data.history > s.historyLimit do table.remove(W.DB.data.history, 1) end
        self:SetText(tostring(s.historyLimit)); self:ClearFocus()
    end)
    button(f, 'History', 14, -398, 105, function() W:History() end)
    button(f, 'Clear Watchlist', 129, -398, 207, function() StaticPopup_Show('WARPATH_RESET') end)
    label(f, W.Compat.forever and 'Forever: restricted unit identities are skipped.' or 'Classic Era • Manual hardware input required', 14, -434)
end
function U:CreateCenterAlert()
    local f = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate'); self.center = f
    f:SetSize(420, 65); f:SetPoint('TOP', UIParent, 'TOP', 0, -180); f:SetFrameStrata('HIGH'); skin(f)
    f.text = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge'); f.text:SetPoint('CENTER'); f.text:SetWidth(390); f.text:SetTextColor(.82, .65, 1)
    f:Hide()
end
function U:CenterAlert(text) self.center.text:SetText(text); self.center.untilTime = GetTime() + 2; self.center:Show() end
function U:Pulse() self.pulseUntil = GetTime() + .8 end
function U:Animate()
    local now = GetTime()
    if self.pulseUntil then
        if now >= self.pulseUntil then self.pulseUntil = nil; self.frame:SetBackdropBorderColor(.39, .20, .60, .95)
        else self.frame:SetBackdropBorderColor(.8, .45, 1, 1) end
    end
    if self.center.untilTime and now >= self.center.untilTime then self.center:Hide(); self.center.untilTime = nil end
end
