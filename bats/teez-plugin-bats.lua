local DEFAULT_TEST_DIR = "test"

local DEFAULT_INCLUDE = {
  "**/*.bats",
  "**/test/**/*.bats",
}

local DEFAULT_EXCLUDE = {
  "**/*.teez.lua",
}

local function runner_opts(context)
  return context.runner or {}
end

local function test_dir(context)
  local runner = runner_opts(context)
  return runner.test_dir or DEFAULT_TEST_DIR
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, arg in ipairs(extra) do
    table.insert(args, arg)
  end
end

local function matches_any_exclude(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function discover_bats_files(context)
  local runner = runner_opts(context)
  local patterns = runner.include or DEFAULT_INCLUDE
  local excludes = runner.exclude or DEFAULT_EXCLUDE
  local files = {}
  local seen = {}

  for _, pattern in ipairs(patterns) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if not seen[path] and not matches_any_exclude(path, excludes) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
end

local function filter_tests(tests, filters)
  if not filters then
    return tests
  end

  local filtered = {}
  for _, id in ipairs(tests) do
    if filter.matches({ id = id }, filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function unique_test_files(tests)
  local files = {}
  local seen = {}

  for _, id in ipairs(tests) do
    local file = id:match("^([^:]+)") or id
    if not seen[file] then
      seen[file] = true
      table.insert(files, file)
    end
  end

  return files
end

local function bats_args(context, mode)
  local runner = runner_opts(context)
  local args = {}

  if mode == "list" then
    table.insert(args, "--collect")
    table.insert(args, "-r")
  else
    if runner.tap ~= false then
      table.insert(args, "-t")
    end
    if runner.recursive then
      table.insert(args, "-r")
    end
  end

  append_args(args, runner.args)
  return args
end

local function list_via_collect(context)
  local args = bats_args(context, "list")
  table.insert(args, test_dir(context))

  local result = sys.run("bats", args, { cwd = context.target_path })
  if result.exit_code ~= 0 then
    return nil
  end

  local tests = {}
  for line in result.stdout:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(tests, trimmed)
    end
  end

  return tests
end

local function collect_tests(context)
  local tests = list_via_collect(context)
  if not tests or #tests == 0 then
    tests = discover_bats_files(context)
  end

  return filter_tests(tests, context.filters)
end

local function wrap_coverage(command, args, runner)
  local tool = runner.coverage
  if not tool then
    return command, args
  end

  if tool == "kcov" then
    local out = runner.coverage_dir or "coverage/kcov"
    local kcov_args = { "--lcov", out }
    append_args(kcov_args, runner.coverage_opts)
    table.insert(kcov_args, command)
    for _, arg in ipairs(args) do
      table.insert(kcov_args, arg)
    end
    return "kcov", kcov_args
  end

  if tool == "bashcov" then
    local bashcov_args = {}
    append_args(bashcov_args, runner.coverage_opts)
    table.insert(bashcov_args, "--")
    table.insert(bashcov_args, command)
    for _, arg in ipairs(args) do
      table.insert(bashcov_args, arg)
    end
    return "bashcov", bashcov_args
  end

  error("unsupported bats coverage tool: " .. tostring(tool))
end

function list(context)
  return collect_tests(context)
end

function build_command(context)
  local runner = runner_opts(context)
  local args = bats_args(context, "run")
  local targets

  if context.filters then
    local tests = collect_tests(context)
    if #tests == 0 then
      error("no Bats tests matched the current filters")
    end
    targets = unique_test_files(tests)
  else
    targets = { test_dir(context) }
  end

  for _, target in ipairs(targets) do
    table.insert(args, target)
  end

  local command, wrapped_args = wrap_coverage("bats", args, runner)

  return {
    command = command,
    args = wrapped_args,
    cwd = context.target_path,
  }
end

function parse_line(line)
  local trimmed = line:match("^%s*(.*)$")
  if trimmed == "" then
    return nil
  end

  if trimmed:match("^%d+%.%.$") then
    return nil
  end

  if trimmed:match("^#") then
    return { event = "output", text = line }
  end

  if trimmed:match("^ok %d+ # skip") or trimmed:match("^ok %d+ # SKIP") then
    local id = trimmed:match("^ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "skip", id = id }
  end

  if trimmed:match("^ok %d+") then
    local id = trimmed:match("^ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "pass", id = id }
  end

  if trimmed:match("^not ok %d+") then
    local id = trimmed:match("^not ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "fail", id = id, msg = trimmed }
  end

  if trimmed == "ok" then
    return { event = "pass", id = "bats" }
  end

  if trimmed == "not ok" then
    return { event = "fail", id = "bats", msg = trimmed }
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  local tool = runner.coverage or "kcov"
  local args = { "-t", "-r", test_dir(context) }
  append_args(args, runner.args)

  if tool == "kcov" then
    local out = runner.coverage_dir or "coverage/kcov"
    local kcov_args = { "--lcov", out, "bats" }
    append_args(kcov_args, runner.coverage_opts)
    for _, arg in ipairs(args) do
      table.insert(kcov_args, arg)
    end

    return {
      command = "kcov",
      args = kcov_args,
      cwd = context.target_path,
      report = out .. "/coverage/lcov.info",
      reporter = "lcov",
    }
  end

  if tool == "bashcov" then
    local bashcov_args = {
      "--simple-format",
      "--skip-uncoverable",
      runner.coverage_report or "coverage/lcov.info",
    }
    append_args(bashcov_args, runner.coverage_opts)
    table.insert(bashcov_args, "--")
    table.insert(bashcov_args, "bats")
    for _, arg in ipairs(args) do
      table.insert(bashcov_args, arg)
    end

    return {
      command = "bashcov",
      args = bashcov_args,
      cwd = context.target_path,
      report = runner.coverage_report or "coverage/lcov.info",
      reporter = "lcov",
    }
  end

  error("unsupported bats coverage tool: " .. tostring(tool))
end
