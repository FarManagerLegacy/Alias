local Info = Info or package.loaded.regscript or function(...) return ... end --luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
  name        = "Alias";
  description = "Console aliases helper";
  version     = "2.1";
  --fix:escape_ptn
  author      = "jd";
  url         = "https://forum.farmanager.com/viewtopic.php?f=60&t=8546";
  id          = "09953E73-D214-4546-AF53-2B5762004346";
  minfarversion = {3,0,0,4324,0}; --luamacro 498
  files       = "alias.sample.doskey";
  options = {

    path      = false,
    filename  = "alias.doskey",

    macrokey  = false,
    autostart = true,

    msgdelay  = 200,
    errdelay  = 1000,
    exes      = {"far.exe","cmd.exe"}, --in lower case
                --win.GetEnv("COMSPEC"):match("[^\\]+$"):lower() --todo
  };
}
if not nfo or nfo.disabled or not panel.CheckPanelsExist() then return end
local O = nfo.options

local prefix = "alias:"
local cmd_load = "/file"

local set_pattern     = "^%s*([^=%s]+)%s*=%s*(.-)%s*$"
local set_pattern2    = "^%s*(=+)%s*=%s*(.-)%s*$"
local empty_pattern   = "^%s*$"
local section_pattern = "^%[(..-)%](.*)$"
local rem_pattern     = "^%s*;=%s*(.*)$"

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[//http://msdn.microsoft.com/library/ms681935
BOOL AddConsoleAliasW(
  LPCTSTR Source,
  LPCTSTR Target,
  LPCTSTR ExeName
);]]

local function _utf16 (str) return win.Utf8ToUtf16(str.."\0") end
local function _ptr (buffer) return ffi.cast("void*",buffer) end
local function AddConsoleAlias (Source,Target,ExeName)
  Source,Target,ExeName = _utf16(Source),_utf16(Target),_utf16(ExeName)
  local res = C.AddConsoleAliasW(_ptr(Source),_ptr(Target),_ptr(ExeName))
  if res>0 then return true end
end

--------------------------------------------------------------------------------
local F = far.Flags
local __filename = Macro and ... or _filename:match[[^\\%?\UNC\(.+)$]] or
                   _filename:match[[^\\%?\(.+)$]] or _filename
local __path = __filename:match"^.+\\"
local aliasfile = (O.path or __path)..O.filename
--nfo.userfiles = aliasfile

