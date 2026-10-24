-- Run from repository root: lua tools/import_era.lua ../reference
-- Reference files pinned in tools/source.json. No runtime Questie dependency.
local dir=arg[1] or '../reference'
local db={}; local mods={QuestieDB=db}
QuestieLoader={ImportModule=function(_,n) return assert(mods[n],n) end}
for _,kind in ipairs({'Quest','Npc','Object','Item'}) do
 dofile(dir..'/classic'..kind..'DB.lua')
 local key=kind:lower()..'Data';db[key]=assert(loadstring(db[key]))()
end
local enum={Enum={}};assert(loadfile(dir..'/zones.lua'))('reference',enum)
for _,p in ipairs({'items','quests'}) do assert(loadfile(dir..'/'..p..'.lua'))('reference',enum) end
local env={questKeys=db.questKeys,npcKeys=db.npcKeys,objectKeys=db.objectKeys,itemKeys=db.itemKeys,zoneIDs=enum.Enum.zoneIDs}
for k,v in pairs(enum.Enum) do env[k]=v end
setmetatable(env,{__index=_G})
local fixes={};local applied={};local unresolved={}
for _,kind in ipairs({'Quest','NPC','Object','Item'}) do
 local f=assert(io.open(dir..'/classic'..kind..'Fixes.lua'));local text=f:read('*a');f:close()
 local blocks={}
 local base=text:match('^(.-)function %w+:LoadFactionFixes') or text
 local alliance=text:match('local %w+FixesAlliance = {(.-)\n    }') or ''
 for _,section in ipairs({base,alliance}) do
  local starts={}
  for pos,id in section:gmatch('()\n        %[(%d+)%] = {') do starts[#starts+1]={pos=pos,id=tonumber(id)} end
  for i,s in ipairs(starts) do
   local chunk=section:sub(s.pos,(starts[i+1] and starts[i+1].pos-1) or #section)
   local body=assert(chunk:match('= ({.-\n        }),'),'Unsupported correction formatting: '..kind..':'..s.id)
   blocks[s.id]=blocks[s.id] or {};table.insert(blocks[s.id],body)
  end
 end
 fixes[kind]=blocks
end
local function correct(kind,id)
 local key=kind:lower();local row=db[key..'Data'][id]
 if not row then return nil end
 local tag=kind..':'..id
 if applied[tag]~=nil then return row end
 applied[tag]=false
 for _,body in ipairs(fixes[kind][id] or {}) do
  local fn,err=loadstring('return '..body);if fn then setfenv(fn,env) end
  local ok,patch=false,nil;if fn then ok,patch=pcall(fn) end
  if ok then
   for field,value in pairs(patch) do row[field]=value end
   -- Lua drops explicit nil fields from table literals; preserve correction deletions.
   for key in body:gmatch('\n            %[([%w_]+%.[%w_]+)%] = nil,') do
    local keyfn=assert(loadstring('return '..key));setfenv(keyfn,env);row[assert(keyfn())]=nil
   end
   applied[tag]=true
  else unresolved[#unresolved+1]=tag..': '..tostring(err or patch) end
 end
 return row
end
local function serialize(v)
 if type(v)=='string' then return string.format('%q',v) end
 if type(v)~='table' then return tostring(v) end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end return type(a)<type(b) end)
 local out={'{'};for _,k in ipairs(keys) do out[#out+1]='['..serialize(k)..']='..serialize(v[k])..',' end
 out[#out+1]='}';return table.concat(out)
end
local zones={[44]='redridge',[10]='duskwood'}
local output={quests={},points={},unresolved=unresolved,corrections=applied};local seen={}
local function point(q,z,role,kind,id,x,y,item)
 if not zones[z] or type(x)~='number' or type(y)~='number' or x<0 or x>100 or y<0 or y>100 then return end
 local key=table.concat({q,z,role,kind,id,x,y},':')
 if seen[key] then return end;seen[key]=true
 output.points[#output.points+1]={quest=q,zone=zones[z],role=role,kind=kind,entity=id,x=x/100,y=y/100,item=item}
end
local function entity(q,role,kind,id,item)
 local row=correct(kind,id);if not row then unresolved[#unresolved+1]='Missing '..kind..':'..id;return end
 local keys=db[kind:lower()..'Keys']
 for z,coords in pairs(row[keys.spawns] or {}) do for _,xy in ipairs(coords) do point(q,z,role,kind,id,xy[1],xy[2],item) end end
end
local function item(q,id,visited)
 visited=visited or {};if visited[id] then return end;visited[id]=true
 local row=correct('Item',id);if not row then unresolved[#unresolved+1]='Missing Item:'..id;return end
 for _,n in ipairs(row[db.itemKeys.npcDrops] or {}) do entity(q,'objective','NPC',n,id) end
 for _,n in ipairs(row[db.itemKeys.objectDrops] or {}) do entity(q,'objective','Object',n,id) end
 for _,n in ipairs(row[db.itemKeys.itemDrops] or {}) do item(q,n,visited) end
end
local ids={};for id,row in pairs(db.questData) do if zones[row[17]] then ids[#ids+1]=id end end;table.sort(ids)
local function alliance(mask)
 if mask==0 then return true end
 if not mask then return false end
 for _,bit in ipairs({1,4,8,64}) do if math.floor(mask/bit)%2==1 then return true end end
 return false
end
for _,id in ipairs(ids) do
 local q=correct('Quest',id)
 if alliance(q[6]) then
 local meta={id=id,name=q[1],required=q[4],level=q[5],races=q[6],classes=q[7],preAll=q[12],preAny=q[13],exclusive=q[16],next=q[22],skill=q[18],minRep=q[19],maxRep=q[20],maxLevel=q[32],zone=zones[q[17]],limitations={}}
  output.quests[id]=meta
  for _,pair in ipairs({{2,'giver'},{3,'turn-in'}}) do
   local contacts=q[pair[1]] or {}
   for _,n in ipairs(contacts[1] or {}) do entity(id,pair[2],'NPC',n) end
   for _,n in ipairs(contacts[2] or {}) do entity(id,pair[2],'Object',n) end
   if contacts[3] then meta.limitations[#meta.limitations+1]='Item-start availability is conditional' end
  end
  local obj=q[10] or {}
  for _,n in ipairs(obj[1] or {}) do entity(id,'objective','NPC',n[1]) end
  for _,n in ipairs(obj[2] or {}) do entity(id,'objective','Object',n[1]) end
  for _,n in ipairs(obj[3] or {}) do item(id,n[1]) end
  for _,n in ipairs(obj[5] or {}) do for _,npc in ipairs(n[1] or {}) do entity(id,'objective','NPC',npc) end end
  for z,coords in pairs(q[9] and q[9][2] or {}) do for _,xy in ipairs(coords) do point(id,z,'objective','event',id,xy[1],xy[2]) end end
  if obj[4] or obj[6] or q[29] or q[21] then meta.limitations[#meta.limitations+1]='Supplementary, reputation, spell or source-item objectives not spatially expanded' end
 end
end
table.sort(output.points,function(a,b) return serialize(a)<serialize(b) end)
assert(#unresolved==0,'Unresolved correction or missing entity: '..table.concat(unresolved,'; '))
local file=assert(io.open('Data/AuditedEra.lua','w'));file:write('local _, WP = ...\n-- Generated by tools/import_era.lua; see tools/source.json and DATA_AUDIT.md.\nWP.eraAudit={quests=',serialize(output.quests),',\npoints={\n')
for _,p in ipairs(output.points) do file:write(serialize(p),',\n') end
file:write('},unresolved=',serialize(unresolved),',corrections=',serialize(applied),'}\n');file:close()
local counts={};for _,p in ipairs(output.points) do local k=p.zone..':'..p.role;counts[k]=(counts[k] or 0)+1 end
print(serialize(counts));print('quests',#ids,'unresolved corrections',#unresolved)
for _,s in ipairs(unresolved) do print(s) end
