for _,path in ipairs(arg) do assert(loadfile(path)) end
print('PASS: compiled '..#arg..' Lua files')
