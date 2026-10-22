local _, WP = ...
local M=WP:Module("MapOverlay",{})
local mapZone={[1433]="redridge",[1431]="duskwood"}
local function validCanvas()
 if not WorldMapFrame or not WorldMapFrame.ScrollContainer then return nil end
 local canvas=WorldMapFrame.ScrollContainer.Child
 if canvas and canvas:GetWidth()>0 and canvas:GetHeight()>0 then return canvas end
end
function M:Clear()
 for _,b in ipairs(self.active or {}) do b:Hide();b:ClearAllPoints();b:SetScript("OnEnter",nil);b:SetScript("OnLeave",nil);b:SetScript("OnClick",nil);self.free[#self.free+1]=b end
 self.active={}
 for _,line in ipairs(self.lines or {}) do line:Hide();self.freeLines[#self.freeLines+1]=line end
 self.lines={}
end
function M:Pin(canvas,x,y,size,color,title,details)
 if type(x)~="number" or type(y)~="number" or x<0 or x>1 or y<0 or y>1 then return end
 local b=table.remove(self.free)
 if not b then
  b=CreateFrame("Button",nil,canvas)
  b.texture=b:CreateTexture(nil,"OVERLAY")
  b.texture:SetAllPoints()
  b.texture:SetTexture("Interface\\Buttons\\WHITE8X8")
 end
 b:SetParent(canvas);b:SetSize(size,size)
 b:SetPoint("CENTER",canvas,"TOPLEFT",canvas:GetWidth()*x,-canvas:GetHeight()*y)
 b.texture:SetVertexColor(unpack(color))
 b:SetScript("OnEnter",function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:AddLine(title,.75,.48,1)
  for _,s in ipairs(details) do GameTooltip:AddLine(s,1,1,1,true) end
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
 b:SetScript("OnClick",function() WP:Safe("UI","Refresh") end)
 b:Show();self.active[#self.active+1]=b
end
function M:DrawCorridors(canvas,zone,low,high)
 if WP.char.showRoutes~=true then return end
 if type(canvas.CreateLine)~="function" then return end
 local anchors={}
 for _,point in ipairs(WP.questAnchors or {}) do
  if point.zone==zone and WP.modules.Hotspots:LevelOverlap(point,low,high) then anchors[point.id]=point end
 end
 -- Quest-associated contact links, not verified walkable paths.
 for _,pair in ipairs(WP.eraCorridors or {}) do
  if pair.zone==zone then
   local a,b=anchors[pair.from],anchors[pair.to]
   if a and b then
    local line=table.remove(self.freeLines) or canvas:CreateLine(nil,"OVERLAY")
    line:SetParent(canvas)
    line:SetThickness(2)
    line:SetColorTexture(.72,.4,1,.7)
    line:SetStartPoint("CENTER",canvas,"TOPLEFT",a.x*canvas:GetWidth(),-a.y*canvas:GetHeight())
    line:SetEndPoint("CENTER",canvas,"TOPLEFT",b.x*canvas:GetWidth(),-b.y*canvas:GetHeight())
    line:Show()
    self.lines[#self.lines+1]=line
   end
  end
 end
end
function M:Refresh()
 self:Clear()
 local canvas=validCanvas()
 if not canvas or not WP.char or type(WorldMapFrame.GetMapID)~="function" then return end
 local ok,id=pcall(WorldMapFrame.GetMapID,WorldMapFrame)
 if not ok then return end
 local zone=mapZone[id]
 if not zone then return end
 local low,high=WP.char.levelMin or 15,WP.char.levelMax or 45
 self:DrawCorridors(canvas,zone,low,high)
 -- Expanded source coverage independent of truncated per-entity reference samples.
 if WP.char.showAreaCoverage~=false then
  for _,a in ipairs(WP.questAreaCoverage or {}) do
   if a.zone==zone then
    self:Pin(canvas,a.x,a.y,21,{1,.58,.12,.84},a.label,{
     "Expanded QuestieDB spawn association coverage",
     "Quest-associated spawn rows in nearby area: "..a.count,
     a.quests,
     "Area-level reference; not player activity or confirmed objective",
     "Approximate center; area is wider than this marker"
    })
   end
  end
 end
 if WP.char.showHeat~=false then
  for _,h in ipairs(WP.modules.Hotspots:Compute(zone,low,high)) do
   local notes={"Static objective-density score "..h.score.."/100; NOT enemy probability",h.confidence,string.format("Classic Era coords: %.1f, %.1f",h.x*100,h.y*100)}
   for id,name in pairs(h.quests) do notes[#notes+1]=name.." (#"..id..")" end
   self:Pin(canvas,h.x,h.y,24,{.58,.18,.9,.65},"Quest-associated spawn hotspot",notes)
  end
 end
 if WP.char.showQuest~=false then
  local rendered={}
  for _,p in ipairs(WP.eraObjectives or {}) do
   if p.zone==zone and WP.modules.Hotspots:LevelOverlap(p,low,high) then
    local key=p.kind..":"..p.entity..":"..p.x..":"..p.y
    if not rendered[key] then
     rendered[key]=true
     self:Pin(canvas,p.x,p.y,9,{.20,.85,.75,.92},p.name,{
       "Quest-associated spawn (#"..p.quest..")",
       p.kind.." ID "..p.entity,
       p.levelKnown and ("Required level "..p.required.."; quest level "..p.level) or "Quest level unavailable in current metadata",
       string.format("QuestieDB Era: %.2f, %.2f",p.x*100,p.y*100),
       "Spawn reference; not live player activity"
     })
    end
   end
  end
  for _,p in ipairs(WP.questAnchors) do
   if p.zone==zone and WP.modules.Hotspots:LevelOverlap(p,low,high) then
    self:Pin(canvas,p.x,p.y,12,{1,.82,.26,.95},p.name,{p.questName.." (#"..p.quest..")",p.kind.." | Required level "..p.min,string.format("Classic Era coords %.1f, %.1f",p.x*100,p.y*100),"Contact reference only, not quest objective"})
   end
  end
 end
end
function M:Initialize()
 if self.initialized then return end
 self.initialized=true;self.active={};self.free={};self.lines={};self.freeLines={}
 if not WorldMapFrame then WP:Log("World map frame unavailable; map overlay disabled");return end
 WorldMapFrame:HookScript("OnShow",function() M:Refresh() end)
 WorldMapFrame:HookScript("OnHide",function() M:Clear() end)
 -- Watch map ID and layout dimensions, which change without OnMapChanged on some clients.
 local elapsed=0;local lastID,lastW,lastH
 WorldMapFrame:HookScript("OnUpdate",function(_,delta)
  elapsed=elapsed+(delta or 0)
  if elapsed<.15 then return end
  elapsed=0
  if not WorldMapFrame:IsShown() then return end
  local canvas=validCanvas()
  if not canvas or type(WorldMapFrame.GetMapID)~="function" then return end
  local ok,id=pcall(WorldMapFrame.GetMapID,WorldMapFrame)
  if not ok then return end
  local w,h=canvas:GetWidth(),canvas:GetHeight()
  if id~=lastID or w~=lastW or h~=lastH then
   lastID,lastW,lastH=id,w,h
   M:Refresh()
  end
 end)
 self:Refresh()
end
