local passed = 0
local function check(value, message)
    assert(value, message); passed = passed + 1
end
local clock, combat, units, macros, writes, messages = 0, false, {}, {}, 0, {}
local frames, sounds = {}, 0
local methods = {}
function methods:SetScript(k, fn) self.scripts[k] = fn end
function methods:GetScript(k) return self.scripts[k] end
function methods:RegisterEvent(k) self.events[k] = true end
function methods:CreateFontString() return CreateFrame('FontString') end
function methods:CreateTexture() return CreateFrame('Texture') end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text or '' end
function methods:SetChecked(t) self.checked = t end
function methods:GetChecked() return self.checked end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown ~= false end
function methods:SetShown(v) self.shown = v end
function methods:SetSize(x,y) self.width,self.height = x,y end
function methods:SetWidth(x) self.width = x end
function methods:SetHeight(x) self.height = x end
function methods:GetWidth() return self.width or 140 end
function methods:GetHeight() return self.height or 140 end
function methods:GetFrameLevel() return 1 end
function methods:GetCenter() return 500,500 end
function methods:GetEffectiveScale() return 1 end
local noop = function() end
for _, key in ipairs({'SetPoint','SetJustifyH','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetFontObject',
 'SetWordWrap','SetTextColor','SetFrameStrata','SetFrameLevel','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag',
 'RegisterForClicks','StartMoving','StopMovingOrSizing','SetAutoFocus','SetMaxLetters','ClearFocus','SetFocus','SetAllPoints',
 'SetMultiLine','HighlightText','ClearAllPoints','SetOwner','AddLine'}) do methods[key] = noop end
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({scripts={},events={},name=name,template=template}, {__index=methods})
    frames[#frames+1] = f
    if name then _G[name] = f end
    return f
end
UIParent, Minimap, GameTooltip = CreateFrame('Frame'), CreateFrame('Frame'), CreateFrame('Frame')
DEFAULT_CHAT_FRAME = {AddMessage=function(_, text) messages[#messages+1]=text end}
GetBuildInfo = function() return '1.15.9','70576','',11509 end
GetNormalizedRealmName = function() return 'TestRealm' end
GetRealmName = function() return 'Test Realm' end
GetTime = function() return clock end
time = function() return 1780000000 + clock end
date = function() return '10/28 12:00' end
InCombatLockdown = function() return combat end
UnitExists = function(u) return units[u] ~= nil end
UnitName = function(u) local x=units[u]; if x then return x.name,x.realm end end
UnitGUID = function(u) return units[u] and units[u].guid end
UnitIsPlayer = function(u) return units[u].player end
UnitCanAttack = function(_,u) return units[u].hostile end
UnitIsDeadOrGhost = function(u) return units[u].dead end
PlaySound = function() sounds=sounds+1 end
GetSpellInfo = function(s) return s == 'Mind Blast' and s or nil end
C_NamePlate = {GetNamePlates=function() return {} end}
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120,18
local W = {}
local function event(e,arg) W.events.scripts.OnEvent(W.events,e,arg) end
GetMacroInfo = function(i) if macros[i] then return macros[i].name,136116,macros[i].body end end
GetMacroIndexByName = function(n) for i,m in pairs(macros) do if m.name==n then return i end end; return 0 end
GetNumMacros = function() local n=0;for i in pairs(macros) do if i>120 then n=n+1 end end;return 0,n end
CreateMacro = function(name,icon,body,char)
    assert(not combat,'protected macro creation in combat'); assert(char); writes=writes+1
    for i=121,138 do if not macros[i] then macros[i]={name=name,body=body}; event('UPDATE_MACROS'); return i end end
end
EditMacro = function(i,name,icon,body)
    assert(not combat,'protected macro edit in combat');writes=writes+1;macros[i]={name=name,body=body};event('UPDATE_MACROS');return i
end
PickupMacro = function(i) assert(not combat); _G.picked=i end
StaticPopupDialogs, SlashCmdList = {},{}
StaticPopup_Show = function(k) _G.popup=k end
GetCursorPosition = function() return 500,500 end
math.atan2 = math.atan2 or function(y,x) return math.atan(y/x) end
local files = {'Core','Compat','Database','Targeting','Macros','Alerts','Detection','UI','Minimap','Config'}
for _,file in ipairs(files) do
    local chunk,err=loadfile(file..'.lua');check(chunk, file..' syntax: '..tostring(err));chunk('VoidMarkWarpath',W)
end
event('ADDON_LOADED','OtherAddon');check(not W.DB.data,'other addon ignored')
event('ADDON_LOADED','VoidMarkWarpath');event('PLAYER_LOGIN')
check(W.UI.frame and W.Minimap.button,'standalone UI boots')
check(W.DB.data.settings.mode=='target','default target only')
local a=assert(W.DB:Add('Ganktastic'));check(a.realm=='testrealm','local realm normalized')
check(W.Macros.armed==a.key,'first target automatically armed')
W.Macros.armed,W.Macros.armedName=nil,nil; W.Macros:Restore()
check(W.Macros.armed==a.key and W.Macros.armedName=='Ganktastic','reload restores last-owned native macro identity')
check(macros[121].body=='#showtooltip\n/targetexact Ganktastic-testrealm','realm-qualified exact macro')
check(not W.Macros.error,'synchronous UPDATE_MACROS does not break ownership')
local e,err=W.DB:Add('ganktastic-Test Realm');check(not e and err,'duplicate case and realm spaces rejected')
for _,bad in ipairs({'','A','Name\n/cast Mind Blast','Name;Other','Name[foo]','Name/Other','Name|Hlink','Name123'}) do
 check(not W.DB:Add(bad),'invalid input rejected: '..bad)
end
local b=assert(W.DB:Add('Enemyrogue-Other Realm'));check(W.DB:Select(b.key),'select second target')
check(W.Macros.armed==b.key,'macro switches target')
W.DB:Init();check(W.DB.data.active==b.key and #W.DB.data.entries==2,'reload retains list/selection')
check(W.Targeting:SetMode('spell','Mind Blast'),'spell mode configured')
local body=assert(W.Macros:Build())
check(body=='#showtooltip Mind Blast\n/cleartarget\n/targetexact Enemyrogue-otherrealm\n/stopmacro [noexists]\n/cast [@target,harm,nodead] Mind Blast','spell macro exact order and explicit target')
-- Independent small macro semantics model: failure leaves existing target unless cleared.
local function press(text,available,prior)
 local target,cast=prior,nil
 for line in text:gmatch('[^\n]+') do
  if line=='/cleartarget' then target=nil
  elseif line:match('^/targetexact ') then target=available or target
  elseif line=='/stopmacro [noexists]' and not target then break
  elseif line:match('^/cast ') and target and target.hostile and not target.dead then cast=target.name end
 end
 return target,cast
end
local _,hit=press(body,nil,{name='UnrelatedEnemy',hostile=true,dead=false});check(hit==nil,'failed target cannot cast at prior enemy in macro model')
local _,hit2=press(body,{name='Enemyrogue',hostile=true,dead=false},{name='Wrong',hostile=true});check(hit2=='Enemyrogue','success casts at exact target in model')
local _,hit3=press(body,{name='Enemyrogue',hostile=true,dead=true},nil);check(not hit3,'dead target not cast on')
local _,hit4=press(body,{name='Enemyrogue',hostile=false,dead=false},nil);check(not hit4,'friendly target not cast on')
check(not W.Targeting:SetMode('spell','Mind Blast\n/startattack'),'spell injection rejected')
check(not W.Targeting:SetMode('spell','Mind Blast;Smite'),'spell conditional injection rejected')
W.DB.data.settings.spell=string.rep('X',100);local long=assert(W.DB:Add(string.rep('A',48)..'-'..string.rep('R',49)))
W.DB:Select(long.key);check(W.Macros.error and W.Macros.armed==b.key,'overlong macro leaves previous macro intact with error')
W.Targeting:SetMode('target');W.DB:Select(a.key)
local before=writes;combat=true;W.DB:Select(b.key)
check(writes==before and W.Macros.pending and W.Macros.armed==a.key,'combat queues target change without protected writes')
W.UI:Refresh();check(W.UI.status:GetText():find('COMBAT QUEUED',1,true),'queued warning visible')
check(not W.Macros:Pickup(),'pickup blocked in combat')
combat=false;event('PLAYER_REGEN_ENABLED');check(W.Macros.armed==b.key and not W.Macros.pending,'queued target applied after combat')
combat=true;W.DB:Remove(b.key);check(W.Macros.armed==b.key and W.Macros.pending,'removing active in combat retains honest applied key')
W.UI:Refresh();check(W.UI.status:GetText():find('Enemyrogue',1,true),'combat removal warning retains old applied target name')
combat=false;event('PLAYER_REGEN_ENABLED');check(not W.Macros.armed and macros[121].body=='#showtooltip\n/stopmacro','removal disarms native macro after combat')
W.DB:Select(a.key);check(W.Macros:Pickup() and picked==121,'native macro pickup')
macros[121].body='/say user customization';event('UPDATE_MACROS');check(W.Macros.error,'external macro edit detected')
W:Changed();check(macros[121].body=='/say user customization' and W.Macros.index==122,'edited macro preserved; separate name allocated')
local saved=WarpathCharDB
WarpathCharDB={entries={},settings={}};W.DB:Init()
for i=121,138 do macros[i]={name='Other'..i,body='/say test'} end
local full=assert(W.DB:Add('Fullslots'));check(W.Macros.error and W.Macros.error:find('full'),'macro limit handled')
WarpathCharDB=saved;W.DB:Init();macros={};W:Changed()
-- Detection: only exposed tokens, exact identity and hostile filtering.
local function player(name,guid,realm,dead,hostile)
 return {name=name,guid=guid,realm=realm,dead=dead or false,hostile=hostile~=false,player=true}
end
W.Detection:Reset();W.DB.data.history={};clock=100
units.mouseover=player('Ganktastically','Player-2');W.Detection:Tick();check(#W.DB.data.history==0,'substring does not match')
units.mouseover=player('Ganktastic','Player-2','OtherRealm');W.Detection:Tick();check(#W.DB.data.history==0,'foreign realm does not match local name')
units.mouseover=player('Ganktastic','Player-1',nil,false,false);W.Detection:Tick();check(#W.DB.data.history==0,'friendly ignored')
units.mouseover=player('Ganktastic','Player-1');event('UPDATE_MOUSEOVER_UNIT');check(#W.DB.data.history==1 and W.DB.data.history[1].kind=='seen','confirmed mouseover detection')
for i=1,50 do clock=clock+.25;W.Detection:Tick() end
check(#W.DB.data.history==1,'continuous visibility no repeated alert after cooldown')
units.target=units.mouseover;event('PLAYER_TARGET_CHANGED');check(#W.DB.data.history==2 and W.DB.data.history[2].kind=='acquired','new target acquisition separate evidence')
check(W.Detection:Status(a.key):find('Target Acquired',1,true),'acquired status')
units.target.dead=true;event('UNIT_FLAGS','target');check(W.Detection:Status(a.key):find('dead',1,true),'dead visible status')
units.target.dead=false;event('UNIT_FLAGS','target');check(W.DB.data.history[#W.DB.data.history].kind=='alive','continuously observed dead-to-alive transition')
check(W.DB:Get(a.key),'entry retained after detection')
units.target.dead=true;W.Detection:Tick();units={};W.Detection:Tick();clock=clock+4
units.mouseover=player('Ganktastic','Player-1');W.Detection:Tick();check(W.DB.data.history[#W.DB.data.history].kind=='seen','reacquisition not inferred resurrection')
local last=#W.DB.data.history;units={};W.Detection:Tick();clock=clock+3;units.mouseover=player('Ganktastic','Player-1');W.Detection:Tick()
check(#W.DB.data.history==last,'per-kind cooldown suppresses rapid reacquisition')
units={};W.Detection:Tick();clock=clock+11;units.nameplate1=player('Ganktastic','Player-1');event('NAME_PLATE_UNIT_ADDED','nameplate1')
check(W.DB.data.history[#W.DB.data.history].source=='nameplate1','nameplate supported')
event('NAME_PLATE_UNIT_REMOVED','nameplate1');check(not W.Detection.states[a.key].present,'nameplate removed resets visible state')
W.DB:Enable(a.key,false);W.Detection:Tick();check(not W.Detection.states[a.key],'disabled entry ignored')
W.DB:Enable(a.key,true)
local npc=assert(W.DB:Add('Scarlet Scout','npc'));units={mouseover={name='Scarlet Scout',guid='Creature-1',dead=false,hostile=true,player=false}}
local n=#W.DB.data.history;W.Detection:Tick();check(#W.DB.data.history==n,'NPC tracking default off')
W.DB.data.settings.npcs=true;W.Detection:Tick();check(#W.DB.data.history==n+1,'optional NPC detection')
W.DB.data.settings.historyLimit=2
for i=1,4 do clock=clock+20;W.Alerts:Notify(npc,'seen',{unit='mouseover',dead=false}) end
check(#W.DB.data.history==2,'history bounded')
W.DB.data.settings.historyLimit=0;W.DB.data.history={};clock=clock+20;W.Alerts:Notify(npc,'seen',{unit='mouseover'});check(#W.DB.data.history==0,'history can be disabled')
-- Secret identities must be skipped without name inspection or comparison.
local oldName=UnitName;local secret={}
issecretvalue=function(v) return v==secret end
UnitName=function() return secret end
check(not W.Compat:Snapshot('mouseover'),'secret unit name skipped')
UnitName=oldName;issecretvalue=nil
local throwing=UnitGUID;UnitGUID=function() error('restricted API') end
check(not W.Compat:Snapshot('mouseover'),'restricted API failure safely skipped');UnitGUID=throwing
W.UI:Settings();check(W.UI.settings:IsShown(),'settings opens')
W.UI:CopyMacro();check(W.UI.copy:IsShown(),'copy popup opens')
W.UI.frame.scripts.OnEnter(W.UI.frame);W.UI.frame.scripts.OnLeave(W.UI.frame)
W.UI.center:Hide();W.UI:CenterAlert('test');clock=clock+3;W.UI:Animate();check(not W.UI.center:IsShown(),'center alert expires')
W.UI:Pulse();clock=clock+1;W.UI:Animate();check(not W.UI.pulseUntil,'pulse expires')
W.DB.data.settings.collapsed=true;W.UI:Refresh();check(W.UI.frame.height==81 and not W.UI.body:IsShown(),'collapse persists')
W.UI:Toggle();check(not W.UI.frame:IsShown(),'toggle hides')
W:Command('reset');check(popup=='WARPATH_RESET','reset requires confirmation')
StaticPopupDialogs.WARPATH_RESET.OnAccept();check(#W.DB.data.entries==0 and not W.DB.data.active,'confirmed reset clears watchlist')
-- Re-run compatibility identity against Forever interface, independent of project ID.
GetBuildInfo=function() return '1.60.1','70532','',16001 end
assert(loadfile('Compat.lua'))('VoidMarkWarpath',W)
check(W.Compat.forever and not W.Compat.era,'Forever detected by interface')
Constants={MacroConsts={MAX_ACCOUNT_MACROS=150,MAX_CHARACTER_MACROS=30}}
local accountMax,charMax=W.Compat:MacroLimits();check(accountMax==150 and charMax==30,'modern macro limits prefer namespaced constants')
local ticks=0;local tick=W.Detection.Tick;W.Detection.Tick=function() ticks=ticks+1 end
event('UNIT_HEALTH','raid5');check(ticks==0,'unrelated unit health events do not scan observable tokens')
W.Detection.Tick=tick
print('PASS: '..passed..' Lua 5.1 assertions (mocked client; no in-game claims)')
