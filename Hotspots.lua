local _, WP = ...
local M=WP:Module("Hotspots",{})
function M:LevelOverlap(p,low,high)
 return type(p.level)=="number" and type(p.min)=="number" and p.level>=low-5 and p.min<=high
end
function M:Compute(zone,low,high)
 local cells={}
 for _,p in ipairs(WP.questAnchors) do
  if p.zone==zone and self:LevelOverlap(p,low,high) then
   local key=math.floor(p.x*25+.5)..":"..math.floor(p.y*25+.5)
   local cell=cells[key]
   if not cell then cell={zone=zone,x=0,y=0,count=0,quests={},points={}};cells[key]=cell end
   cell.x=cell.x+p.x;cell.y=cell.y+p.y;cell.count=cell.count+1
   cell.quests[p.quest]=true;cell.points[#cell.points+1]=p
  end
 end
 local out={}
 for _,cell in pairs(cells) do
  cell.x=cell.x/cell.count;cell.y=cell.y/cell.count
  local unique=0;for _ in pairs(cell.quests) do unique=unique+1 end
  -- Contact-based reference score, not a PvP prediction confidence.
  cell.score=math.min(100,20+unique*15+cell.count*7)
  cell.confidence="Contact references only; objective coverage incomplete"
  out[#out+1]=cell
 end
 table.sort(out,function(a,b) if a.score==b.score then return a.x<b.x end return a.score>b.score end)
 return out
end
