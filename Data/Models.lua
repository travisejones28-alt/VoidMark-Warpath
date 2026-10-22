local _, WP = ...
-- Normalized coordinates must be within 0..1. Empty collections are intentional.
-- Future curated quest sources must distinguish verified objectives from estimates.
WP.models = {
  objective = {"id","zone","questID","objectiveIndex","x","y","levelMin","levelMax","source","verified"},
  hotspot = {"id","zone","x","y","radius","reason","questIDs","score","source"},
  sighting = {"id","zone","x","y","player","level","observedAt","source","confidence"},
  route = {"id","zone","points","travelMode","source","score"},
  zone = {"id","key","name","min","max"}
}
WP.data = {objectives={},hotspots={},routes={}}
function WP:ValidCoordinate(n) return type(n)=="number" and n>=0 and n<=1 end
function WP:ValidSighting(s)
  if type(s)~="table" or type(s.zone)~="string" or not self.zoneByKey[s.zone] then return false end
  if not self:ValidCoordinate(s.x) or not self:ValidCoordinate(s.y) then return false end
  if type(s.observedAt)~="number" or s.observedAt<=0 then return false end
  if s.source~="manual" and s.source~="observed" then return false end
  if s.player~=nil and (type(s.player)~="string" or #s.player>60) then return false end
  return true
end
