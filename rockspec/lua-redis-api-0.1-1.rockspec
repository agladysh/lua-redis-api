package = "lua-redis-api"
version = "0.1-1"
source = {
   url = "git://github.com/agladysh/lua-redis-api.git",
   branch = "v0.1"
}
description = {
   summary = "Redis API highlevel wrapper for Lua",
   homepage = "http://github.com/agladysh/lua-redis-api",
   license = "MIT/X11",
   maintainer = "Alexander Gladysh <agladysh@gmail.com>"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["redis-api"] = {
         sources = {
            "src/lua-redis-api.lua"
         }
      }
   }
}
