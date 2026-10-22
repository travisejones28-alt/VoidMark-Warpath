local _, WP = ...
local M = WP:Module("Storage", {})
local function defaults()
  return {schema=WP.schema, observations={}, nextID=1, migrations={}}
end
function M:Initialize()
  if type(VoidMarkWarpathDB)~="table" then VoidMarkWarpathDB=defaults() end
  local db=VoidMarkWarpathDB
  local version=tonumber(db.schema) or 0
  if version>WP.schema then
    WP:Log("Newer saved data detected; Warpath will not modify it.")
    WP.readOnly=true
    return
  end
  if type(db.observations)~="table" then db.observations={} end
  if type(db.migrations)~="table" then db.migrations={} end
  if type(db.nextID)~="number" or db.nextID<1 then db.nextID=1 end
  if version<1 then db.migrations[1]=true end
  db.schema=WP.schema
  if type(VoidMarkWarpathCharDB)~="table" then VoidMarkWarpathCharDB={} end
  local char=VoidMarkWarpathCharDB
  if not WP.zoneByKey[char.zone] then char.zone="redridge" end
  if type(char.levelMin)~="number" then char.levelMin=15 end
  if type(char.levelMax)~="number" then char.levelMax=45 end
  if type(char.weights)~="table" then char.weights={density=15,contacts=7} end
  if type(char.showHeat)~="boolean" then char.showHeat=true end
  if type(char.showQuest)~="boolean" then char.showQuest=true end
  if type(char.showRoutes)~="boolean" then char.showRoutes=false end
  if type(char.visible)~="boolean" then char.visible=false end
  if type(char.position)~="table" then char.position={point="CENTER", x=0, y=0} end
  WP.db=db
  WP.char=char
end
