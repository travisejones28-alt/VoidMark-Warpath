local _, WP = ...
local M=WP:Module("MapOverlay",{active={},free={},lines={},freeLines={}})
local mapZone={[1433]="redridge",[1431]="duskwood"}
local function validCanvas()
 if not WorldMapFrame or not WorldMapFrame:IsShown() or not WorldMapFrame.ScrollContainer then return end
 local c=WorldMapFrame.ScrollContainer.Child
 if c and c:GetWidth()>0 and c:GetHeight()>0 then return c end
end
function M:Clear()
 if GameTooltip and self.tooltipOwner then GameTooltip:Hide();self.tooltipOwner=nil end
 for _,b in ipairs(self.active) do
  b:Hide();b:ClearAllPoints();b:SetScript("OnEnter",nil);b:SetScript("OnLeave",nil);b:SetScript("OnMouseWheel",nil)
  self.free[#self.free+1]=b
 end
 self.active={}
 for _,line in ipairs(self.lines) do line:Hide();self.freeLines[#self.freeLines+1]=line end
 self.lines={}
end
function M:Pin(canvas,x,y,size,color,title,details,shape)
 if not WP:ValidCoordinate(x) or not WP:ValidCoordinate(y) then return end
 local b=table.remove(self.free)
 if not b then
  b=CreateFrame("Button",nil,canvas);b.texture=b:CreateTexture(nil,"OVERLAY");b.texture:SetAllPoints()
  b.dot=b:CreateTexture(nil,"OVERLAY");b.dot:SetSize(5,5);b.dot:SetPoint("CENTER")
  b.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask");b.dot:SetVertexColor(.2,.85,.75,.9)
 end
 b.dot:Hide()
 b:SetParent(canvas);b:SetSize(size,size)
 b:SetPoint("CENTER",canvas,"TOPLEFT",canvas:GetWidth()*x,-canvas:GetHeight()*y)
 b.texture:SetTexture(shape=="contact" and "Interface\\Minimap\\Tracking\\TrivialQuests" or "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
 b.texture:SetVertexColor(unpack(color))
 local page=1;local pageSize=14;local pages=math.max(1,math.ceil(#details/pageSize))
 local function tooltip(self)
  if not GameTooltip then return end
  M.tooltipOwner=self;GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:AddLine(title,.75,.48,1)
  if GameTooltip.ClearLines then GameTooltip:ClearLines();GameTooltip:AddLine(title,.75,.48,1) end
  for i=(page-1)*pageSize+1,math.min(page*pageSize,#details) do GameTooltip:AddLine(details[i],1,1,1,true) end
  if pages>1 then GameTooltip:AddLine("Mouse wheel: page "..page.."/"..pages,.6,.8,1) end
  GameTooltip:Show()
 end
 b:SetScript("OnEnter",tooltip)
 b:EnableMouseWheel(pages>1)
 b:SetScript("OnMouseWheel",function(self,delta) page=math.max(1,math.min(pages,page-(delta>0 and 1 or -1)));tooltip(self) end)
 b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end;M.tooltipOwner=nil end)
 b:Show();self.active[#self.active+1]=b
 return b
end
function M:DrawCorridors(canvas,data)
 if WP.char.showRoutes~=true or type(canvas.CreateLine)~="function" then return end
 -- A small selected set, with omissions disclosed. Every line is schematic.
 for i,p in ipairs(data.links) do
  if i>24 then break end
  local inferred=p.kind=="Inferred chain transition"
  local segments=inferred and 5 or 1
  for j=1,segments do
   local start=(j-1)/segments;local finish=inferred and (j-.45)/segments or 1
   local line=table.remove(self.freeLines) or canvas:CreateLine(nil,"OVERLAY")
   line:SetParent(canvas);line:SetThickness(inferred and 1 or 1.5)
   if inferred then line:SetColorTexture(.3,.8,.85,.45) else line:SetColorTexture(.75,.42,1,.35) end
   line:SetStartPoint("CENTER",canvas,"TOPLEFT",(p.a.x+(p.b.x-p.a.x)*start)*canvas:GetWidth(),-(p.a.y+(p.b.y-p.a.y)*start)*canvas:GetHeight())
   line:SetEndPoint("CENTER",canvas,"TOPLEFT",(p.a.x+(p.b.x-p.a.x)*finish)*canvas:GetWidth(),-(p.a.y+(p.b.y-p.a.y)*finish)*canvas:GetHeight())
   line:Show();self.lines[#self.lines+1]=line
  end
  local notes={"Schematic connection; NOT a verified walkable road or enemy route.",
   "Nearest supported endpoint shown; other objective sites may exist.",
   "Displaying up to 24 of "..#data.links.." deduplicated connections."}
  if p.other then notes[#notes+1]="Prerequisite quest #"..p.other.."; progression is conditional." end
  for _,s in ipairs(WP.modules.Hotspots:QuestNotes(p.quests)) do notes[#notes+1]=s end
  self:Pin(canvas,(p.a.x+p.b.x)/2,(p.a.y+p.b.y)/2,5,{.65,.45,1,.7},p.kind,notes)
 end
end
function M:Refresh()
 self:Clear()
 local canvas=validCanvas()
 if not canvas or not WP.char or type(WorldMapFrame.GetMapID)~="function" then return end
 local ok,id=pcall(WorldMapFrame.GetMapID,WorldMapFrame);if not ok then return end
 local zone=mapZone[id];if not zone then return end
 local low,high=WP.char.levelMin,WP.char.levelMax
 local model=WP.modules.Hotspots;local data=model:Get(zone,low,high)
 self:DrawCorridors(canvas,data)
 for _,h in ipairs(data.cells) do
  if WP.char.showHeat~=false or (WP.char.showAreaCoverage~=false and next(h.objectives)) then
   local notes={h.confidence,
    string.format("Heuristic score %d/100 (not probability); quest levels %d-%d",h.score,low,high),
    string.format("Objective units %.1f; contact quests %d; nearby matching contacts %d",h.objectiveUnits,h.contactCount,h.proximity),
    "Distinct quests: "..h.questCount.."; chain overlaps discounted: "..h.chainOverlap,
    "12x12 coverage cell; source point density does not multiply score.",
    "Quest prerequisites, class, reputation and completion are not observed."}
   for _,s in ipairs(model:QuestNotes(h.quests)) do notes[#notes+1]=s end
   local heatPin
   if WP.char.showHeat~=false then
    local size=h.intensity=="High" and 22 or h.intensity=="Medium" and 16 or 10
    local alpha=h.intensity=="High" and .55 or h.intensity=="Medium" and .38 or .22
    heatPin=self:Pin(canvas,h.x,h.y,size,{.70,.32,1,alpha},h.intensity.." static quest activity",notes)
   end
   if WP.char.showAreaCoverage~=false and next(h.objectives) then
    if heatPin then heatPin.dot:Show()
    else self:Pin(canvas,h.x,h.y,5,{.2,.85,.75,.8},"Objective coverage cell",notes) end
   end
  end
 end
 if WP.char.showQuest~=false then
  -- Cluster close contacts; retain every associated quest in the tooltip.
  local groups,order={},{}
  for _,p in ipairs(data.contacts) do
   local key=math.floor(p.x*40)..":"..math.floor(p.y*40)
   local g=groups[key]
   if not g then g={x=p.x,y=p.y,quests={},roles={}};groups[key]=g;order[#order+1]=key end
   for q,name in pairs(p.quests) do g.quests[q]=name end
   for role in pairs(p.roles) do g.roles[role]=true end
  end
  table.sort(order)
  for _,key in ipairs(order) do
   local p=groups[key]
   local notes={"Source-backed quest contacts; nearby contacts grouped.",
    (p.roles.giver and "Quest giver" or "")..(p.roles["turn-in"] and " / Turn-in" or ""),
    "Potential availability only; prerequisites and completion unknown."}
   for _,s in ipairs(model:QuestNotes(p.quests)) do notes[#notes+1]=s end
   self:Pin(canvas,p.x,p.y,12,{1,.84,.3,.95},"Quest contact",notes,"contact")
  end
 end
end
function M:Initialize()
 if self.initialized then return end
 self.initialized=true
 if not WorldMapFrame then WP:Log("World map frame unavailable; overlay disabled");return end
 WorldMapFrame:HookScript("OnShow",function() M:Refresh() end)
 WorldMapFrame:HookScript("OnHide",function() M:Clear() end)
 local elapsed=0;local lastID,lastW,lastH,lastScale
 WorldMapFrame:HookScript("OnUpdate",function(_,dt)
  elapsed=elapsed+(dt or 0);if elapsed<.15 then return end;elapsed=0
  local c=validCanvas();if not c then if #M.active>0 then M:Clear() end;return end
  local id=WorldMapFrame:GetMapID();local w,h=c:GetWidth(),c:GetHeight();local scale=c:GetEffectiveScale()
  if id~=lastID or w~=lastW or h~=lastH or scale~=lastScale then
   lastID,lastW,lastH,lastScale=id,w,h,scale;M:Refresh()
  end
 end)
 self:Refresh()
end
