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

local assert_is_table,
      assert_is_string,
      assert_is_boolean
      = import 'lua-nucleo/typeassert.lua'
      {
        'assert_is_table',
        'assert_is_string',
        'assert_is_boolean'
      }

local empty_table,
      tclone
      = import 'lua-nucleo/table-utils.lua'
      {
        'empty_table',
        'tclone'
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
  -- Load and preprocess data

  local data_str = assert(io.open("commands.json", "r")):read("*a")
  local data = assert(json.decode(data_str))
  for name, info in pairs(data) do
    local cmd = { }

    cmd.raw = info -- TODO: Remove

    cmd.name = name:upper()
    cmd.id = ident_map[name:lower():gsub(" ", "_")]

    cmd.summary = assert_is_string(info.summary)
    cmd.since = assert_is_string(info.since)
    cmd.group = assert_is_string(info.group)

    cmd.have_multiple = false
    cmd.post_multiple_count = 0
    cmd.multiple_is_optional = false

    cmd.arguments = { }
    if info.arguments then
      for i = 1, #info.arguments do
        local arg_info = info.arguments[i]

        local arg = { }

        if arg_info.optional ~= nil then
          arg.optional = assert_is_boolean(arg_info.optional)
          if arg.optional and cmd.have_multiple then
            error(
                "optional after multiple in " .. name .. ":" .. tstr(cmd)
              )
          end
        else
          arg.optional = false
        end

        if arg_info.multiple then
          arg.multiple = true

          if cmd.have_multiple then
            error(
                "double multiple in " .. name .. ":" .. tstr(cmd)
              )
          end

          if arg.optional then
            cmd.multiple_is_optional = false
          end

          cmd.have_multiple = true
        else
          arg.multiple = false

          if cmd.have_multiple then
            if cmd.multiple_is_optional then
              error(
                  "optional post-multiple in " .. name .. ":" .. tstr(cmd)
                )
            end

            cmd.post_multiple_count = cmd.post_multiple_count + 1
          end
        end

        if not is_table(arg_info.name) then
          arg.name = assert_is_string(arg_info.name)
          arg.id = ident_map[assert_is_string(arg_info.name)]
          arg.type = assert_is_string(arg_info.type) -- TODO: map types

          cmd.arguments[#cmd.arguments + 1] = arg
        else
          -- TODO: Do not lose group info
          --       (for example, about paired optionals like in ZRANGEBYSCORE)

          assert_is_table(arg_info.type)
          assert(#arg_info.name > 0)
          assert(#arg_info.name == #arg_info.type)
          assert(arg_info.optional or arg_info.multiple)

          for i = 1, #arg_info.name do
            arg.name = assert_is_string(arg_info.name[i])
            arg.id = ident_map[assert_is_string(arg_info.name[i])]
            arg.type = assert_is_string(arg_info.type[i]) -- TODO: map types

            cmd.arguments[#cmd.arguments + 1] = arg

            arg = tclone(arg)
          end
        end
      end
    end

    COMMANDS[#COMMANDS + 1] = cmd
  end

  table.sort(COMMANDS, function(lhs, rhs) return lhs.name < rhs.name end)
end

--------------------------------------------------------------------------------

local cat, concat = make_concatter()

--------------------------------------------------------------------------------

for i = 1, #COMMANDS do
  local cmd = COMMANDS[i]

  cat [[
--------------------------------------------------------------------------------
-- ]] (cmd.name) [[

--
-- Group: ]] (cmd.group) [[

-- Since: ]] (cmd.since) [[

--
]] (wrap(cmd.summary, 80 - 3, "-- ", "-- ")) [[

--------------------------------------------------------------------------------

]]
  if #cmd.arguments == 0 then
    cat [[
local ]] (cmd.id) [[ = function(self)
  return self.command_(self.obj_, ]] (("%q"):format(cmd.name)) [[)
end

]]
  else
    cat [[
local ]] (cmd.id) [[ = function(
    self]]
    for i = 1, #cmd.arguments do
      local arg = cmd.arguments[i]
      if arg.multiple then
        cat [[,
    ...]]
        break
      end

        cat [[,
    ]] (arg.id)

    end

    cat [[

  )
  local nargs = select("#", ...)
]]
    -- TODO: Try to make generated code to look less weird
    if command.have_multiple then
      local had_multiple = false
      for i = 1, #cmd.arguments do
        if arg.multiple then
          assert(not had_multiple)
          had_multiple = true

          cat [[
  for i = ]] (i) [[, nargs - ]] (cmd.post_multiple_count) [[ do
    check_]] (arg.type) [[(self, ]] (
        tostring(arg.optional)
      ) [[, select(nargs - ]] (i) [[, ...))
  end
]]
        elseif had_multiple then
          assert(not arg.optional)
          cat [[
  check_]] (arg.type) [[(self, false, select(nargs - ]] (i) [[, ...))
]]
        end
      end
    end

    cat [[
  return self.command_(
      self.obj_
]]

    for i = 1, #cmd.arguments do
      local arg = cmd.arguments[i]
      if arg.multiple then
        cat [[,
      ...
]]
        break
      end

      -- TODO: This is wrong!
      cat [[,
      check_]] (arg.type) [[(self, ]] (
          tostring(arg.optional)
        ) [[, ]] (arg.id) [[)]]
    end

    cat [[
    )
end

]]
  end
end

io.write(concat(), "\n")
