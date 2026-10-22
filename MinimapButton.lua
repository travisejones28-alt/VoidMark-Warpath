local _, WP = ...
local M=WP:Module("MinimapButton",{})
function M:Initialize()
 if self.button or not Minimap or not WP.char then return end
 local b=CreateFrame("Button","VoidMarkWarpathMinimapButton",Minimap)
 b:SetSize(30,30);b:SetFrameStrata("MEDIUM");b:SetFrameLevel(Minimap:GetFrameLevel()+8)
 b:SetMovable(true);b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp")
 b:RegisterForDrag("LeftButton")
 local bg=b:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints()
 bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
 local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(19,19);icon:SetPoint("CENTER")
 icon:SetTexture("Interface\\Icons\\Ability_Rogue_DeadlyBrew")
 icon:SetVertexColor(.76,.42,1)
 local function position()
  local angle=math.rad(WP.char.minimapAngle or 225)
  b:ClearAllPoints()
  b:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*80,math.sin(angle)*80)
 end
 position()
 b:SetScript("OnDragStart",function(self) self.dragging=true;self:SetScript("OnUpdate",function()
  if not GetCursorPosition or not UIParent then return end
  local scale=UIParent:GetEffectiveScale()
  local x,y=GetCursorPosition()
  local mx,my=Minimap:GetCenter()
  if not x or not mx or not scale or scale==0 then return end
  local angle=math.deg(math.atan2(y/scale-my,x/scale-mx))
  WP.char.minimapAngle=angle
  position()
 end) end)
 b:SetScript("OnDragStop",function(self) self.dragging=false;self:SetScript("OnUpdate",nil) end)
 b:SetScript("OnClick",function(_,button)
  if button=="RightButton" then
   if WorldMapFrame then WorldMapFrame:Show();WP:Safe("MapOverlay","Refresh") end
  else WP:Safe("UI","Toggle") end
 end)
 b:SetScript("OnEnter",function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self,"ANCHOR_LEFT")
  GameTooltip:AddLine("VoidMark Warpath",.75,.48,1)
  GameTooltip:AddLine("Left-click: Warpath window",1,1,1)
  GameTooltip:AddLine("Right-click: World Map",1,1,1)
  GameTooltip:AddLine("Drag: move around minimap",.8,.8,.8)
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
 self.button=b
end
