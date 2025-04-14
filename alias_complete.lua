local Info = Info or package.loaded.regscript or function(...) return ... end --luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
  name        = "Alias: complete";
  description = "Complete alias in cmdline";
  version     = "0.1.1+pre"; --https://semver.org/lang/ru/
  author      = "jd";
  url         = "https://forum.farmanager.com/viewtopic.php?f=60&t=8546";
  id          = "18D69EBE-68A3-437E-8A26-045C25AD64F0";
  parent_id   = "09953E73-D214-4546-AF53-2B5762004346";
  --disabled    = false;
  options     = {
    alias_w   = 15,
    MaxHeight = 7, --false
    complete  = "CtrlSpace",
    showall   = "CtrlAltShiftSpace",
    --BreakKeys = --{...}
    exes      = {"far.exe","cmd.exe"},
    prefix    = "alias:",
    aliaspart_pattern='^(.-)([^&|"%s]+)$',
  };
}
if not nfo or nfo.disabled or not panel.CheckPanelsExist() then return end
local O = nfo.options
--local F = far.Flags

local EditAlias
if nfo.index then
  mf.postmacro(function()
    local main = Info.getscript(nfo.parent_id)
    if main then
      O.exes = main.options.exes
      EditAlias = main.export.EditAlias
    end
  end)
else
  local lmguid = win.Uuid(far.PluginStartupInfo().PluginGuid)
  function EditAlias(alias)
    Plugin.Command(lmguid,O.prefix..alias)
  end
end

local ffi = require("ffi")
ffi.cdef[[
//http://msdn.microsoft.com/library/ms683159
DWORD GetConsoleAliasesLengthW(
  LPTSTR lpExeName
);
//http://msdn.microsoft.com/library/ms683158
DWORD GetConsoleAliasesW(
  LPTSTR lpAliasBuffer,     //_Out_
  DWORD  AliasBufferLength,
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

local function GetConsoleAliases (ExeName)
  ExeName = _wchar(ExeName)
  local AliasBufferLength = C.GetConsoleAliasesLengthW(_ptr(ExeName))
  local AliasBuffer = _buf(AliasBufferLength/ffi.sizeof"wchar_t")
  local res = C.GetConsoleAliasesW(AliasBuffer,AliasBufferLength,_ptr(ExeName))
  return _str(AliasBuffer,AliasBufferLength),res
end

local def_width = 15 --const
local function makeFmt (width)
  width = width or def_width
  --        %-15.15s%s
  return ('%%-%s.%ss%%s'):format(width,width)
end
local function makeSep (str,width)
  width = width or def_width
  return not str or str:len()<=width and '│' or '…'
end
local function makeAliasItems (filter)
  local len = filter:len()
  filter = filter:lower()
  local alias_fmt = makeFmt(O.alias_w)
  local items,n,nsep = {},0,0
  for _,exe in ipairs(O.exes) do
    local v = GetConsoleAliases(exe)
    if v then
      local sep = {separator=true,text=exe,hidden=true}
      items[#items+1] = sep
      for a in v:gmatch"%Z+" do
        local alias,value = a:match"^(.-)=([^=].-)$"
        local hidden = alias:sub(1,len):lower()~=filter
        if not hidden then
          if sep then sep.hidden,sep = nil,nil; nsep=nsep+1 end
          n = n+1
        end
        if not hidden then
          items[#items+1] = {
            text =alias_fmt:format(alias,makeSep(alias,O.alias_w)).." "..value,
            alias=alias,
            value=value,
          }
        end
      end
    end
  end
  return items,n,nsep+n
end

local props = {
  Flags={FMENU_SHOWAMPERSAND=1,FMENU_WRAPMODE=1},
  Title=nfo.name,
  Id=win.Uuid"E2E95882-3D7F-47E7-BFBB-23598AF1DFA6",
}
local bkeys = O.BreakKeys or {
  {BreakKey="Shift+Return",   act="exec"},
  {BreakKey="F4",             act="edit"},
  {BreakKey="Ctrl+Return",    act="expand"},
  {BreakKey="Ctrl+Space",     act="next"},
  {BreakKey="CtrlShift+Space",act="farautocompletion"},
  {BreakKey="F5",             act="size"},
}
local function toggleSize ()
  if not O.MaxHeight then
    return
  elseif props.size then
    local size = props.size
    props.X,props.Y,props.MaxHeight = size.X,size.Y,size.MaxHeight
    props.size = false
  else
    props.size = {
      X=props.X,
      Y=props.Y,
      MaxHeight=props.MaxHeight,
    }
    props.X,props.Y,props.MaxHeight = nil,nil,nil
  end
end
local function next (items,pos)
  for j=pos+1,#items do
    if not items[j].separator and not items[j].hidden then return j end
  end
  return 1
end
local function AliasComplete (filter,x,y)
  local items,n,nn = makeAliasItems(filter or "")
  if n==0 then return end
  if O.MaxHeight then
    if y and nn<O.MaxHeight then y = y+O.MaxHeight-nn end
    props.X,props.Y,props.SelectIndex = x,y,1
  end
  props.MaxHeight = x and O.MaxHeight
  repeat
    local ret,i = far.Menu(props,items,bkeys)
    if not ret then
      return true
    elseif ret.act then
      if ret.act=="next" then
        props.SelectIndex = next(items,i)
      elseif ret.act=="size" then
        toggleSize()
      else
        local item = items[i]
        return item.alias,item.value,ret.act
      end
    else
      return ret.alias
    end
  until false
end
function nfo.execute () AliasComplete() end

local function getPos ()
  if O.MaxHeight then
    local pos = far.AdvControl"ACTL_GETCURSORPOS"
    return pos.X - panel.GetCmdLinePos() +1,
           pos.Y - O.MaxHeight -3
  end
end

local allPanels = "Shell QView Info Tree ShellAutoCompletion"
Macro { description=nfo.name;
  area=allPanels; key=O.complete; --CtrlSpace
  id="A3B4D685-0457-4E21-A5D4-D86D00142629";
  condition=function() return not CmdLine.Empty end;
  action=function()
    local fromFarCompl
    if Area.ShellAutoCompletion or Area.DialogAutoCompletion then fromFarCompl = true; Keys"Esc" end
    local cmdline = panel.GetCmdLine()
    local pre,aliaspart = cmdline:match(O.aliaspart_pattern)
    if aliaspart then
      local alias,value,act = AliasComplete(aliaspart,getPos())
      if alias then
        if type(alias)=="string" then
          if not act then--Enter--------------------
            panel.SetCmdLine(nil,pre..alias)
          elseif act=="exec" then-------------------
            panel.SetCmdLine(nil,pre..alias)
            Keys"Enter"
          elseif act=="edit" then-------------------
            EditAlias(alias)
          elseif act=="expand" then-----------------
            cmdline = pre..value
            panel.SetCmdLine(nil,cmdline)
            local a,b = cmdline:find("$*",1,"plain")
            if a then
              panel.SetCmdLinePos(nil,b+1)
              panel.SetCmdLineSelection(nil,a,b)
            end
            if fromFarCompl then Keys"CtrlSpace" end
          elseif act=="farautocompletion" then------
            Keys"CtrlSpace"
          end---------------------------------------
        end
        return
      end
    end
    Keys"AKey"
  end;
}

--todo showall
--todo breakkeys
--todo no descrptions mode
--todo CtrlG: Dialog DialogAutoCompletion
