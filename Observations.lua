local _, WP = ...
local M=WP:Module("Observations",{})
function M:Add(s)
  if WP.readOnly or not WP.db then return false, "storage unavailable" end
  if not WP:ValidSighting(s) then return false, "invalid sighting" end
  local id=WP.db.nextID
  WP.db.nextID=id+1
  local copy={id=id,zone=s.zone,x=s.x,y=s.y,player=s.player,level=s.level,observedAt=s.observedAt,source=s.source,confidence=s.confidence}
  table.insert(WP.db.observations,copy)
  return true,id
end
function M:Count(zone)
  if not WP.db then return 0 end
  local count=0
  for _,s in pairs(WP.db.observations) do
    if WP:ValidSighting(s) and (not zone or s.zone==zone) then count=count+1 end
  end
  return count
end
-- No automatic inference from /who, chat, friend list, or external addons.
