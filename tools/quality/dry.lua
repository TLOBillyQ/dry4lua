#!/usr/bin/env lua5.4
-- Entrypoint for the dry4lua structural duplication detector.
local script = arg[0] or ""
local root = script:match("^(.+)/tools/quality/dry%.lua$") or "."
package.path = root .. "/lib/?.lua;" .. package.path

local cli = require("dry4lua.cli")
os.exit(cli.run(arg))
