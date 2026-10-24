local _, WP = ...
local M=WP:Module("Hotspots",{cache={},cacheOrder={}})
local GRID=12
local function sortedKeys(t)
 local a={};for k in pairs(t) do a[#a+1]=k end;table.sort(a);return a
end
function M:LevelOverlap(q,low,high)
 -- Range is suggested QUEST level. Unknown levels are excluded, never fabricated.
 return type(q.level)=="number" and q.level>=low and q.level<=high
  and type(q.required)=="number" and q.required<=high
  and (not q.maxLevel or q.maxLevel>=low)
end
function M:SetLevels(low,high)
 low,high=tonumber(low),tonumber(high)
 if not low or not high or low%1~=0 or high%1~=0 or low<1 or high>60 or low>high then
  WP:Log("Use quest levels 1-60, minimum <= maximum.");return false
 end
 WP.char.levelMin=low;WP.char.levelMax=high
 WP:Safe("MapOverlay","Refresh");WP:Safe("UI","Refresh")
 return true
end
function M:Build(zone,low,high)
 local data=WP.eraAudit or {quests={},points={}}
 local cells,contacts,byQuest={},{},{}
 local function cellAt(p)
  local cx,cy=math.min(GRID-1,math.floor(p.x*GRID)),math.min(GRID-1,math.floor(p.y*GRID))
  local key=cx..":"..cy
  if not cells[key] then cells[key]={key=key,zone=zone,x=(cx+.5)/GRID,y=(cy+.5)/GRID,
   quests={},objectives={},contacts={},count=0,questCount=0} end
  return cells[key]
 end
 for _,p in ipairs(data.points) do
  local q=data.quests[p.quest]
  if p.zone==zone and q and self:LevelOverlap(q,low,high) then
   local c=cellAt(p);c.quests[p.quest]=q.name;c.count=c.count+1
   byQuest[p.quest]=byQuest[p.quest] or {objective={},giver={},["turn-in"]={}}
   local list=byQuest[p.quest][p.role];list[#list+1]=p
   if p.role=="objective" then
    c.objectives[p.quest]=math.max(c.objectives[p.quest] or 0,p.item and .8 or 1)
   else
    c.contacts[p.quest]=true
    local key=p.kind..":"..p.entity..":"..p.x..":"..p.y
    local contact=contacts[key]
    if not contact then contact={key=key,x=p.x,y=p.y,quests={},roles={},entity=p.entity,kind=p.kind};contacts[key]=contact end
    contact.quests[p.quest]=q.name;contact.roles[p.role]=true
   end
  end
 end
 local out={}
 for _,key in ipairs(sortedKeys(cells)) do
  local c=cells[key];local units,nContacts,overlap=0,0,0
  for _,id in ipairs(sortedKeys(c.objectives)) do
   local q=data.quests[id];local linked=false
   for _,pre in ipairs(q.preAny or {}) do if c.objectives[pre] then linked=true end end
   for _,pre in ipairs(q.preAll or {}) do if c.objectives[pre] then linked=true end end
   units=units+c.objectives[id]*(linked and .5 or 1)
   if linked then overlap=overlap+1 end
  end
  for _ in pairs(c.contacts) do nContacts=nContacts+1 end
  local nearby={}
  for _,contact in pairs(contacts) do
   if (contact.x-c.x)^2+(contact.y-c.y)^2<=.07^2 then
    for id in pairs(contact.quests) do if c.objectives[id] then nearby[id]=true end end
   end
  end
  local proximity=0;for _ in pairs(nearby) do proximity=proximity+1 end
  for _ in pairs(c.quests) do c.questCount=c.questCount+1 end
  c.objectiveUnits=units;c.contactCount=nContacts;c.chainOverlap=overlap;c.proximity=proximity
  c.score=math.min(100,math.floor(20*units+5*math.min(nContacts,4)+3*math.min(proximity,3)+.5))
  c.intensity=c.score>=60 and "High" or c.score>=30 and "Medium" or "Low"
  c.confidence="Static source-backed estimate; availability/traffic not observed"
  out[#out+1]=c
 end
 table.sort(out,function(a,b) if a.score~=b.score then return a.score>b.score end return a.key<b.key end)
 local contactList={};for _,key in ipairs(sortedKeys(contacts)) do contactList[#contactList+1]=contacts[key] end
 local links,seen={},{}
 local function nearest(list,p)
  local best,d
  for _,v in ipairs(list or {}) do local nd=(v.x-p.x)^2+(v.y-p.y)^2;if not d or nd<d then best,d=v,nd end end
  return best
 end
 local function link(a,b,kind,id,other)
  if not a or not b or (a.x==b.x and a.y==b.y) then return end
  local key=string.format("%s:%.3f:%.3f:%.3f:%.3f",kind,a.x,a.y,b.x,b.y)
  if seen[key] then seen[key].quests[id]=data.quests[id].name;return end
  local v={a=a,b=b,kind=kind,quests={[id]=data.quests[id].name},other=other}
  seen[key]=v;links[#links+1]=v
 end
 for _,id in ipairs(sortedKeys(byQuest)) do
  local p=byQuest[id]
  for _,a in ipairs(p.giver) do
   link(a,nearest(p.objective,a) or nearest(p["turn-in"],a),"Quest relationship",id)
  end
  for _,b in ipairs(p["turn-in"]) do link(nearest(p.objective,b),b,"Quest relationship",id) end
  local q=data.quests[id]
  for _,list in ipairs({q.preAny or {},q.preAll or {}}) do
   for _,pre in ipairs(list) do
    local prev=byQuest[pre]
    if prev then for _,a in ipairs(prev["turn-in"]) do link(a,nearest(p.giver,a),"Inferred chain transition",id,pre) end end
   end
  end
 end
 return {cells=out,contacts=contactList,links=links}
end
function M:Get(zone,low,high)
 local key=zone..":"..low..":"..high
 if not self.cache[key] then
  self.cache[key]=self:Build(zone,low,high);self.cacheOrder[#self.cacheOrder+1]=key
  if #self.cacheOrder>8 then self.cache[table.remove(self.cacheOrder,1)]=nil end
 end
 return self.cache[key]
end
function M:Compute(zone,low,high) return self:Get(zone,low,high).cells end
function M:QuestNotes(quests)
 local out={}
 for _,id in ipairs(sortedKeys(quests)) do
  local q=WP.eraAudit.quests[id]
  if q then
   local line=q.name.." (#"..id..") - quest "..(q.level or "?")..", requires "..(q.required or "?")
   if q.classes and q.classes~=0 then line=line.."; class restricted" end
   if q.skill or q.minRep or q.maxRep then line=line.."; skill/reputation conditional" end
   if #(q.preAny or {})>0 then line=line.."; prior (any): "..table.concat(q.preAny,", ") end
   if #(q.preAll or {})>0 then line=line.."; prior (all): "..table.concat(q.preAll,", ") end
   if #(q.exclusive or {})>0 then line=line.."; exclusive alternatives" end
   out[#out+1]=line
   for _,s in ipairs(q.limitations or {}) do out[#out+1]=s end
  end
 end
 return out
end
