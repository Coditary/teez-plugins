-- teez p5.js adapter (Mocha / Jest test utilities)

local DEFAULT_INCLUDE = { "**/*.test.js", "**/test/**" }
local DEFAULT_EXCLUDE = { "**/node_modules/**", "**/*.teez.lua" }

local parse_state = {
  current_file = nil,
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function runner_config(context)
  return context.runner or {}
end

local function target_path(context)
  return context.target_path or "."
end

local function resolve_glob_hit(root, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  return root .. "/" .. file
end

local function read_json_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  if not content or content == "" then
    return nil
  end

  return json.decode(content)
end

local function find_package_root(context)
  local path = target_path(context)
  while path and path ~= "" do
    if fs.exists(path .. "/package.json") then
      return path
    end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == path then
      break
    end
    path = parent
  end
  return target_path(context)
end

local function package_json(context)
  local root = find_package_root(context)
  return read_json_file(root .. "/package.json"), root
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

local function is_test_file(path, context)
  if not path:match("%.js$") then
    return false
  end
  if path_matches_any(path, exclude_patterns(context)) then
    return false
  end
  if path:match("%.test%.js$") then
    return true
  end
  if path:match("/test/") or path:match("^test/") then
    return true
  end
  return path_matches_any(path, include_patterns(context))
end

local function discover_test_files(context)
  local root = target_path(context)
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      local resolved = resolve_glob_hit(root, path)
      if is_test_file(resolved, context) and not seen[resolved] then
        seen[resolved] = true
        table.insert(tests, resolved)
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

local function detect_framework(context, pkg)
  local runner = runner_config(context)
  if runner.framework == "jest" or runner.framework == "mocha" then
    return runner.framework
  end

  if pkg then
    local dev = pkg.devDependencies or {}
    local prod = pkg.dependencies or {}
    if dev.jest or prod.jest then
      return "jest"
    end
    if dev.mocha or prod.mocha then
      return "mocha"
    end

    local test_script = pkg.scripts and pkg.scripts.test or ""
    if test_script:find("jest", 1, true) then
      return "jest"
    end
    if test_script:find("mocha", 1, true) then
      return "mocha"
    end
  end

  return "mocha"
end

local function use_npm_test(context, pkg)
  local runner = runner_config(context)
  if runner.use_npm == true then
    return true
  end
  if runner.use_npm == false then
    return false
  end
  if runner.npm_script then
    return true
  end
  return false
end

local function npm_script_name(context)
  local runner = runner_config(context)
  return runner.npm_script or "test"
end

local function append_runner_args(args, context)
  local runner = runner_config(context)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
end

local function append_filter_args(args, context, framework)
  local runner = runner_config(context)
  local pattern = runner.pattern or runner.grep

  if context.filters then
    pattern = pattern
      or context.filters.pattern
      or context.filters.name
      or (context.filters.names and context.filters.names[1])
  end

  if not pattern or pattern == "" then
    return
  end

  if framework == "jest" then
    table.insert(args, "--testNamePattern")
    table.insert(args, pattern)
  else
    table.insert(args, "--grep")
    table.insert(args, pattern)
  end
end

local function append_target_files(args, context, files)
  if context.filters and context.filters.paths then
    for _, path in ipairs(context.filters.paths) do
      table.insert(args, path)
    end
    return
  end

  if #files > 0 then
    for _, path in ipairs(files) do
      table.insert(args, path)
    end
  end
end

local function list_with_jest(context, root)
  local args = { "jest", "--listTests", "--json" }
  append_runner_args(args, context)
  append_filter_args(args, context, "jest")

  local result = sys.run("npx", args, { cwd = root })
  if result.exit_code ~= 0 or result.stdout == "" then
    return nil
  end

  local ok, data = pcall(json.decode, result.stdout)
  if ok and type(data) == "table" then
    return data
  end

  local tests = {}
  for line in result.stdout:gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" then
      table.insert(tests, line)
    end
  end
  if #tests > 0 then
    return tests
  end
  return nil
end

local function list_with_mocha(context, root)
  local args = { "mocha", "--dry-run", "--reporter", "min" }
  append_runner_args(args, context)
  append_filter_args(args, context, "mocha")

  local result = sys.run("npx", args, { cwd = root })
  if result.exit_code ~= 0 or result.stdout == "" then
    return nil
  end

  local tests = {}
  for line in result.stdout:gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" and not line:match("^Error") then
      table.insert(tests, line)
    end
  end
  if #tests > 0 then
    return tests
  end
  return nil
end

function list(context)
  local pkg, root = package_json(context)
  local framework = detect_framework(context, pkg)
  local tests

  if framework == "jest" then
    tests = list_with_jest(context, root)
  else
    tests = list_with_mocha(context, root)
  end

  if not tests or #tests == 0 then
    tests = discover_test_files(context)
  end

  return filter_test_ids(tests, context)
end

local function build_npx_test_command(context, for_coverage)
  local pkg, root = package_json(context)
  local framework = detect_framework(context, pkg)
  local files = discover_test_files(context)

  if use_npm_test(context, pkg) and not for_coverage then
    local args = { "run", npm_script_name(context) }
    append_runner_args(args, context)
    if #files > 0 or (context.filters and context.filters.paths) then
      table.insert(args, "--")
      append_target_files(args, context, files)
      append_filter_args(args, context, framework)
    end
    return {
      command = "npm",
      args = args,
      cwd = root,
      framework = framework,
    }
  end

  local args
  if framework == "jest" then
    args = { "jest", "--colors=false", "--verbose" }
  else
    args = { "mocha", "--colors", "--reporter", "spec" }
  end

  append_runner_args(args, context)
  append_filter_args(args, context, framework)
  append_target_files(args, context, files)

  return {
    command = "npx",
    args = args,
    cwd = root,
    framework = framework,
  }
end

function build_command(context)
  parse_state.current_file = nil
  return build_npx_test_command(context, false)
end

function build_coverage_run(context)
  local spec = build_npx_test_command(context, true)
  local runner = runner_config(context)
  local coverage = runner.coverage or {}
  local report = coverage.report or "coverage/lcov.info"

  local args = { "nyc" }
  if coverage.temp_dir then
    table.insert(args, "--temp-dir")
    table.insert(args, coverage.temp_dir)
  end

  local reporters = coverage.reporters or coverage.reporter or "lcov"
  if type(reporters) == "string" then
    reporters = { reporters }
  end
  for _, reporter in ipairs(reporters) do
    table.insert(args, "--reporter=" .. reporter)
  end

  if coverage.extension then
    if type(coverage.extension) == "string" then
      table.insert(args, "--extension")
      table.insert(args, coverage.extension)
    else
      for _, ext in ipairs(coverage.extension) do
        table.insert(args, "--extension")
        table.insert(args, ext)
      end
    end
  end

  if coverage.include then
    for _, pattern in ipairs(coverage.include) do
      table.insert(args, "--include")
      table.insert(args, pattern)
    end
  end

  if coverage.exclude then
    for _, pattern in ipairs(coverage.exclude) do
      table.insert(args, "--exclude")
      table.insert(args, pattern)
    end
  end

  table.insert(args, table.remove(spec.args, 1))
  for _, arg in ipairs(spec.args) do
    table.insert(args, arg)
  end

  return {
    command = "npx",
    args = args,
    cwd = spec.cwd,
    report = report,
    reporter = coverage.teez_reporter or "lcov",
    output = coverage.output,
    min_line_rate = coverage.min_line_rate,
  }
end

local function test_id(name)
  if parse_state.current_file and parse_state.current_file ~= "" then
    if name:find(parse_state.current_file, 1, true) == 1 then
      return name
    end
    return parse_state.current_file .. "::" .. name
  end
  return name
end

local function parse_pass_line(line)
  local name, duration_ms = line:match("^%s*[✓√]+%s+(.-)%s+%((%d+) ms%)$")
  if not name then
    name = line:match("^%s*[✓√]+%s+(.-)$")
  end
  if name then
    name = trim(name)
    local event = { event = "pass", id = test_id(name) }
    if duration_ms then
      event.duration_ms = tonumber(duration_ms)
    end
    return event
  end

  name, duration_ms = line:match("^%s*ok %d+%s+(.-)%s+%((%d+)ms%)$")
  if not name then
    name = line:match("^%s*ok %d+%s+(.+)$")
  end
  if name then
    name = trim(name)
    local event = { event = "pass", id = test_id(name) }
    if duration_ms then
      event.duration_ms = tonumber(duration_ms)
    end
    return event
  end

  return nil
end

local function parse_fail_line(line)
  local name, duration_ms = line:match("^%s*[✕×]+%s+(.-)%s+%((%d+) ms%)$")
  if not name then
    name = line:match("^%s*[✕×]+%s+(.-)$")
  end
  if name then
    name = trim(name)
    local event = { event = "fail", id = test_id(name), msg = line }
    if duration_ms then
      event.duration_ms = tonumber(duration_ms)
    end
    return event
  end

  name = line:match("^%s*not ok %d+%s+(.+)$")
  if name then
    return { event = "fail", id = test_id(trim(name)), msg = line }
  end

  name = line:match("^%s*%d+%)%s+(.+)$")
  if name then
    return { event = "fail", id = test_id(trim(name)), msg = line }
  end

  return nil
end

local function parse_skip_line(line)
  local name = line:match("^%s*ok %d+%s+(.-)%s+# SKIP")
  if name then
    return { event = "skip", id = test_id(trim(name)) }
  end

  name = line:match("^%s*%-%s+(.+)$")
  if name then
    return { event = "skip", id = test_id(trim(name)) }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local suite_event, suite_file = line:match("^(PASS)%s+(%S+)")
  if not suite_event then
    suite_event, suite_file = line:match("^(FAIL)%s+(%S+)")
  end
  if suite_file then
    parse_state.current_file = suite_file
    if suite_event == "PASS" then
      return { event = "pass", id = suite_file }
    end
    return { event = "fail", id = suite_file, msg = line }
  end

  local pass = parse_pass_line(line)
  if pass then
    return pass
  end

  local fail = parse_fail_line(line)
  if fail then
    return fail
  end

  local skip = parse_skip_line(line)
  if skip then
    return skip
  end

  if line:match("^%s*%d+) passing") or line:match("^Tests:%s+%d+ failed") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
