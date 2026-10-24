local w={};assert(loadfile('Data/AuditedEra.lua'))('audit',w)
local d=w.eraAudit;local qn={};local pn={};local corrected=0;local types={};local present={};local missing={}
for _,p in ipairs(d.points) do pn[p.zone..' '..p.role]=(pn[p.zone..' '..p.role] or 0)+1;present[p.quest]=true end
for id,q in pairs(d.quests) do
 qn[q.zone]=(qn[q.zone] or 0)+1
 if not present[id] then missing[#missing+1]=id end
 if #q.limitations>0 then print('LIMIT',id,q.name,table.concat(q.limitations,'; ')) end
end
for tag,value in pairs(d.corrections) do if value then corrected=corrected+1;local t=tag:match('^(%w+):');types[t]=(types[t] or 0)+1 end end
for k,v in pairs(qn) do print('QUESTS',k,v) end
for k,v in pairs(pn) do print('POINTS',k,v) end
for k,v in pairs(types) do print('CORRECTED',k,v) end
table.sort(missing);print('NO_LOCAL_SPATIAL_EVIDENCE',table.concat(missing,','));print('CORRECTED_TOTAL',corrected)
local old={};assert(loadfile('Data/ClassicEraObjectiveSamples.lua'))('old',old)
for _,q in ipairs(old.eraObjectiveSamples) do
 local new=d.quests[q.quest]
 if not new or new.level~=q.level or new.required~=q.required or new.name~=q.name then print('OLD_METADATA_CHANGE',q.quest,q.name,new and new.name,new and new.required,new and new.level) end
end
