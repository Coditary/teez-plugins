local DEFAULT_INCLUDE = {
  "**/test/**",
  "**/*_test.pl",
  "**/tests/**",
}

local INCLUDE_GLOBS = {
  ["**/test/**"] = "**/test/**/*.pl",
  ["**/tests/**"] = "**/tests/**/*.pl",
  ["**/*_test.pl"] = "**/*_test.pl",
}

local RUN_SCRIPT_CANDIDATES = {
  "run_tests.pl",
  "scripts/run_tests.pl",
  "test/run_tests.pl",
  "tests/run_tests.pl",
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

local function is_prolog_file(path)
  return path:match("%.pl$") ~= nil
end

local function should_include_file(path, context)
  if not is_prolog_file(path) then
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

local function find_run_script(context)
  local runner = runner_config(context)
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
    goal = string.format("run_tests(%s)", shell_quote(context.filters.name))
  end

  if opts.wrap_coverage or runner.coverage then
    local cov_data = opts.coverage_data or runner.coverage_data or "coverage/plunit.cov"
    goal = string.format(
      "use_module(library(prolog_coverage)), coverage((%s)), cov_save_data(%s, [])",
      goal,
      shell_quote(cov_data)
    )
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

local function build_swipl_spec(context, opts)
  opts = opts or {}
  local runner = runner_config(context)
  local args = {}
  append_runner_args(args, context)

  local script = find_run_script(context)
  if script and not opts.force_file then
    table.insert(args, "-s")
    table.insert(args, script)
    return {
      command = "swipl",
      args = args,
      cwd = runner.cwd or context.target_path,
      env = runner.env,
    }
  end

  local target = context.target_path
  if not target:match("%.pl$") then
    local files = discover_test_files(context)
    if #files == 1 then
      target = files[1]
    elseif runner.entry then
      target = join_path(context.target_path, runner.entry)
    end
  end

  if not target:match("%.pl$") then
    error("prolog runner: no PlUnit test file found under " .. context.target_path)
  end

  table.insert(args, "-g")
  table.insert(args, build_goal(context, opts))
  table.insert(args, "-t")
  table.insert(args, "halt")
  table.insert(args, target)

  return {
    command = "swipl",
    args = args,
    cwd = runner.cwd or context.target_path,
    env = runner.env,
  }
end

function list(context)
  local tests = discover_test_files(context)
  return apply_filters(tests, context)
end

function build_command(context)
  return build_swipl_spec(context, {})
end

function build_coverage_run(context)
  local runner = runner_config(context)
  if not runner.coverage then
    return nil
  end

  local cov_data = runner.coverage_data or "coverage/plunit.cov"
  local spec = build_swipl_spec(context, {
    wrap_coverage = true,
    coverage_data = cov_data,
  })

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = spec.env,
    report = runner.coverage_report or cov_data,
    reporter = runner.coverage_reporter or "json",
    output = runner.coverage_output or "coverage/teez.msgpack",
    min_line_rate = runner.min_line_rate,
  }
end

local function parse_duration_sec(text)
  if not text then
    return nil
  end
  local seconds = tonumber(text)
  if not seconds then
    return nil
  end
  return math.floor(seconds * 1000 + 0.5)
end

local function parse_test_result(line)
  if not line:match("^%%") then
    return nil
  end

  local body = trim(line:sub(2))
  local duration_ms = parse_duration_sec(body:match("%(([0-9%.]+)%s*sec%)"))

  local name, status = body:match("^(.-)%s+%.+ (%*%*FAILED%*%*|%*%*FIXME%*%*|passed|failed|blocked|declined)")
  if not name then
    name, status = body:match("^(.-)%s+(%*%*FAILED%*%*|%*%*FIXME%*%*|passed|failed|blocked|declined)")
  end
  if not name or not status then
    return nil
  end

  name = trim(name)
  if status == "passed" then
    local event = { event = "pass", id = name }
    if duration_ms then
      event.duration_ms = duration_ms
    end
    return event
  end

  if status == "failed" or status == "**FAILED**" then
    local event = { event = "fail", id = name, msg = line }
    if duration_ms then
      event.duration_ms = duration_ms
    end
    return event
  end

  if status == "**FIXME**" or status == "blocked" or status == "declined" then
    return { event = "skip", id = name }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local module = line:match("^%% Started in plunit:(%S+)")
  if module then
    return { event = "start", id = module }
  end

  local result = parse_test_result(line)
  if result then
    return result
  end

  if line:match("^%% ERROR:") or line:match("^%% Warning:") then
    return { event = "output", text = line }
  end

  if line:match("^%% All %d+ tests passed") or line:match("^%% %d+ tests failed") then
    return { event = "output", text = line }
  end

  if line:match("^%%") then
    return nil
  end

  return { event = "output", text = line }
end
