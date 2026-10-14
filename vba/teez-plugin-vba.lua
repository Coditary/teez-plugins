-- teez VBA runner — Rubberduck or any CLI that emits Rubberduck/JUnit-like lines.
-- Windows-only in practice; configure runners.vba.command for your test harness.

local DEFAULT_COMMAND = "rubberduck"

local function runner_config(context)
  return context.runner or {}
end

local function include_patterns(context)
  local runner = runner_config(context)
  if runner.include and #runner.include > 0 then
    return runner.include
  end
  return { "**/*Tests.bas", "**/Tests/**" }
end

local function exclude_patterns(context)
  local runner = runner_config(context)
  local patterns = { "**/*.teez.lua" }
  if runner.exclude then
    for _, pattern in ipairs(runner.exclude) do
      table.insert(patterns, pattern)
    end
  end
  return patterns
end

local function is_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function module_name(path)
  local name = path:match("([^/\\]+)$") or path
  return (name:gsub("%.bas$", ""))
end

local function collect_test_files(context)
  local root = context.target_path
  local files = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not seen[path] and path:match("%.bas$") and not is_excluded(path, exclude_patterns(context)) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function parse_test_methods(path)
  local content = read_file(path)
  local module = module_name(path)
  if not content then
    return { module }
  end

  local tests = {}
  local seen = {}

  for line in content:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    local method

    local annotated = trimmed:match("^['\"]@TestMethod[^'\"]*['\"]%s+.*%s+Sub%s+(%w+)")
      or trimmed:match("^['\"]@TestMethod[^'\"]*['\"]%s+.*%s+Function%s+(%w+)")
      or trimmed:match("^@TestMethod%s+.*%s+Sub%s+(%w+)")
      or trimmed:match("^@TestMethod%s+.*%s+Function%s+(%w+)")
    if annotated then
      method = annotated
    end

    if not method then
      local plain = trimmed:match("^(?:Public%s+|Private%s+)?Sub%s+(Test[%w_]*)%s*%(")
        or trimmed:match("^(?:Public%s+|Private%s+)?Function%s+(Test[%w_]*)%s*%(")
      if plain then
        method = plain
      end
    end

    if method and not seen[method] then
      seen[method] = true
      table.insert(tests, module .. "." .. method)
    end
  end

  if #tests == 0 then
    table.insert(tests, module)
  end

  return tests
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

local function command_name(context)
  local runner = runner_config(context)
  return runner.command or DEFAULT_COMMAND
end

local function append_unique(args, value)
  if value and value ~= "" then
    table.insert(args, value)
  end
end

local function build_base_args(context, mode)
  local runner = runner_config(context)
  local args = {}

  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end

  if mode == "list" and runner.list_args then
    for _, arg in ipairs(runner.list_args) do
      table.insert(args, arg)
    end
  elseif mode == "run" and runner.run_args then
    for _, arg in ipairs(runner.run_args) do
      table.insert(args, arg)
    end
  end

  local use_defaults = command_name(context) == DEFAULT_COMMAND
  if mode == "list" then
    local subcommand = runner.list_subcommand
    if subcommand == nil and use_defaults then
      subcommand = "list"
    end
    append_unique(args, subcommand)
  else
    local subcommand = runner.run_subcommand
    if subcommand == nil and use_defaults then
      subcommand = "run"
    end
    append_unique(args, subcommand)
  end

  append_unique(args, context.target_path)

  if context.filters then
    if runner.filter_flag then
      table.insert(args, runner.filter_flag)
      table.insert(args, json.encode(context.filters))
    elseif runner.filters_env then
      -- handled via env below
    end
  end

  return args
end

local function build_env(context)
  local runner = runner_config(context)
  local env = {}

  if runner.env then
    for key, value in pairs(runner.env) do
      env[key] = value
    end
  end

  if context.filters and runner.filters_env then
    env[runner.filters_env] = json.encode(context.filters)
  end

  if next(env) == nil then
    return nil
  end
  return env
end

function list(context)
  local tests = {}

  for _, path in ipairs(collect_test_files(context)) do
    for _, id in ipairs(parse_test_methods(path)) do
      table.insert(tests, id)
    end
  end

  if #tests == 0 and runner_config(context).list_command then
    local runner = runner_config(context)
    local result = sys.run(runner.list_command, build_base_args(context, "list"), {
      env = build_env(context),
      cwd = runner.cwd,
    })
    if result.exit_code == 0 then
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local id = line:match("^%s*(%S+%.%S+)%s*$")
          or line:match("^%s*PASS%s+(%S+)%s*$")
          or line:match("^%s*TEST%s+(%S+)%s*$")
        if id then
          table.insert(tests, id)
        end
      end
    end
  end

  return apply_filters(tests, context)
end

