local _, WP = ...
local M=WP:Module("UI",{})
local function style(frame,r,g,b,a) if frame.SetBackdropColor then frame:SetBackdropColor(r,g,b,a) end end
function M:Create()
  if self.frame or type(CreateFrame)~="function" then return end
  local f=CreateFrame("Frame","VoidMarkWarpathWindow",UIParent,"BackdropTemplate")
  if not f.SetBackdrop and BackdropTemplateMixin and Mixin then Mixin(f,BackdropTemplateMixin) end
  f:SetSize(440,480)
  f:SetClampedToScreen(true)
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
  subtitle:SetText("Static Alliance quest estimates | sightings kept separate")
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
    if zone.key~="redridge" and zone.key~="duskwood" then b:Disable();b:SetText(zone.name.." (later)") end
    b:SetScript("OnClick",function() WP.char.zone=zone.key; M:Refresh() end)
    self.rows[#self.rows+1]=b
  end
  local info=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  info:SetPoint("TOPLEFT",f,"TOPLEFT",20,-223)
  info:SetWidth(400); info:SetJustifyH("LEFT")
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
 self.toggles={}
 self.toggles.showHeat=toggle("Static intensity","showHeat",19,-277)
 self.toggles.showQuest=toggle("Quest contacts","showQuest",220,-277)
 self.toggles.showRoutes=toggle("Connections","showRoutes",19,-302)
 self.toggles.showAreaCoverage=toggle("Objective cells","showAreaCoverage",220,-302)
 local levels=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 levels:SetPoint("TOPLEFT",f,"TOPLEFT",20,-333)
 levels:SetText("Suggested quest levels (inclusive)")
 self.levels=levels
 self.levelInputs={}
 for i,value in ipairs({WP.char.levelMin,WP.char.levelMax}) do
  local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
  edit:SetSize(50,24);edit:SetPoint("TOPLEFT",f,"TOPLEFT",25+(i-1)*70,-356)
  edit:SetAutoFocus(false);edit:SetNumeric(true);edit:SetMaxLetters(2);edit:SetText(tostring(value))
  edit:SetScript("OnEscapePressed",function(self) self:ClearFocus();M:Refresh() end)
  edit:SetScript("OnEnterPressed",function(self)
   WP.modules.Hotspots:SetLevels(M.levelInputs[1]:GetText(),M.levelInputs[2]:GetText());self:ClearFocus()
  end)
  self.levelInputs[i]=edit
 end
 local apply=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
 apply:SetSize(70,24);apply:SetPoint("TOPLEFT",f,"TOPLEFT",160,-356);apply:SetText("Apply")
 apply:SetScript("OnClick",function()
  WP.modules.Hotspots:SetLevels(M.levelInputs[1]:GetText(),M.levelInputs[2]:GetText())
  for _,e in ipairs(M.levelInputs) do e:ClearFocus() end
 end)
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
  note:SetPoint("TOPLEFT",f,"TOPLEFT",20,-396);note:SetWidth(400);note:SetJustifyH("LEFT")
  note:SetText("Purple: intensity | cyan: objectives | gold: contacts\nConnections are schematic, not verified roads.\nQuest availability is conditional; no player traffic inferred.")
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
  self.info:SetText("|cffbd7aff"..zone.name.."|r  |cffaaaaaaApprox. levels "..zone.min.."-"..zone.max.."|r\nSaved sightings: "..WP.modules.Observations:Count(zone.key).."   |  Objective hotspots: "..#WP.modules.Hotspots:Compute(zone.key,WP.char.levelMin or 15,WP.char.levelMax or 45).."")
  if self.levelInputs then self.levelInputs[1]:SetText(tostring(WP.char.levelMin));self.levelInputs[2]:SetText(tostring(WP.char.levelMax)) end
  for key,cb in pairs(self.toggles or {}) do cb:SetChecked(WP.char[key]~=false) end
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
