local DEFAULT_INCLUDE = {
  "**/test/**",
  "**/*-test.scm",
  "**/*_test.scm",
}

local TEST_EXTENSIONS = {
  [".scm"] = true,
  [".sls"] = true,
}

local COMMAND_CANDIDATES = { "guile", "chicken", "scheme" }

local function runner_config(context)
  return context.runner or {}
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function extension(path)
  return path:match("(%.[^./]+)$") or ""
end

local function is_test_file(path)
  local ext = extension(path)
  if not TEST_EXTENSIONS[ext] then
    return false
  end

  local name = basename(path)
  if name:match("%-test%.scm$") or name:match("_test%.scm$") then
    return true
  end

  return path:match("/test/") ~= nil or path:match("/tests/") ~= nil
end

local function expand_pattern(pattern)
  local expanded = { pattern }
  if pattern:match("/%*$") or pattern:match("/%*%*$") then
    local base = pattern:gsub("/%*+$", "")
    table.insert(expanded, base .. "/**/*.scm")
    table.insert(expanded, base .. "/**/*.sls")
  end
  return expanded
end

local function merge_patterns(context)
  local runner = runner_config(context)
  local source = runner.include or DEFAULT_INCLUDE
  local patterns = {}

  for _, pattern in ipairs(source) do
    for _, expanded in ipairs(expand_pattern(pattern)) do
      table.insert(patterns, expanded)
    end
  end

  return patterns
end

local function should_exclude(path, context)
  local runner = runner_config(context)
  local excludes = runner.exclude
  if not excludes then
    return false
  end

  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end

  return false
end

local function collect_tests(context)
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(merge_patterns(context)) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if not seen[path] and is_test_file(path) and not should_exclude(path, context) then
        seen[path] = true
        table.insert(tests, path)
      end
    end
  end

  table.sort(tests)
  return tests
end

local function command_available(command)
  local result = sys.run(command, { "--version" })
  return result.exit_code == 0
end

local function resolve_command(runner)
  if runner.command then
    return runner.command
  end

  for _, candidate in ipairs(COMMAND_CANDIDATES) do
    if command_available(candidate) then
      return candidate
    end
  end

  error(
    "No Scheme implementation found on PATH. Install guile or chicken, "
      .. "or set runners.scheme.command in teez.config.lua."
  )
end

local function resolve_test_runner(runner, target_path)
  if runner.test_runner then
    return runner.test_runner
  end

  local project_runner = target_path .. "/test-runner.scm"
  if fs.exists(project_runner) then
    return project_runner
  end

  return "test-runner.scm"
end

local function build_args(command, runner, test_runner, test_files)
  local args = {}

  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end

  if command == "chicken" then
    table.insert(args, "-script")
    table.insert(args, test_runner)
    for _, file in ipairs(test_files) do
      table.insert(args, file)
    end
    return args
  end

  table.insert(args, "-l")
  table.insert(args, test_runner)
  for _, file in ipairs(test_files) do
    table.insert(args, file)
  end

  return args
end

local function apply_filters(tests, context)
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

function list(context)
  return apply_filters(collect_tests(context), context)
end

function build_command(context)
  local runner = runner_config(context)
  local command = resolve_command(runner)
  local tests = apply_filters(collect_tests(context), context)

  if #tests == 0 then
    error("No Scheme SRFI-64 test files found")
  end

  local spec = {
    command = command,
    args = build_args(command, runner, resolve_test_runner(runner, context.target_path), tests),
  }

  if runner.env then
    spec.env = runner.env
  end

  if runner.coverage then
    if type(runner.coverage) == "table" and runner.coverage.env then
      spec.env = spec.env or {}
      for key, value in pairs(runner.coverage.env) do
        spec.env[key] = value
      end
    end
  end

  return spec
end

local function parse_result_line(line)
  local pass = line:match("^%s*PASS[:%s]+(.+)%s*$")
  if pass then
    return { event = "pass", id = pass }
  end

  local fail, msg = line:match("^%s*FAIL[:%s]+([^:]+):%s*(.+)%s*$")
  if fail then
    return { event = "fail", id = fail, msg = msg }
  end

  fail = line:match("^%s*FAIL[:%s]+(.+)%s*$")
  if fail then
    return { event = "fail", id = fail, msg = line }
  end

  local skip = line:match("^%s*SKIP[:%s]+(.+)%s*$")
  if skip then
    return { event = "skip", id = skip }
  end

  local start = line:match("^%s*START[:%s]+(.+)%s*$")
  if start then
    return { event = "start", id = start }
  end

  pass = line:match("^%s*Test passed:%s+(.+)%s*$")
  if pass then
    return { event = "pass", id = pass }
  end

  fail, msg = line:match("^%s*Test failed:%s+([^:]+):%s*(.+)%s*$")
  if fail then
    return { event = "fail", id = fail, msg = msg }
  end

  fail = line:match("^%s*Test failed:%s+(.+)%s*$")
  if fail then
    return { event = "fail", id = fail, msg = line }
  end

  local unexpected = line:match("^%s*Unexpected failure:%s+(.+)%s*$")
  if unexpected then
    return { event = "fail", id = unexpected, msg = line }
  end

  local expected = line:match("^%s*Expected failure:%s+(.+)%s*$")
  if expected then
    return { event = "pass", id = expected }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local event = parse_result_line(line)
  if event then
    return event
  end

  if line:match("# of unexpected failures:%s*%d+")
    or line:match("# of expected passes:%s*%d+")
    or line:match("^%s*;;;;")
  then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = runner_config(context)
  local coverage = runner.coverage
  if not coverage then
    return nil
  end

  local command = resolve_command(runner)
  local tests = apply_filters(collect_tests(context), context)
  if #tests == 0 then
    error("No Scheme SRFI-64 test files found")
  end

  local spec = {
    command = command,
    args = build_args(command, runner, resolve_test_runner(runner, context.target_path), tests),
    report = coverage.report or "coverage/lcov.info",
    reporter = coverage.reporter or "lcov",
    output = coverage.output or "coverage/teez.msgpack",
  }

  if type(coverage) == "table" then
    if coverage.collect then
      spec.collect = coverage.collect
    end
    if coverage.min_line_rate then
      spec.min_line_rate = coverage.min_line_rate
    end
    if coverage.cwd then
      spec.cwd = coverage.cwd
    end
    if coverage.env then
      spec.env = coverage.env
    end
  end

  return spec
end
