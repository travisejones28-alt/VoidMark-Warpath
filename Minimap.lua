local _, W = ...
W.Minimap = {}
function W.Minimap:Create()
    if not Minimap then return end
    local b = CreateFrame('Button', 'WarpathMinimapButton', Minimap, 'BackdropTemplate')
    self.button = b; b:SetSize(28, 28); b:SetFrameStrata('MEDIUM'); b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 2})
    b:SetBackdropColor(.045, .025, .075, 1); b:SetBackdropBorderColor(.66, .34, .95, 1)
    local text = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'); text:SetPoint('CENTER'); text:SetText('W'); text:SetTextColor(.85, .65, 1)
    b:RegisterForClicks('LeftButtonUp', 'RightButtonUp'); b:RegisterForDrag('LeftButton')
    function self:Position()
        local a = math.rad(W.DB.data.settings.minimapAngle)
        local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2 + 8
        b:ClearAllPoints(); b:SetPoint('CENTER', Minimap, 'CENTER', math.cos(a) * radius, math.sin(a) * radius)
    end
    b:SetScript('OnClick', function(_, key) if key == 'RightButton' then W.UI:Settings() else W.UI:Toggle() end end)
    b:SetScript('OnDragStart', function()
        b:SetScript('OnUpdate', function()
            local x, y = GetCursorPosition(); local scale = Minimap:GetEffectiveScale(); local mx, my = Minimap:GetCenter()
            W.DB.data.settings.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx)); self:Position()
        end)
    end)
    b:SetScript('OnDragStop', function() b:SetScript('OnUpdate', nil) end)
    b:SetScript('OnEnter', function()
        GameTooltip:SetOwner(b, 'ANCHOR_LEFT'); GameTooltip:SetText('Warpath', .8, .6, 1)
        GameTooltip:AddLine('Left: toggle • Right: settings\nDrag to move around minimap', 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self:Position()
end
