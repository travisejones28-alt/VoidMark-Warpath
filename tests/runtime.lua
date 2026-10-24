-- Lua 5.1 executable tests with a deliberately small WoW UI mock, not in-game QA.
local WP={};local created=0
local frame={};frame.__index=frame
function frame:SetScript(k,v) self.scripts[k]=v end
function frame:HookScript(k,v) local old=self.scripts[k];self.scripts[k]=function(...) if old then old(...) end;v(...) end end
function frame:Show() local was=self.shown;self.shown=true;if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function frame:Hide() local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function frame:IsShown() return self.shown end
function frame:SetSize(w,h) self.w=w;self.h=h end
function frame:GetSize() return self.w or 100,self.h or 100 end
function frame:GetWidth() return self.w or 100 end
function frame:GetHeight() return self.h or 100 end
function frame:GetEffectiveScale() return 1 end
function frame:GetFrameLevel() return 2 end
function frame:GetCenter() return 0,0 end
function frame:SetPoint(...) self.point={...} end
function frame:SetText(v) self.text=v end
function frame:GetText() return self.text end
function frame:SetChecked(v) self.checked=v end
function frame:GetChecked() return self.checked end
function frame:GetMapID() return self.mapID end
function CreateFrame(_,name,parent) created=created+1;local f=setmetatable({scripts={},shown=true,parent=parent},frame);if name then _G[name]=f end;return f end
function frame:CreateTexture() return CreateFrame('Texture') end
function frame:CreateFontString() return CreateFrame('FontString') end
function frame:CreateLine() return CreateFrame('Line') end
for _,method in ipairs({'SetParent','SetAllPoints','SetTexture','SetVertexColor','ClearAllPoints','SetFrameStrata','SetFrameLevel','EnableMouse','RegisterForClicks','RegisterForDrag','SetMovable','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetWidth','SetJustifyH','LockHighlight','UnlockHighlight','SetThickness','SetColorTexture','SetStartPoint','SetEndPoint','SetClampedToScreen','Disable','SetAutoFocus','SetNumeric','SetMaxLetters','ClearFocus','RegisterEvent','UnregisterEvent','SetOwner','AddLine','StartMoving','StopMovingOrSizing'}) do frame[method]=function() end end
UIParent=CreateFrame('Frame');Minimap=CreateFrame('Frame');Minimap:SetSize(200,160)
function frame:EnableMouseWheel() end
WorldMapFrame=CreateFrame('Frame');WorldMapFrame.mapID=1433
WorldMapFrame.ScrollContainer={Child=CreateFrame('Frame')};WorldMapFrame.ScrollContainer.Child:SetSize(1000,700)
GameTooltip=CreateFrame('Frame');SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
function ToggleWorldMap() if WorldMapFrame:IsShown() then WorldMapFrame:Hide() else WorldMapFrame:Show() end end
function GetCursorPosition() return 300,50 end
local entries={}
for line in io.lines('VoidMarkWarpath.toc') do if line:match('%.lua$') then entries[#entries+1]=line;assert(loadfile(line))('VoidMarkWarpath',WP) end end
local oldObservation={id=17,zone='redridge',x=.3,y=.4,observedAt=1,source='manual'}
VoidMarkWarpathDB={schema=1,observations={oldObservation},nextID=18}
VoidMarkWarpathCharDB={levelMin=15,levelMax=30,minimapAngle=225,showRoutes=false,position={x=15,y=20}}
WP.modules.Storage:Initialize();assert(WP.db.observations[1]==oldObservation and WP.db.nextID==18)
local model=WP.modules.Hotspots
local qCount=0;for id,q in pairs(WP.eraAudit.quests) do qCount=qCount+1;assert(q.required and q.level and q.races);assert(q.id==id) end
assert(qCount==108);assert(#WP.eraAudit.unresolved==0)
local dedupe={};local counts={}
for _,p in ipairs(WP.eraAudit.points) do
 assert(WP:ValidCoordinate(p.x) and WP:ValidCoordinate(p.y));assert(WP.eraAudit.quests[p.quest])
 local key=table.concat({p.quest,p.zone,p.role,p.kind,p.entity,p.x,p.y},':');assert(not dedupe[key],key);dedupe[key]=true
 local tag=p.zone..':'..p.role;counts[tag]=(counts[tag] or 0)+1
end
assert(counts['redridge:objective']==1213 and counts['duskwood:objective']==1274)
for _,zone in ipairs({'redridge','duskwood'}) do
 for _,range in ipairs({{1,60},{15,20},{21,30},{31,40},{60,60}}) do
  local d=model:Get(zone,range[1],range[2]);local seen={}
  for _,c in ipairs(d.cells) do
   assert(not seen[c.key]);seen[c.key]=true;assert(c.score>=0 and c.score<=100)
   for id in pairs(c.quests) do assert(model:LevelOverlap(WP.eraAudit.quests[id],range[1],range[2])) end
  end
  assert(#d.cells<=144);assert(model:Get(zone,range[1],range[2])==d)
  print(zone,range[1],range[2],'cells',#d.cells,'contacts',#d.contacts,'links',#d.links)
 end
end
assert(not model:LevelOverlap({level=25,required=18},15,20))
assert(#model.cacheOrder<=8)
assert(not model:LevelOverlap({required=18},15,20))
assert(not model:LevelOverlap({level=20,required=30},15,20))
assert(model:LevelOverlap({level=20,required=15},15,20))
local before=model:Build('redridge',1,60)
local originalCount=#WP.eraAudit.points
local repeated;for _,p in ipairs(WP.eraAudit.points) do if p.zone=='redridge' and p.role=='objective' then repeated=p;break end end
for i=1,50 do WP.eraAudit.points[#WP.eraAudit.points+1]=repeated end
local after=model:Build('redridge',1,60)
assert(#before.cells==#after.cells)
for i,c in ipairs(before.cells) do assert(c.key==after.cells[i].key and c.score==after.cells[i].score,'duplicate inflation') end
for i=#WP.eraAudit.points,originalCount+1,-1 do WP.eraAudit.points[i]=nil end
-- Geographic tests assert source-backed objectives, never add score boosts.
local cases={
 {'Northern Blackrock','redridge',.20,.05,.42,.22,20},
 {'NW gnolls','redridge',.15,.20,.40,.40,124},
 {'Northern approaches','redridge',.30,.15,.55,.42,89},
 {'Tower of Ilgalar','redridge',.75,.40,.87,.56,249},
 {'Stonewatch','redridge',.63,.48,.76,.64,19},
 {'South shore','redridge',.38,.57,.75,.82,127},
 {'Raven Hill cemetery','duskwood',.14,.25,.29,.45,58},
 {'Rotting Orchard worgen','duskwood',.58,.62,.73,.80,173},
 {'Southern worgen','duskwood',.56,.74,.70,.88,222},
 {'Ogres','duskwood',.30,.72,.42,.87,181},
}
for _,c in ipairs(cases) do
 local n=0
 for _,p in ipairs(WP.eraAudit.points) do if p.zone==c[2] and p.role=='objective' and p.quest==c[7] and p.x>=c[3] and p.x<=c[5] and p.y>=c[4] and p.y<=c[6] then n=n+1 end end
 assert(n>0,c[1]..' missing objective');print('Geography',c[1],n)
end
local darkshire=0;for _,p in ipairs(WP.eraAudit.points) do if p.zone=='duskwood' and p.role~='objective' and p.x>.70 and p.x<.80 and p.y>.40 and p.y<.52 then darkshire=darkshire+1 end end;assert(darkshire>0)
WP.modules.UI:Create();local overlay=WP.modules.MapOverlay;overlay:Initialize()
assert(#overlay.active>0 and #WP.errors==0)
local allocated=created;for i=1,10 do overlay:Refresh() end;assert(created==allocated,'frame leak')
for _,pin in ipairs(overlay.active) do pin.scripts.OnEnter(pin);pin.scripts.OnMouseWheel(pin,-1);pin.scripts.OnLeave(pin) end
assert(model:SetLevels(15,20));assert(WP.modules.UI.levelInputs[1]:GetText()=='15')
assert(not model:SetLevels(30,20));assert(WP.char.levelMin==15)
WP.char.showHeat=false;WP.char.showAreaCoverage=false;WP.char.showQuest=false;WP.char.showRoutes=false;overlay:Refresh();assert(#overlay.active==0)
WP.char.showAreaCoverage=true;overlay:Refresh();assert(#overlay.active>0)
WP.char.showAreaCoverage=false;WP.char.showRoutes=true;overlay:Refresh();assert(#overlay.lines>0)
WorldMapFrame:Hide();assert(#overlay.active==0 and #overlay.lines==0)
overlay:Refresh();assert(#overlay.active==0)
WorldMapFrame:Show();assert(#overlay.active>0)
WorldMapFrame.mapID=999;overlay:Refresh();assert(#overlay.active==0)
WorldMapFrame.mapID=1431;WP.char.showHeat=true;WorldMapFrame.ScrollContainer.Child:SetSize(800,600);WorldMapFrame.scripts.OnUpdate(WorldMapFrame,.2);assert(#overlay.active>0)
local mini=WP.modules.MinimapButton;mini:Initialize()
for _,angle in ipairs({0,45,90,135,180,225,270,315}) do
 WP.char.minimapAngle=angle;mini:Position();local p=mini.button.point
 assert(math.abs(math.abs(p[4])-109)<.01 or math.abs(math.abs(p[5])-89)<.01,'square perimeter')
end
Minimap:SetSize(300,200);WP.char.minimapAngle=0;mini.button.scripts.OnUpdate(mini.button,.6);assert(mini.button.point[4]==159)
mini.button.scripts.OnDragStart(mini.button);mini.button.scripts.OnDragStop(mini.button)
local visible=WP.modules.UI.frame:IsShown();mini.button.scripts.OnClick(mini.button,'LeftButton');assert(WP.modules.UI.frame:IsShown()==visible)
mini.button.scripts.OnMouseDown(mini.button);mini.button.scripts.OnClick(mini.button,'LeftButton');assert(WP.modules.UI.frame:IsShown()~=visible)
assert(WP.db.observations[1]==oldObservation and #WP.errors==0)
print('PASS: Lua 5.1 manifest load, data, levels, scoring, geography, UI, cleanup, pool reuse, minimap and saved data')
