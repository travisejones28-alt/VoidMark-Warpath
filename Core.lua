local addonName, WP = ...
WP.name = addonName
WP.version = "0.2.3"
WP.schema = 1
WP.modules = {}
WP.colors = {purple={0.57,0.29,0.85,1}, panel={0.055,0.045,0.085,0.96}, accent={0.75,0.50,1,1}}
WP.errors = {}
function WP:Log(message)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffae77ffWarpath:|r "..tostring(message)) end
end
function WP:Safe(module, method, ...)
  local m = self.modules[module]
  if not m or type(m[method])~="function" then return false end
  local ok, result = pcall(m[method], m, ...)
  if not ok then
    self.errors[#self.errors+1] = {module=module, message=tostring(result)}
    self:Log(module.." error: "..tostring(result))
    return false
  end
  return true, result
end
function WP:Module(name, value)
  self.modules[name] = value
  return value
end
function WP:Optional(name)
  if type(IsAddOnLoaded)=="function" then
    local ok, loaded = pcall(IsAddOnLoaded, name)
    return ok and loaded == true
  end
  if C_AddOns and type(C_AddOns.IsAddOnLoaded)=="function" then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and loaded == true
  end
  return false
end
