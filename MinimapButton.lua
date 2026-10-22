local _, WP = ...
local M=WP:Module("MinimapButton",{})
local function offsets(angle)
 local rad=math.rad(angle)
 local dx,dy=math.cos(rad),math.sin(rad)
 local w,h=Minimap:GetWidth()/2+9,Minimap:GetHeight()/2+9
 if w<=0 or h<=0 then return 0,0 end
 local tx=math.abs(dx)>0.0001 and w/math.abs(dx) or math.huge
 local ty=math.abs(dy)>0.0001 and h/math.abs(dy) or math.huge
 local t=math.min(tx,ty)
 return dx*t,dy*t
end
function M:Position()
 if not self.button or not WP.char or not Minimap then return end
 local x,y=offsets(WP.char.minimapAngle or 225)
 self.button:ClearAllPoints()
 self.button:SetPoint("CENTER",Minimap,"CENTER",x,y)
end
function M:Initialize()
 if self.button or not Minimap or not WP.char then return end
 local b=CreateFrame("Button","VoidMarkWarpathMinimapButton",Minimap)
 b:SetSize(30,30);b:SetFrameStrata("MEDIUM");b:SetFrameLevel(Minimap:GetFrameLevel()+8)
 b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp");b:RegisterForDrag("LeftButton")
 local bg=b:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints()
 bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
 local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(19,19);icon:SetPoint("CENTER")
 icon:SetTexture("Interface\\Icons\\Ability_Rogue_DeadlyBrew")
 icon:SetVertexColor(.76,.42,1)
 self.button=b
 self:Position()
 local dragDriver=CreateFrame("Frame",nil,b)
 dragDriver:Hide()
 dragDriver:SetScript("OnUpdate",function()
   if not GetCursorPosition then return end
   local mx,my=Minimap:GetCenter()
   local scale=Minimap:GetEffectiveScale()
   local x,y=GetCursorPosition()
   if not mx or not scale or scale==0 then return end
   local px,py=x/scale-mx,y/scale-my
   if math.abs(px)+math.abs(py)<1 then return end
   WP.char.minimapAngle=math.deg(math.atan2(py,px))
   M:Position()
 end)
 b:SetScript("OnDragStart",function(self) self.dragging=true;dragDriver:Show() end)
 b:SetScript("OnDragStop",function(self) self.dragging=false;dragDriver:Hide() end)
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
  GameTooltip:AddLine("Drag: move along square edge",.8,.8,.8)
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
 local previousW,previousH=Minimap:GetSize()
 local timer=0
 b:HookScript("OnUpdate",function(_,dt)
  if b.dragging then return end
  timer=timer+(dt or 0)
  if timer<.5 then return end
  timer=0
  local w,h=Minimap:GetSize()
  if w~=previousW or h~=previousH then previousW,previousH=w,h;M:Position() end
 end)
end
