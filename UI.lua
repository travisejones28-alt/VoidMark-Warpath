local _, WP = ...
local M=WP:Module("UI",{})
local function style(frame,r,g,b,a) if frame.SetBackdropColor then frame:SetBackdropColor(r,g,b,a) end end
function M:Create()
  if self.frame or type(CreateFrame)~="function" then return end
  local f=CreateFrame("Frame","VoidMarkWarpathWindow",UIParent,"BackdropTemplate")
  if not f.SetBackdrop and BackdropTemplateMixin and Mixin then Mixin(f,BackdropTemplateMixin) end
  f:SetSize(400,408)
  f:SetPoint("CENTER",UIParent,"CENTER",WP.char.position.x,WP.char.position.y)
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}}) end
  style(f,0.055,0.045,0.085,0.97)
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.57,0.29,0.85,1) end
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart",function(self) self:StartMoving() end)
  f:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local x,y=self:GetCenter()
    local ux,uy=UIParent:GetCenter()
    if x and ux then WP.char.position={point="CENTER",x=x-ux,y=y-uy} end
  end)
  local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  title:SetPoint("TOPLEFT",f,"TOPLEFT",18,-17)
  title:SetText("|cffbd7affVOIDMARK|r  WARPATH")
  local close=CreateFrame("Button",nil,f,"UIPanelCloseButton")
  close:SetPoint("TOPRIGHT",f,"TOPRIGHT",-3,-3)
  local subtitle=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-12)
  subtitle:SetText("Alliance quest activity | historical intelligence")
  local selector=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
  selector:SetPoint("TOPLEFT",f,"TOPLEFT",20,-83)
  selector:SetText("SELECT ZONE")
  self.rows={}
  for i,zone in ipairs(WP.zones) do
    local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b:SetSize(174,27)
    local column=(i-1)%2
    local line=math.floor((i-1)/2)
    b:SetPoint("TOPLEFT",f,"TOPLEFT",18+column*189,-105-line*35)
    b:SetText(zone.name)
    b:SetScript("OnClick",function() WP.char.zone=zone.key; M:Refresh() end)
    self.rows[#self.rows+1]=b
  end
  local info=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  info:SetPoint("TOPLEFT",f,"TOPLEFT",20,-223)
  info:SetWidth(360); info:SetJustifyH("LEFT")
  self.info=info
  local function toggle(text,key,x,y)
  local cb=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
  cb:SetSize(23,23);cb:SetPoint("TOPLEFT",f,"TOPLEFT",x,y)
  cb:SetChecked(WP.char[key]~=false)
  local label=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  label:SetPoint("LEFT",cb,"RIGHT",2,0);label:SetText(text)
  cb:SetScript("OnClick",function(self)
   WP.char[key]=self:GetChecked() and true or false
   WP:Safe("MapOverlay","Refresh")
  end)
  return cb
 end
 toggle("Hotspots","showHeat",19,-300)
 toggle("Quest contacts","showQuest",190,-300)
 local levels=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 levels:SetPoint("TOPLEFT",f,"TOPLEFT",20,-337)
 levels:SetText("Levels: "..(WP.char.levelMin or 15).."-"..(WP.char.levelMax or 45).."  (/warpath levels MIN MAX)")
 self.levels=levels
 local openMap=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
 openMap:SetSize(130,25)
 openMap:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-20,20)
 openMap:SetText("Open World Map")
 openMap:SetScript("OnClick",function()
   if type(ToggleWorldMap)=="function" then ToggleWorldMap()
   elseif WorldMapFrame then WorldMapFrame:Show() end
   WP:Safe("MapOverlay","Refresh")
 end)
 local note=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  note:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",20,56)
  note:SetText("Reference coordinates: Classic 1.12, not live sightings.")
  f:SetScript("OnHide",function() if WP.char then WP.char.visible=false end end)
  self.frame=f
  local wasVisible=WP.char.visible
  f:Hide()
  WP.char.visible=wasVisible
  self:Refresh()
end
function M:Refresh()
  if not self.info or not WP.char then return end
  local zone=WP.zoneByKey[WP.char.zone] or WP.zones[1]
  self.info:SetText("|cffbd7aff"..zone.name.."|r  |cffaaaaaaApprox. levels "..zone.min.."-"..zone.max.."|r\nSaved sightings: "..WP.modules.Observations:Count(zone.key).."   |  Curated hotspots: 0")
  if self.levels then self.levels:SetText("Levels: "..(WP.char.levelMin or 15).."-"..(WP.char.levelMax or 45).."  (/warpath levels MIN MAX)") end
  for i,b in ipairs(self.rows or {}) do
    local z=WP.zones[i]
    if z.key==zone.key then b:LockHighlight() else b:UnlockHighlight() end
  end
end
function M:Toggle(show)
  self:Create()
  if not self.frame then return end
  if show==nil then show=not self.frame:IsShown() end
  if show then self:Refresh();self.frame:Show() else self.frame:Hide() end
  WP.char.visible=show
end
