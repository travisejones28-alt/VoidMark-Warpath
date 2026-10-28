local addonName, W = ...
W.name, W.version = addonName, '1.0.0-alpha.1'
W.events = CreateFrame('Frame')
function W:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffb785ffWarpath|r: ' .. tostring(message)) end
end
function W:Refresh()
    if self.UI and self.UI.frame then self.UI:Refresh() end
end
function W:Changed()
    self.Macros:Apply()
    self:Refresh()
end
