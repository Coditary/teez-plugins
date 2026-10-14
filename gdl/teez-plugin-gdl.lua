local DEFAULT_INCLUDE = {
  "**/tests/**",
  "**/*_test.pro",
}

local INCLUDE_GLOBS = {
  ["**/tests/**"] = "**/tests/**/*.pro",
  ["**/*_test.pro"] = "**/*_test.pro",
}

local RUN_SCRIPT_CANDIDATES = {
  "run_tests.pro",
  "scripts/run_tests.pro",
  "test/run_tests.pro",
  "tests/run_tests.pro",
}

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function join_path(base, part)
  if not part or part == "" then
    return base
  end
  if part:sub(1, 1) == "/" then
    return part
  end
  if base:sub(-1) == "/" then
    return base .. part
  end
  return base .. "/" .. part
end

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
  return runner.exclude or {}
end

local function glob_patterns(context)
  local patterns = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    local glob = INCLUDE_GLOBS[pattern] or pattern
    if not seen[glob] then
      seen[glob] = true
      table.insert(patterns, glob)
    end
  end

  if #patterns == 0 then
    for _, glob in pairs(INCLUDE_GLOBS) do
      if not seen[glob] then
        seen[glob] = true
        table.insert(patterns, glob)
      end
    end
  end

  return patterns
end

local function is_pro_file(path)
  return path:match("%.pro$") ~= nil
end

local function should_include_file(path, context)
  if not is_pro_file(path) then
    return false
  end

  for _, pattern in ipairs(exclude_patterns(context)) do
    if filter.glob_match(path, pattern) then
      return false
    end
  end

  for _, pattern in ipairs(include_patterns(context)) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end

  return false
end

local function discover_test_files(context)
  local files = {}
  local seen = {}
  local root = context.target_path

  for _, pattern in ipairs(glob_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not seen[path] and should_include_file(path, context) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
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

local function resolve_executable(context)
  local runner = runner_config(context)
  if runner.gdl then
    return runner.gdl
  end
  if runner.idl then
    return runner.idl
  end
  if runner.executable then
    return runner.executable
  end
  return "gdl"
end

local function find_run_script(context)
  local runner = runner_config(context)
  if runner.command then
    local script = runner.command
    if fs.exists(join_path(context.target_path, script)) then
      return script
    end
    if fs.exists(script) then
      return script
    end
  end

  if runner.script then
    local script = runner.script
    if fs.exists(join_path(context.target_path, script)) then
      return script
    end
    if fs.exists(script) then
      return script
    end
  end

  for _, candidate in ipairs(RUN_SCRIPT_CANDIDATES) do
    local path = join_path(context.target_path, candidate)
    if fs.exists(path) then
      return candidate
    end
  end

  return nil
end

local function shell_quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function build_goal(context, opts)
  opts = opts or {}
  local runner = runner_config(context)
  local goal = runner.goal or "run_tests"

  if context.filters and context.filters.name and context.filters.name ~= "" then
    goal = string.format("run_tests, FILTER=%s", shell_quote(context.filters.name))
  end

  if opts.wrap_coverage or runner.coverage then
    local cov = runner.coverage
    if type(cov) == "table" and cov.goal then
      goal = cov.goal
    elseif runner.coverage_goal then
      goal = runner.coverage_goal
    else
      goal = string.format("run_tests, /COVERAGE")
    end
  end

  return goal
end

local function append_runner_args(args, context)
  local runner = runner_config(context)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
end

local function merge_env(spec, extra)
  if not extra then
    return
  end
  spec.env = spec.env or {}
  for key, value in pairs(extra) do
    spec.env[key] = value
  end
end

local function build_gdl_spec(context, opts)
  opts = opts or {}
  local runner = runner_config(context)
  local command = resolve_executable(context)
  local args = {}
  append_runner_args(args, context)

  local script = find_run_script(context)
  if script and not opts.force_file then
    table.insert(args, script)
    local spec = {
      command = command,
      args = args,
      cwd = runner.cwd or context.target_path,
    }
    merge_env(spec, runner.env)
    merge_env(spec, opts.env)
    return spec
  end

  local target = context.target_path
  if not target:match("%.pro$") then
    local files = discover_test_files(context)
    if #files == 1 then
      target = files[1]
    elseif runner.entry then
      target = join_path(context.target_path, runner.entry)
    end
  end

  if not target:match("%.pro$") then
    error("gdl runner: no test .pro file found under " .. context.target_path)
  end

  table.insert(args, "-e")
  table.insert(args, build_goal(context, opts))
  table.insert(args, target)

  local spec = {
    command = command,
    args = args,
    cwd = runner.cwd or context.target_path,
  }
  merge_env(spec, runner.env)
  merge_env(spec, opts.env)

  if opts.wrap_coverage or runner.coverage then
    spec.env = spec.env or {}
    spec.env.TEEZ_GDL_COVERAGE = "1"
    local cov = runner.coverage
    if type(cov) == "table" and cov.env then
      merge_env(spec, cov.env)
    end
  end

  return spec
end

function list(context)
  local tests = discover_test_files(context)
  return apply_filters(tests, context)
end

function build_command(context)
  return build_gdl_spec(context, {})
end

function build_coverage_run(context)
  local runner = runner_config(context)
  if not runner.coverage then
    return nil
  end

  local cov = runner.coverage
  if type(cov) ~= "table" then
    cov = {}
  end

  local spec = build_gdl_spec(context, {
    wrap_coverage = true,
    env = cov.env,
  })

  local collect = cov.collect
  if not collect and cov.collect_command then
    collect = {
      command = cov.collect_command,
      args = cov.collect_args or {},
    }
  end

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = spec.env,
    collect = collect,
    report = cov.report or runner.coverage_report or "coverage/gdl.lcov",
    reporter = cov.reporter or runner.coverage_reporter or "lcov",
    output = cov.output or runner.coverage_output or "coverage/teez.msgpack",
    min_line_rate = cov.min_line_rate or runner.min_line_rate,
  }
