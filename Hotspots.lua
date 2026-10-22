local _, WP = ...
local M=WP:Module("Hotspots",{})
function M:LevelOverlap(p,low,high)
 local required=p.required or p.min
 -- Unknown quest levels must not silently be treated as level 60.
 if type(required)~="number" or type(p.level)~="number" then return true end
 return p.level>=low-5 and required<=high
end
function M:Compute(zone,low,high)
 -- Per-quest grids preserve source quest level and let the slider filter both zones.
 if WP.eraQuestCells and #WP.eraQuestCells>0 then
  local cells={}
  for _,p in ipairs(WP.eraQuestCells) do
   if p.zone==zone and self:LevelOverlap(p,low,high) then
    local key=p.cx..":"..p.cy
    local cell=cells[key]
    if not cell then
     cell={zone=zone,x=p.x,y=p.y,count=0,quests={},questCount=0}
     cells[key]=cell
    end
    cell.count=cell.count+p.count
    if not cell.quests[p.quest] then
     cell.quests[p.quest]=p.name
     cell.questCount=cell.questCount+1
    end
   end
  end
  local out={}
  for _,cell in pairs(cells) do
   if cell.count>=2 then
    cell.score=math.min(100,math.floor(10+12*cell.questCount+5*math.sqrt(cell.count)))
    cell.confidence="Level-filtered quest-associated spawn reference density; 16x16 grid"
    out[#out+1]=cell
   end
  end
  table.sort(out,function(a,b) if a.score==b.score then return a.count>b.count end return a.score>b.score end)
  return out
 end
 local cells={}
 for _,p in ipairs(WP.eraObjectives or {}) do
  if p.zone==zone and self:LevelOverlap(p,low,high) then
   local x=math.floor(p.x*20+.5)
   local y=math.floor(p.y*20+.5)
   local key=x..":"..y
   local cell=cells[key]
   if not cell then cell={zone=zone,x=0,y=0,count=0,quests={},entities={},points={}};cells[key]=cell end
   local dedupe=p.kind..":"..p.entity..":"..math.floor(p.x*10000+.5)..":"..math.floor(p.y*10000+.5)
   if not cell.entities[dedupe] then
    cell.entities[dedupe]=true
    cell.x=cell.x+p.x;cell.y=cell.y+p.y;cell.count=cell.count+1
   end
   if not cell.quests[p.quest] then cell.quests[p.quest]=p.name end
   cell.points[#cell.points+1]=p
  end
 end
 local out={}
 for _,cell in pairs(cells) do
  if cell.count>0 then
   cell.x=cell.x/cell.count;cell.y=cell.y/cell.count
   local quests=0;for _ in pairs(cell.quests) do quests=quests+1 end
   local density=math.max(0,math.min(50,tonumber(WP.char and WP.char.weights and WP.char.weights.density) or 15))
   local entities=math.max(0,math.min(50,tonumber(WP.char and WP.char.weights and WP.char.weights.contacts) or 7))
   cell.score=math.min(100,20+quests*density+cell.count*entities)
   cell.confidence="Static Era spawn estimate; unknown-level quests may be included"
   out[#out+1]=cell
  end
 end
 table.sort(out,function(a,b) if a.score==b.score then return a.x<b.x end return a.score>b.score end)
 return out
end
