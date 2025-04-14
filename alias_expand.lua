local Info = Info or package.loaded.regscript or function(...) return ... end --luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
  name        = "Alias: expand";
  description = "Expands alias in cmdline";
  version     = "0.1.1+pre"; --https://semver.org/lang/ru/
  author      = "jd";
  url         = "https://forum.farmanager.com/viewtopic.php?f=60&t=8546";
  id          = "76547AB6-D17B-4B4C-B153-8FBF3BFC8DCF";
  parent_id   = "09953E73-D214-4546-AF53-2B5762004346";
  --disabled    = false;
  options     = {
    exes     ={"far.exe","cmd.exe"},
    expand   ="ShiftSpace",
    confirm  ="AltSpace",
    alias_re =[[^(\s*)([^&|\s]+)\s*(.+)?$]], --pre,str,params
    stopchars=" &<|>/\\",--todo escape then
  };
}
if not nfo or nfo.disabled or not panel.CheckPanelsExist() then return end
local O = nfo.options
if nfo.index then
  mf.postmacro(function()
    local main = Info.getscript(nfo.parent_id)
    if main then
      O.exes = main.options.exes
    end
  end)
end

local ffi = require("ffi")

ffi.cdef[[
//https://msdn.microsoft.com/library/ms683157
DWORD GetConsoleAliasW(
  LPTSTR lpSource,
  LPTSTR lpTargetBuffer,     //_Out_ 
  DWORD  TargetBufferLength,
  LPTSTR lpExeName
);]]
local C = ffi.C

local function _wchar (str)
  str = win.Utf8ToUtf16(str)
  local buffer = ffi.new("wchar_t[?]",#str/2+1)
  ffi.copy(buffer,str)
  return buffer
end
local function _buf (len) return ffi.new("wchar_t[?]",len) end
local function _ptr (buffer) return ffi.cast("void*",buffer) end
local function _str (buffer,len) return win.Utf16ToUtf8(ffi.string(buffer,len)) end
local TargetBufferLength = 4096
local function GetConsoleAlias (Source,ExeName)
  Source,ExeName = _wchar(Source),_wchar(ExeName)
  local TargetBuffer = _buf(TargetBufferLength)
  local res = C.GetConsoleAliasW(_ptr(Source),TargetBuffer,TargetBufferLength,_ptr(ExeName))
  if res~=0 then
    return _str(TargetBuffer,res-1)
  end
end
local function get (alias)
  for _,exe in ipairs(O.exes) do
    local v = GetConsoleAlias(alias,exe)
    if v then return v end
  end
end

local parse = regex.new(O.alias_re)
local function expand (cmdline)
  local noparams,alias
  cmdline = parse:gsub(cmdline,function(pre,str,params)
    alias = get(str)
    local n
    if alias and params then
      alias,n = alias:gsub("%$%*",function() return params end)
      if n==0 then alias = alias.." "..params end
    end
    noparams = not params
    return alias and pre..alias
  end,1)
  return alias and cmdline,noparams
end

local function processCmdline (need_confirm)
  local pre,cmdline,pos = false,panel.GetCmdLine(),panel.GetCmdLinePos()
  if pos<=cmdline:len() then
    while pos>1 and cmdline:sub(pos-1,pos-1):match"[^"..O.stopchars.."]" do pos = pos-1 end --todo fixme
    if pos>1 then
      pre = cmdline:sub(1,pos-1)
      cmdline = cmdline:sub(pos,-1)
    end
  end
  local noparams
  cmdline,noparams = expand(cmdline)
  if cmdline then
    local a,b
    if noparams then --process $*
      local n = select(2,cmdline:gsub("%$%*",""))
      if n==1 and cmdline:match"%$%*$" then
        cmdline = cmdline:sub(1,-3)
      end
      if n>0 then a,b = cmdline:find("$*",1,"plain") end
    end
    if pre then cmdline = pre..cmdline end
    if need_confirm and far.Message(cmdline,nfo.name)==-1 then return end
    panel.SetCmdLine(nil,cmdline)
    if a then --process $*
      if pre then
        local pre_len = pre:len()
        a = a+pre_len
        b = b+pre_len
      end
      panel.SetCmdLinePos(nil,b+1)
      panel.SetCmdLineSelection(nil,a,b)
    end
    if Area.ShellAutoCompletion or Area.DialogAutoCompletion then Keys"Esc CtrlSpace" end
  elseif need_confirm then
    mf.beep()
  else
    Keys"AKey"
  end
end

local allPanels = "Shell QView Info Tree ShellAutoCompletion"
local function condition () return not CmdLine.Empty end

if O.expand then Macro { description=nfo.name;
  area=allPanels; key=O.expand; --ShiftSpace
  id="D41AF343-3E24-4658-B558-105942623FD4";
  condition=condition;
  action=processCmdline;
}end

if O.confirm then Macro { description=nfo.name.." (with confirmation)";
  area=allPanels; key=O.confirm; --AltSpace
  id="1D9DA0BD-8605-487D-930E-A76261FF605B";
  condition=condition;
  action=function()
    processCmdline("confirm")--todo change verb
  end;
}end
--todo optionally complete
--todo CtrlG: Dialog DialogAutoCompletion
