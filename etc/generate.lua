-- generate.lua: Redis API highlevel wrapper generator for Lua
--------------------------------------------------------------------------------
-- This file is a part of lua-redis-api.
-- See copyring information in file named COPYRIGHT.
--------------------------------------------------------------------------------
-- Dependencies:
-- =============
--
-- sudo luarocks install lua-nucleo
-- sudo luarocks install luajson
--
-- Get commands.json file from redis-doc repository
-- (you may want to get a particular tag instead of master).
--
-- wget https://github.com/antirez/redis-doc/raw/master/commands.json
--
--------------------------------------------------------------------------------

pcall(require, 'luarocks.require') -- Ignoring errors

--------------------------------------------------------------------------------

require 'lua-nucleo.module'
require 'lua-nucleo.strict'
require = import 'lua-nucleo/require_and_declare.lua' { 'require_and_declare' }

--------------------------------------------------------------------------------

require 'json'

--------------------------------------------------------------------------------

local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' }
local tpretty = import 'lua-nucleo/tpretty.lua' { 'tpretty' }

local is_table,
      is_string
      = import 'lua-nucleo/type.lua'
      {
        'is_table',
        'is_string'
      }

local empty_table
      = import 'lua-nucleo/table-utils.lua'
      {
        'empty_table'
      }

local make_concatter,
      fill_curly_placeholders
      = import 'lua-nucleo/string.lua'
      {
        'make_concatter',
        'fill_curly_placeholders'
      }

--------------------------------------------------------------------------------

local maybe_tstr = function(a)
  if is_string(a) then
    return a
  end
  return tstr(a)
end

-- TODO: rewrite.
-- From http://lua-users.org/wiki/StringRecipes
local function wrap(str, limit, indent, indent1)
  indent = indent or ""
  indent1 = indent1 or indent
  limit = limit or 72
  local here = 1-#indent1
  return indent1..str:gsub("(%s+)()(%S+)()",
                          function(sp, st, word, fi)
                            if fi-here > limit then
                              here = st - #indent
                              return "\n"..indent..word
                            end
                          end)
end

local ident_map = setmetatable(
    {
      ["end"] = "end_"; -- TODO: Think out a better name
    },
    {
      __index = function(t, k)
        local v = k
        t[k] = v
        return v
      end;
    }
  )

--------------------------------------------------------------------------------

local COMMANDS = { }
do
  local data_str = assert(io.open("commands.json", "r")):read("*a")
  local data = assert(json.decode(data_str))
  for name, info in pairs(data) do
    assert(info.name == nil)
    info.name = name:upper()
    info.id = ident_map[name:lower():gsub(" ", "_")]
    info.arguments = info.arguments or empty_table
    COMMANDS[#COMMANDS + 1] = info
  end

  table.sort(COMMANDS, function(lhs, rhs) return lhs.name < rhs.name end)
end

--------------------------------------------------------------------------------

local cat, concat = make_concatter()

--------------------------------------------------------------------------------

local ocat = cat
local function cat(s)
  if type(s) ~= "string" then print(tstr(s)) end
  assert(type(s) == "string")
  ocat(s)
  return cat
end

for i = 1, #COMMANDS do
  local info = COMMANDS[i]

  cat [[
--------------------------------------------------------------------------------
-- ]] (info.name) [[

--
-- Group: ]] (info.group) [[

-- Since: ]] (info.since) [[

--
]] (wrap(info.summary, 80 - 3, "-- ", "-- ")) [[

--------------------------------------------------------------------------------

local ]] (info.id) [[ = function(
    self]]

  local multiple = false
  local genuine_multiple = false
  for i = 1, #info.arguments do
    local arg = info.arguments[i]

    arg.auto_multiple = true -- TODO: Hack! Remove ASAP.

    if is_table(arg.name) and not arg.multiple then
      io.stderr:write(
          "WARNING: hidden multiple cmd `", info.name,
          "' arg ", tstr(arg), "\n"
        )
      arg.auto_multiple = true
    end

    if arg.multiple then
      assert(genuine_multiple == false, "double multiple")
      genuine_multiple = true
    end

    if arg.multiple or arg.auto_multiple then
      if not multiple then
        multiple = true

        cat [[,
    ...
    -- ]] (ident_map[maybe_tstr(arg.name)])
      else
        io.stderr:write(
            "WARNING: double multiple cmd `", info.name,
            "' arg ", tstr(arg), "\n"
          )
        cat [[

    -- ]] (ident_map[maybe_tstr(arg.name)])
      end
    else
      if multiple then
        cat [[

    -- ]] (ident_map[arg.name])
      else

        cat [[,
    ]] (ident_map[arg.name])
      end
    end
  end

  cat [[

  )
  return self.command_(
      self.obj_, ]] (("%q"):format(info.name)) [[,
      ...
]]
  cat [[
    )
end

]]
end

io.write(concat(), "\n")