local exe = O.exes[1]
local isUtf8 = string.char(0xEF,0xBB,0xBF) -- "\239\187\191" -- https://en.wikipedia.org/wiki/Byte_order_mark#UTF-8
local function loadAliasesFile (filename)
  local file,err = io.open(far.ConvertPath(filename or aliasfile,F.CPM_NATIVE),"r")
  if not file then return nil, err end
  local bom = file:read(3)
  if not bom then return true, (filename or aliasfile)..": Empty file" end
  if bom~=isUtf8 then bom = false; file:seek("set") end
  local _exe = exe
  local Errors = {}
  local i = 0
  for line in file:lines() do
    line = bom and line or win.OemToUtf8(line)
    i = i+1
    if not (line:match(empty_pattern) or line:match(rem_pattern)) then
      local section = line:match(section_pattern)
      if section then
        _exe = section:lower()
      else
        local a,v = line:match(set_pattern)
        if not a then a,v = line:match(set_pattern2) end
        if a then
          if not AddConsoleAlias(a,v,_exe) then
            Errors[#Errors+1] = ("%d: %s"):format(i,"<see GetLastError>")
          end
        elseif not line:match(rem_pattern) then
          Errors[#Errors+1] = ("%d: %s"):format(i,line)
        end
      end
    end
  end
  file:close()
  return true, Errors[1] and Errors
end

--------------------------------------------------------------------------------

local function Reload (output_mode,filename)
  local scr
  if output_mode=="con" then
    panel.GetUserScreen()
    io.write("Console aliases loading...\n")
  elseif output_mode=="msg" then
    scr = far.SaveScreen()
    far.Message("Loading...","Console aliases","")
  end
  local success,msg = loadAliasesFile(filename)
  if output_mode=="con" then
    if msg then
      if type(msg)=="table" then msg = "Found errors:\n"..table.concat(msg,"\n") end
      io.write(win.Utf8ToOem(msg),"\n")
    end
    panel.SetUserScreen()
  elseif output_mode=="msg" then
    if msg then
      local _msg = type(msg)=="table" and "Press any key to see warnings" or msg
      far.Message(_msg,"Console aliases","",not success and "w" or nil)
      local ans = mf.waitkey(O.errdelay or 1000)
      far.RestoreScreen(scr)
      if ans~="" and type(msg)=="table" then
        far.Show(unpack(msg))
      end
    else
      win.Sleep(O.msgdelay or 200)
      far.RestoreScreen(scr)
    end
  end
end

local escape_ptn = ("^$()%.[]*+-?"):gsub(".","%%%1")
local _flags = {EF_DISABLEHISTORY=1,EF_NONMODAL=1,EF_IMMEDIATERETURN=1,EF_OPENMODE_USEEXISTING=1,EF_ENABLE_F6=1}
local function EditAlias (str)
  editor.Editor(aliasfile,O.filename,nil,nil,nil,nil,_flags)--,nil,nil,win.GetOEMCP())
  if Area.Editor and str and str~="" then
    local pattern = "^%s*"..str:lower():gsub(escape_ptn,"%%%1").."%s*="
    for i=1,editor.GetInfo().TotalLines do
      local line = editor.GetString(nil,i,3):lower()
      local a,b = line:find(pattern)
      if a then
        editor.SetPosition(nil,i,b,nil,i-2,1)
        editor.Select(nil,F.BTYPE_STREAM,i,a,b-1,1)
        Editor.Set(2,1) --Persistent blocks --todo editor.AddColor?
        editor.Redraw() --to show selection
        return
      end
    end
    far.Message(("Could not find the string\n%q"):format(str),"Search",nil,"w")
  end
end

--------------------------------------------------------------------------------
nfo.help = function() far.ShowHelp(__path, nil, F.FHELP_CUSTOMPATH) end
nfo.execute = function() Reload("msg") end
nfo.config = function() EditAlias() end
nfo.export = {EditAlias=EditAlias}

local function ExpandEnv (path)
  return path:gsub("%%(.-)%%", win.GetEnv)
end

if not CommandLine then
  local param = _filename and ... and type(...)=="string" and ExpandEnv(...)
  Reload(param and "con" or "msg",param)
  return
end
--------------------------------------------------------------------------------

Macro { description="Aliases: load";
  area="Common"; key=O.macrokey; flags=O.autostart and "RunAfterFARStart";
  id="7E457D6D-6DF1-486B-8E27-892BE509936E";
  action=function()
    Reload(mf.akey(1)=="" and "con" or "msg") --??or mf.akey(1,1)
  end;
}

Event { description="Aliases: reload on edit";
  group="EditorEvent"; filemask=O.filename;
  id="21581838-9EA5-44FE-9E28-7AC93D90E495";
  action=function(id,Event,Param)
    if Event==F.EE_SAVE and Param.FileName:lower()==aliasfile:lower() then
      Reload("msg")
    end
  end;
}

local function isCmdLoad (text)
  local cmd_len = cmd_load:len()
  if text:sub(1,cmd_len)~=cmd_load then return end
  if text:len()==cmd_len then return true end
  local file = text:sub(cmd_len+1,-1):match"^%s+(.+)"
  if file then
    return true,ExpandEnv(file:match[[^"(.+)"$]] or file)
  end
end

CommandLine { description="Aliases: process cmdline (edit/add)";
  prefixes=prefix;
  action=function(_,line)
    if line~="" then
      local iscmd,filename = isCmdLoad(line)
      if iscmd then
        Reload("con",filename)
        return
      else
        local a,v = line:match(set_pattern)
        if not a then a,v = line:match(set_pattern2) end
        if a then
          if not AddConsoleAlias(a,v,exe) then
            far.Message("Unable to add console alias","Error",nil,"ew") --GetLastError
          end
          return
        end
      end
    end
    EditAlias(line:match"^%S+")
  end;
}