end

local function parse_duration_ms(text)
  if not text then
    return nil
  end
  local seconds = tonumber(text)
  if not seconds then
    return nil
  end
  return math.floor(seconds * 1000 + 0.5)
end

local function parse_pass_fail(line)
  local id, msg = line:match("^TEEZ%s+PASS:?%s+(.+)$")
  if id then
    return { event = "pass", id = trim(id) }
  end

  id, msg = line:match("^TEEZ%s+FAIL:?%s+([^:]+):%s*(.*)$")
  if id then
    return { event = "fail", id = trim(id), msg = trim(msg) ~= "" and trim(msg) or line }
  end

  id = line:match("^PASS:?%s+(.+)$")
  if id then
    return { event = "pass", id = trim(id) }
  end

  id, msg = line:match("^FAIL:?%s+([^:]+):%s*(.*)$")
  if id then
    return { event = "fail", id = trim(id), msg = trim(msg) ~= "" and trim(msg) or line }
  end

  id = line:match("^OK:?%s+(.+)$")
  if id then
    return { event = "pass", id = trim(id) }
  end

  id, msg = line:match("^FAILED:?%s+([^:]+):%s*(.*)$")
  if id then
    return { event = "fail", id = trim(id), msg = trim(msg) ~= "" and trim(msg) or line }
  end

  id = line:match("^Test%s+(%S+)%s+PASSED")
  if id then
    return { event = "pass", id = trim(id) }
  end

  id, msg = line:match("^Test%s+(%S+)%s+FAILED:?%s*(.*)$")
  if id then
    return { event = "fail", id = trim(id), msg = trim(msg) ~= "" and trim(msg) or line }
  end

  id = line:match("^%*%*%s*PASS%*%*%s+(.+)$")
  if id then
    return { event = "pass", id = trim(id) }
  end

  id, msg = line:match("^%*%*%s*FAIL%*%*%s+([^:]+):%s*(.*)$")
  if id then
    return { event = "fail", id = trim(id), msg = trim(msg) ~= "" and trim(msg) or line }
  end

  id, status = line:match("^(%S+)%s+%.+ (%*%*FAILED%*%*|passed|failed)")
  if id and status then
    if status == "passed" then
      return { event = "pass", id = trim(id) }
    end
    return { event = "fail", id = trim(id), msg = line }
  end

  return nil
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local start_id = line:match("^START:?%s+(.+)$")
    or line:match("^Running test:?%s+(.+)$")
    or line:match("^%*%*%s*Running%s+(.+)%s*%*%*%s*$")
  if start_id then
    return { event = "start", id = trim(start_id) }
  end

  local skip_id = line:match("^SKIP:?%s+(.+)$") or line:match("^TEEZ%s+SKIP:?%s+(.+)$")
  if skip_id then
    return { event = "skip", id = trim(skip_id) }
  end

  local result = parse_pass_fail(line)
  if result then
    local duration_ms = parse_duration_ms(line:match("%(([0-9%.]+)%s*s(ec)?%)"))
    if duration_ms then
      result.duration_ms = duration_ms
    end
    return result
  end

  if line:match("^[Ee]rror") or line:match("^%[Ee]rror") or line:match("^ERROR:") then
    return { event = "output", text = line }
  end

  if line:match("[Ff]ail") and line:match("[Tt]est") then
    local id = line:match("test%s+[\"']?([^\"']+)[\"']?")
      or line:match("Test%s+(%S+)")
    if id then
      return { event = "fail", id = trim(id), msg = line }
    end
  end

  return nil
end
