local DEFAULT_INCLUDE = { "**/tests/**", "**/*Test.php" }
local DEFAULT_EXCLUDE = { "**/vendor/**", "**/*.teez.lua" }

local function runner_config(context)
  return context.runner or {}
end

local function include_patterns(context)
  local runner = runner_config(context)
  if runner.include then
    return runner.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local runner = runner_config(context)
  if runner.exclude then
    return runner.exclude
  end
  return DEFAULT_EXCLUDE
end

local function path_matches_any(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_included_test_file(path, context)
  if not path:match("Test%.php$") then
    return false
  end
  if path_matches_any(path, exclude_patterns(context)) then
    return false
  end
  return path_matches_any(path, include_patterns(context))
end

local function vendor_phpunit(context)
  return context.target_path .. "/vendor/bin/phpunit"
end

local function phpunit_available(context)
  return fs.exists(vendor_phpunit(context))
end

local function resolve_command(context)
  local vendor = vendor_phpunit(context)
  if fs.exists(vendor) then
    return "php", { vendor }
  end
  return "phpunit", {}
end

local function append_runner_args(args, context)
  local runner = runner_config(context)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
  return args
end

local function append_filter_args(args, context)
  local runner = runner_config(context)

  if runner.filter then
    table.insert(args, "--filter")
    table.insert(args, runner.filter)
  elseif runner.pattern then
    table.insert(args, "--filter")
    table.insert(args, runner.pattern)
  end

  if context.filters then
    if context.filters.pattern then
      table.insert(args, "--filter")
      table.insert(args, context.filters.pattern)
    elseif context.filters.name then
      table.insert(args, "--filter")
      table.insert(args, context.filters.name)
    elseif context.filters.names and #context.filters.names == 1 then
      table.insert(args, "--filter")
      table.insert(args, context.filters.names[1])
    end
  end

  return args
end

local function base_run_args(context)
  local args = { "--colors=never", "--verbose", "--debug" }
  append_runner_args(args, context)
  append_filter_args(args, context)
  return args
end

local function discover_tests(context)
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if is_included_test_file(path, context) and not seen[path] then
        seen[path] = true
        table.insert(tests, path)
      end
    end
  end

  table.sort(tests)
  return tests
end

local function filter_test_ids(tests, context)
  if not context.filters then
    return tests
  end

  local filtered = {}
  for _, id in ipairs(tests) do
    if filter.matches({ id = id }, context.filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function parse_list_tests_output(output)
  local tests = {}
  for line in output:gmatch("[^\r\n]+") do
    local id = line:match("^%s*-%s+(.+)$")
    if id and id ~= "" then
      table.insert(tests, id)
    end
  end
  return tests
end

function list(context)
  if phpunit_available(context) then
    local command, base_args = resolve_command(context)
    local args = {}
    for _, arg in ipairs(base_args) do
      table.insert(args, arg)
    end
    table.insert(args, "--list-tests")
    append_filter_args(args, context)

    local result = sys.run(command, args, { cwd = context.target_path })
    if result.exit_code == 0 and result.stdout ~= "" then
      local tests = parse_list_tests_output(result.stdout)
      if #tests > 0 then
        return filter_test_ids(tests, context)
      end
    end
  end

  return filter_test_ids(discover_tests(context), context)
end

function build_command(context)
  local command, base_args = resolve_command(context)
  local args = {}

  for _, arg in ipairs(base_args) do
    table.insert(args, arg)
  end

  for _, arg in ipairs(base_run_args(context)) do
    table.insert(args, arg)
  end

  if context.filters and context.filters.paths then
    for _, path in ipairs(context.filters.paths) do
      table.insert(args, path)
    end
  elseif context.filters and context.filters.names and #context.filters.names > 1 then
    for _, name in ipairs(context.filters.names) do
      table.insert(args, "--filter")
      table.insert(args, name)
    end
  end

  return {
    command = command,
    args = args,
    cwd = context.target_path,
  }
end

local function parse_failure_header(line)
  return line:match("^%d+%)%s+(.+)$")
end

local function parse_debug_event(line)
  local id = line:match("^Test Passed %((.+)%)%)$")
  if id then
    return { event = "pass", id = id }
  end

  id = line:match("^Test Failed %((.+)%)%)$")
  if id then
    return { event = "fail", id = id }
  end

  id = line:match("^Test Errored %((.+)%)%)$")
  if id then
    return { event = "fail", id = id }
  end

  id = line:match("^Test Skipped %((.+)%)%)$")
  if id then
    return { event = "skip", id = id }
  end

  id = line:match("^Test Marked Incomplete %((.+)%)%)$")
  if id then
    return { event = "skip", id = id }
  end

  id = line:match("^Test Prepared %((.+)%)%)$")
  if id then
    return { event = "start", id = id }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local debug_event = parse_debug_event(line)
  if debug_event then
    return debug_event
  end

  local failure_id = parse_failure_header(line)
  if failure_id then
    return { event = "fail", id = failure_id, msg = line }
  end

  if line:match("^OK %(") or line:match("^OK$") then
    return { event = "output", text = line }
  end

  if line:match("^FAILURES!") or line:match("^ERRORS!") then
    return { event = "output", text = line }
  end

  if line:match("^There was %d+ failure") or line:match("^There were %d+ failures") then
    return { event = "output", text = line }
  end

  if line:match("^There was %d+ error") or line:match("^There were %d+ errors") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local command, base_args = resolve_command(context)
  local runner = runner_config(context)
  local output = runner.coverage_output or "coverage/clover.xml"
  local args = {}

  for _, arg in ipairs(base_args) do
    table.insert(args, arg)
  end

  for _, arg in ipairs(base_run_args(context)) do
    table.insert(args, arg)
  end

  table.insert(args, "--coverage-clover")
  table.insert(args, output)

  return {
    command = command,
    args = args,
    cwd = context.target_path,
    report = output,
    reporter = "cobertura",
  }
end
