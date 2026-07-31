rockspec_format = "3.0"
package = "dry4lua"
version = "0.1.0-1"
source = {
   url = "git+http://lzxsvn:3000/qinyuanj/dry4lua.git",
   tag = "v0.1.0",
}
description = {
   summary = "Structural duplication detector for Lua",
   detailed = [[
      dry4lua detects duplicated code in Lua sources by normalizing AST
      subtrees and comparing fingerprint sets with Jaccard similarity. It is
      the Lua port of unclebob's dry4clj / dry4go / dry4java tools.
   ]],
   homepage = "http://lzxsvn:3000/qinyuanj/dry4lua",
   license = "MIT",
}
dependencies = {
   "lua >= 5.4",
   "luacheck == 1.2.0-1",
}
test_dependencies = {
   "luaunit == 3.5-1",
}
build = {
   type = "builtin",
   modules = {
      ["dry4lua.cli"] = "lib/dry4lua/cli.lua",
      ["dry4lua.analysis"] = "lib/dry4lua/analysis.lua",
      ["dry4lua.ast"] = "lib/dry4lua/ast.lua",
   },
   install = {
      bin = {
         ["dry4lua"] = "bin/dry4lua",
      },
   },
}
