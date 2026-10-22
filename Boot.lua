local addonName, WP = ...
local function command(message)
  local arg=(message or ""):lower():match("^%s*(.-)%s*$")
  if arg=="help" then WP:Log("/warpath - toggle window; /warpath zone redridge|duskwood|hillsbrad|wetlands|stranglethorn|arathi; /warpath status");return end
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
      if WP.char.visible then WP:Safe("UI","Toggle",true) end
      WP:Log("Phase 1 ready. /warpath to open.")
    end
  end
end)
