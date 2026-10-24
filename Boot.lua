local addonName, WP = ...
local function command(message)
  local arg=(message or ""):lower():match("^%s*(.-)%s*$")
  if arg=="help" then WP:Log("/warpath; /warpath zone redridge|duskwood; /warpath levels MIN MAX (quest levels); /warpath status");return end
  if arg=="map" then if WorldMapFrame then WorldMapFrame:Show() end;WP:Safe("MapOverlay","Refresh");return end
  local option=arg:match("^toggle%s+(%a+)$")
  if option and WP.char then local keys={heat="showHeat",quests="showQuest",routes="showRoutes",areas="showAreaCoverage"};local key=keys[option];if key then WP.char[key]=not(WP.char[key]~=false);WP:Safe("MapOverlay","Refresh");WP:Safe("UI","Refresh");WP:Log(option.."="..tostring(WP.char[key]));return end end
  local a,b=arg:match("^levels%s+(%d+)%s+(%d+)$")
  if a and b and WP.char then WP.modules.Hotspots:SetLevels(a,b);return end
  if arg=="status" then WP:Log("v"..WP.version.." | schema "..WP.schema.." | sightings "..WP.modules.Observations:Count().." | errors "..#WP.errors);return end
  local zone=arg:match("^zone%s+([%w_]+)$")
  if zone then
    if not WP.zoneByKey[zone] then WP:Log("Unknown zone. Try /warpath help.");return end
    WP.char.zone=zone; WP:Safe("UI","Toggle",true);return
  end
  WP:Safe("UI","Toggle")
end
SLASH_VOIDMARKWARPATH1="/warpath"
SLASH_VOIDMARKWARPATH2="/vmwarpath"
SlashCmdList["VOIDMARKWARPATH"]=command
local listener=CreateFrame("Frame")
listener:RegisterEvent("ADDON_LOADED")
listener:SetScript("OnEvent",function(self,event,name)
  if event=="ADDON_LOADED" and name==addonName then
    self:UnregisterEvent("ADDON_LOADED")
    WP:Safe("Storage","Initialize")
    if WP.char then
      WP:Safe("UI","Create")
      WP:Safe("MapOverlay","Initialize")
      WP:Safe("MinimapButton","Initialize")
      if WP.char.visible then WP:Safe("UI","Toggle",true) end
      WP:Log("Classic Era quest activity ready. /warpath to open.")
    end
  end
end)
