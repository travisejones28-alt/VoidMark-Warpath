local _,WP=...
local M=WP:Module("Hotspots",{})
function M:LevelOverlap(p,low,high)
 return p.level>=low-5 and p.min<=high
end
function M:Compute(zone,low,high)
 local groups={}
 for _,p in ipairs(WP.questAnchors) do
  if p.zone==zone and self:LevelOverlap(p,low,high) then
   local key=math.floor(p.x*25+.5)..":"..math.floor(p.y*25+.5)
   local group=groups[key]
   if not group then group={zone=zone,x=0,y=0,count=0,quests={},points={}};groups[key]=group end
   group.x=group.x+p.x;group.y=group.y+p.y;group.count=group.count+1
   group.quests[p.quest]=true;table.insert(group.points,p)
  end
 end
 local result={}
 for _,group in pairs(groups) do
  group.x=group.x/group.count;group.y=group.y/group.count
  local q=0;for _ in pairs(group.quests) do q=q+1 end
  group.score=math.min(100,20+q*15+group.count*7)
  group.confidence="Low: Classic Era contact-only coverage"
  table.insert(result,group)
 end
 table.sort(result,function(a,b) return a.score>b.score end)
 return result
end
