local cli = require("dry4lua.cli")

test("cli: defaults", function()
  local options = cli.parse_args({})
  assert_eq(options.threshold, 0.82)
  assert_eq(options.min_lines, 4)
  assert_eq(options.min_nodes, 20)
  assert_eq(options.limit, nil)
  assert_eq(options.format, "text")
  assert_eq(options.help, false)
  assert_eq(options.paths[1], "src")
  assert_eq(#options.paths, 1)
end)

test("cli: explicit paths", function()
  local options = cli.parse_args({ "lib", "tests/fixtures" })
  assert_eq(options.paths[1], "lib")
  assert_eq(options.paths[2], "tests/fixtures")
end)

test("cli: value options", function()
  local options = cli.parse_args({
    "--threshold", "0.5",
    "--min-lines", "8",
    "--min-nodes", "40",
    "--limit", "3",
  })
  assert_eq(options.threshold, 0.5)
  assert_eq(options.min_lines, 8)
  assert_eq(options.min_nodes, 40)
  assert_eq(options.limit, 3)
end)

test("cli: format flags", function()
  assert_eq(cli.parse_args({ "--json" }).format, "json")
  assert_eq(cli.parse_args({ "--text" }).format, "text")
  assert_eq(cli.parse_args({ "--json", "--text" }).format, "text")
end)

test("cli: help flag", function()
  assert_eq(cli.parse_args({ "--help" }).help, true)
  assert_eq(cli.parse_args({ "-h" }).help, true)
end)

local function expect_exit(code, args)
  local real_exit = os.exit
  os.exit = function(value) error("exit:" .. tostring(value), 0) end
  local ok, err = pcall(cli.parse_args, args)
  os.exit = real_exit
  assert_true(not ok, "expected os.exit")
  assert_eq(err, "exit:" .. tostring(code))
end

test("cli: unknown option exits with code 2", function()
  expect_exit(2, { "--nope" })
end)

test("cli: non-numeric option value exits with code 2", function()
  expect_exit(2, { "--threshold", "abc" })
end)

test("cli: negative limit exits with code 2", function()
  expect_exit(2, { "--limit", "-1" })
end)
