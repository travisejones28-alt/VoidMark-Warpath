local _,WP=...
local M=WP:Module("MapOverlay",{})
function M:Clear()
 for _,pin in ipairs(self.pins or {}) do pin:Hide();pin:SetParent(nil) end
 self.pins={}
end
local function pin(parent,x,y,size,color,title,details)
 if parent:GetWidth()==0 or parent:GetHeight()==0 then return nil end
 local b=CreateFrame("Button",nil,parent)
 b:SetSize(size,size)
 b:SetPoint("CENTER",parent,"TOPLEFT",x*parent:GetWidth(),-y*parent:GetHeight())
 local t=b:CreateTexture(nil,"OVERLAY")
 t:SetAllPoints();t:SetTexture("Interface\\Buttons\\WHITE8X8")
 t:SetVertexColor(unpack(color))
 b:SetScript("OnEnter",function(self)
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  GameTooltip:AddLine(title,.75,.48,1)
  for _,line in ipairs(details) do GameTooltip:AddLine(line,1,1,1,true) end
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() GameTooltip:Hide() end)
 b:SetScript("OnClick",function() WP:Safe("UI","Refresh") end)
 return b
end
function M:Refresh()
 self:Clear()
 if not WP.char or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
 local parent=WorldMapFrame.ScrollContainer.Child
 if not parent or type(WorldMapFrame.GetMapID)~="function" then return end
 local ok,id=pcall(WorldMapFrame.GetMapID,WorldMapFrame)
 if not ok then return end
 local zone=id==1433 and "redridge" or id==1431 and "duskwood" or nil
 if not zone then return end
 local low,high=WP.char.levelMin or 15,WP.char.levelMax or 45
 if WP.char.showHeat~=false then
  for _,h in ipairs(WP.modules.Hotspots:Compute(zone,low,high)) do
   local lines={"Static score: "..h.score.."/100 (not enemy probability)",h.confidence,string.format("Classic: %.1f, %.1f",h.x*100,h.y*100)}
   for _,p in ipairs(h.points) do table.insert(lines,p.questName.." (#"..p.quest..")") end
   local b=pin(parent,h.x,h.y,24,{.58,.18,.9,.65},"Quest reference cluster",lines)
   if b then table.insert(self.pins,b) end
  end
 end
 if WP.char.showQuest~=false then
  for _,p in ipairs(WP.questAnchors) do
   if p.zone==zone and WP.modules.Hotspots:LevelOverlap(p,low,high) then
    local lines={p.questName.." (#"..p.quest..")",p.kind.." | Level "..p.min.."+",string.format("Classic 1.12 coords: %.1f, %.1f",p.x*100,p.y*100),"Classic Era reference; objective not inferred"}
    local b=pin(parent,p.x,p.y,12,{1,.82,.26,.95},p.name,lines)
    if b then table.insert(self.pins,b) end
   end
  end
 end
end
function M:Initialize()
 if self.initialized then return end
 self.initialized=true;self.pins={}
 if not WorldMapFrame then return end
 WorldMapFrame:HookScript("OnShow",function() M:Refresh() end)
 if type(hooksecurefunc)=="function" and type(WorldMapFrame.OnMapChanged)=="function" then
  hooksecurefunc(WorldMapFrame,"OnMapChanged",function() M:Refresh() end)
 end
 if WorldMapFrame.ScrollContainer then
  WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged",function() M:Refresh() end)
 end
 self:Refresh()
end
