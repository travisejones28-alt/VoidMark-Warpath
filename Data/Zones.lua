local _, WP = ...
WP.zones = {
  {id=44, key="redridge", name="Redridge Mountains", min=15, max=25},
  {id=10, key="duskwood", name="Duskwood", min=18, max=30},
  {id=267, key="hillsbrad", name="Hillsbrad Foothills", min=20, max=35},
  {id=11, key="wetlands", name="Wetlands", min=20, max=30},
  {id=33, key="stranglethorn", name="Stranglethorn Vale", min=30, max=45},
  {id=45, key="arathi", name="Arathi Highlands", min=30, max=40},
}
WP.zoneByKey = {}
for _, zone in ipairs(WP.zones) do WP.zoneByKey[zone.key] = zone end