function build_command(context)
  local runner = runner_config(context)
  local spec = {
    command = command_name(context),
    args = build_base_args(context, "run"),
    env = build_env(context),
  }

  if runner.cwd then
    spec.cwd = runner.cwd
  end

  return spec
end

function build_list_command(context)
  local runner = runner_config(context)
  if not runner.list_command and command_name(context) == DEFAULT_COMMAND then
    return nil
  end

  local spec = {
    command = runner.list_command or command_name(context),
    args = build_base_args(context, "list"),
    env = build_env(context),
  }

  if runner.cwd then
    spec.cwd = runner.cwd
  end

  return spec
end

local function parse_result_line(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil
  end

  local pass_patterns = {
    "^PASS%s+(%S+)%s*$",
    "^%[PASS%]%s+(%S+)%s*$",
    "^ok%s+%d+%s+(%S+)%s*$",
    "^%+%s+(%S+)%s+Passed%s*$",
    "^(%S+%.%S+)%s+%.?%.?%.?Passed%s*$",
    "^Test%s+'([^']+)'%s+passed%s*$",
    "^<testcase[^>]+name=\"([^\"]+)\"[^>]+/>%s*$",
  }
  for _, pattern in ipairs(pass_patterns) do
    local id, duration = trimmed:match(pattern)
    if id then
      local event = { event = "pass", id = id }
      if duration then
        event.duration_ms = tonumber(duration)
      end
      local inline_duration = trimmed:match("%(([%d%.]+)s%)%s*$")
      if inline_duration then
        event.duration_ms = math.floor(tonumber(inline_duration) * 1000)
      end
      return event
    end
  end

  local fail_patterns = {
    "^FAIL%s+(%S+)%s*:%s*(.*)$",
    "^%[FAIL%]%s+(%S+)%s*:%s*(.*)$",
    "^not ok%s+%d+%s+(%S+)%s*[-:]%s*(.*)$",
    "^%-%s+(%S+)%s+Failed%s*[-:]%s*(.*)$",
    "^(%S+%.%S+)%s+%.?%.?%.?Failed%s*[-:]%s*(.*)$",
    "^Test%s+'([^']+)'%s+failed%s*:%s*(.*)$",
    "^<testcase[^>]+name=\"([^\"]+)\"[^>]*>.*<failure[^>]*>(.*)</failure>",
  }
  for _, pattern in ipairs(fail_patterns) do
    local id, msg = trimmed:match(pattern)
    if id then
      return { event = "fail", id = id, msg = msg or trimmed }
    end
  end

  local skip_patterns = {
    "^SKIP%s+(%S+)%s*(.*)$",
    "^%[SKIP%]%s+(%S+)%s*(.*)$",
    "^#%s*SKIP%s+(%S+)%s*(.*)$",
    "^(%S+%.%S+)%s+%.?%.?%.?Skipped%s*(.*)$",
    "^<testcase[^>]+name=\"([^\"]+)\"[^>]+skipped[^>]*/>%s*$",
  }
  for _, pattern in ipairs(skip_patterns) do
    local id, msg = trimmed:match(pattern)
    if id then
      local event = { event = "skip", id = id }
      if msg and msg ~= "" then
        event.msg = msg
      end
      return event
    end
  end

  local start_patterns = {
    "^START%s+(%S+)%s*$",
    "^%[RUN%]%s+(%S+)%s*$",
    "^Running%s+(%S+%.%S+)%s*$",
  }
  for _, pattern in ipairs(start_patterns) do
    local id = trimmed:match(pattern)
    if id then
      return { event = "start", id = id }
    end
  end

  if trimmed:match("^%s*<") or trimmed:match("^%s*</") then
    return nil
  end

  return { event = "output", text = trimmed }
end

function parse_line(line)
  return parse_result_line(line)
end

function build_coverage_run(context)
  local runner = runner_config(context)
  if not runner.coverage then
    return nil
  end

  local coverage = runner.coverage
  if type(coverage) ~= "table" then
    coverage = { enabled = true }
  end

  local spec = {
    command = coverage.command or command_name(context),
    args = coverage.args or build_base_args(context, "run"),
    cwd = coverage.cwd or runner.cwd,
    env = build_env(context),
    report = coverage.report or "coverage/vba-lcov.info",
    reporter = coverage.reporter or "lcov",
    output = coverage.output or "coverage/teez.msgpack",
    min_line_rate = coverage.min_line_rate,
  }

  if coverage.collect then
    spec.collect = coverage.collect
  elseif coverage.collect_command then
    spec.collect = {
      command = coverage.collect_command,
      args = coverage.collect_args or {},
    }
  end

  if coverage.env then
    spec.env = spec.env or {}
    for key, value in pairs(coverage.env) do
      spec.env[key] = value
    end
  end

  local coverage_flag = coverage.flag or runner.coverage_flag
  if coverage_flag then
    table.insert(spec.args, coverage_flag)
  end

  return spec
end
