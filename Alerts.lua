local _, W = ...
local A = { last = {} }
W.Alerts = A
function A:Notify(e, kind, snapshot)
    local settings, now = W.DB.data.settings, GetTime()
    local id = e.key .. ':' .. kind
    if self.last[id] and now - self.last[id] < settings.cooldown then return end
    self.last[id] = now
    local labels = { seen = 'Seen', acquired = 'Target Acquired', alive = 'Observed dead → alive' }
    local text = e.name .. ' — ' .. (labels[kind] or kind)
    local h = W.DB.data.history
    if settings.historyLimit > 0 then
        h[#h + 1] = { time = time(), name = e.name, kind = kind, source = snapshot.unit, dead = snapshot.dead }
        while #h > settings.historyLimit do table.remove(h, 1) end
    end
    -- One sound at most per cooldown across all players/event types.
    local sound = kind == 'acquired' and settings.acquiredSound or (kind ~= 'acquired' and settings.sound)
    if sound and (not self.lastSound or now - self.lastSound >= settings.cooldown) then
        self.lastSound = now
        if PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, 'Master') end
    end
    if settings.center then W.UI:CenterAlert(text) end
    if settings.pulse then W.UI:Pulse() end
    W:Print(text)
end
