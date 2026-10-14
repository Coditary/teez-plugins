local DEFAULT_INCLUDE = { "**/*Test*.st", "**/Tests/**" }

local function runner(context)
  return context.runner or {}
end

local function require_command(runner_cfg)
  local command = runner_cfg.command
  if not command or command == "" then
    error("smalltalk runner: runners.smalltalk.command is required (e.g. 'pharo' or 'gst-tool')")
  end
  return command
end

local function include_patterns(context)
  local cfg = runner(context)
  if cfg.include and #cfg.include > 0 then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local cfg = runner(context)
  return cfg.exclude or {}
end

local function path_excluded(path, excludes)
  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function collect_test_files(context)
  local files = {}
  local seen = {}
  local excludes = exclude_patterns(context)

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if not seen[path] and not path_excluded(path, excludes) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
end

local function read_file(path)
  if fs.read then
    return fs.read(path)
  end
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function add_unique(list, seen, value)
  if value and value ~= "" and not seen[value] then
    seen[value] = true
    table.insert(list, value)
  end
end

local function discover_classes_from_content(content, ids, seen)
  if not content then
    return
  end

  for class_name in content:gmatch("subclass:%s*#([%w]+)") do
    if class_name:match("Test") then
      add_unique(ids, seen, class_name)
    end
  end

  for class_name in content:gmatch("([%w]*Test[%w]*)%s+extend") do
    add_unique(ids, seen, class_name)
  end

  for class_name, selector in content:gmatch("([%w]*Test[%w]*)>>#?([%w]+)") do
    add_unique(ids, seen, class_name .. ">>" .. selector)
  end
end

local function discover_from_files(context)
  local ids = {}
  local seen = {}

  for _, path in ipairs(collect_test_files(context)) do
    discover_classes_from_content(read_file(path), ids, seen)
  end

  table.sort(ids)
  return ids
end

local function apply_filters(ids, context)
  if not context.filters then
    return ids
  end

  local filtered = {}
  for _, id in ipairs(ids) do
    if filter.matches({ id = id }, context.filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function append_runner_args(args, cfg)
  append_args(args, cfg.args)
end

local function filter_env(context)
  if not context.filters then
    return nil
  end
  return { TEEZ_FILTERS = json.encode(context.filters) }
end

local function merge_env(context, extra)
  local env = filter_env(context) or {}
  if extra then
    for key, value in pairs(extra) do
      env[key] = value
    end
  end
  if next(env) == nil then
    return nil
  end
  return env
end

local function pharo_args(cfg, script, mode)
  local args = {}
  append_runner_args(args, cfg)

  local has_headless = false
  local has_image = false
  local has_script = false

  for _, value in ipairs(args) do
    if value == "-headless" or value == "--headless" then
      has_headless = true
    end
    if value:match("%.image$") then
      has_image = true
    end
    if value == "-script" or value == "--script" then
      has_script = true
    end
  end

  if not has_headless then
    table.insert(args, 1, "-headless")
  end

  if cfg.image and cfg.image ~= "" and not has_image then
    table.insert(args, cfg.image)
  end

  if script and script ~= "" and not has_script then
    table.insert(args, "-script")
    table.insert(args, script)
  end

  if mode == "list" and cfg.list_args then
    append_args(args, cfg.list_args)
  elseif mode == "run" and cfg.run_args then
    append_args(args, cfg.run_args)
  end

  return args
end

local function gst_args(cfg, script, mode)
  local args = {}
  append_runner_args(args, cfg)

  local has_script_flag = false
  for _, value in ipairs(args) do
    if value == "-f" or value == "--file" or value == "-b" or value == "--batch" then
      has_script_flag = true
      break
    end
  end

  if script and script ~= "" and not has_script_flag then
    table.insert(args, "-f")
    table.insert(args, script)
  end

  if mode == "list" and cfg.list_args then
    append_args(args, cfg.list_args)
  elseif mode == "run" and cfg.run_args then
    append_args(args, cfg.run_args)
  end

  return args
end

local function runner_script(cfg, mode)
  if mode == "list" then
    return cfg.list_script or cfg.script or "run-tests.st"
  end
  if mode == "coverage" then
    local cov = cfg.coverage or {}
    return cov.script or cfg.script or "run-tests.st"
  end
  return cfg.script or "run-tests.st"
end

local function build_runner_spec(context, mode)
  local cfg = runner(context)
  local command = require_command(cfg)
  local script = runner_script(cfg, mode)
  local args

  if command == "gst-tool" then
    args = gst_args(cfg, script, mode)
  else
    args = pharo_args(cfg, script, mode)
  end

  return {
    command = command,
    args = args,
    cwd = cfg.cwd or context.target_path,
    env = merge_env(context, cfg.env),
  }
end

local function parse_test_ids(output)
  local ids = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local id = line:match("^%s*([%w]+>>[%w]+)%s*$")
      or line:match("^%s*LIST%s+([%w]+>>[%w]+)%s*$")
      or line:match("^%s*([%w]*Test[%w]*)%s*$")

    add_unique(ids, seen, id)
  end

  table.sort(ids)
  return ids
end

function list(context)
  local cfg = runner(context)
  local ids

  if cfg.list_script or (cfg.command and cfg.script) then
    local spec = build_runner_spec(context, "list")
    local output = sys.exec(spec.command, spec.args, {
      env = spec.env,
      cwd = spec.cwd,
    })
    ids = parse_test_ids(output)
  else
    ids = discover_from_files(context)
  end

  return apply_filters(ids, context)
end

function build_command(context)
  return build_runner_spec(context, "run")
end

function build_list_command(context)
  return build_runner_spec(context, "list")
end

local function parse_result_line(line)
  local event, id, msg = line:match("^(PASS|FAIL|SKIP|START)%s+([^%s]+>>[^%s]+)%s*:?%s*(.*)$")
  if event then
    event = string.lower(event)
    if event == "fail" then
      return {
        event = "fail",
        id = id,
        msg = msg ~= "" and msg or line,
      }
    end
    return { event = event, id = id }
  end

  event, id, msg = line:match("^(passed|failed|skipped|error)%s+([^%s]+>>[^%s]+)%s*:?%s*(.*)$")
  if event then
    if event == "failed" or event == "error" then
      return {
        event = "fail",
        id = id,
        msg = msg ~= "" and msg or line,
      }
    end
    if event == "skipped" then
      return { event = "skip", id = id }
    end
    return { event = "pass", id = id }
  end

  local class, method, detail = line:match("^%s*([%w]+)>>#?([%w]+)%s*%-+%s*(.+)%s*$")
  if class and method then
    local id = class .. ">>" .. method
    local lower = detail:lower()
    if lower:match("^fail") or lower:match("error") or lower:match("assertion") then
      return { event = "fail", id = id, msg = detail }
    end
    if lower:match("^skip") then
      return { event = "skip", id = id }
    end
    return { event = "pass", id = id }
  end

  class, method = line:match("^%s*([%w]+)>>#?([%w]+)%s*$")
  if class and method then
    return { event = "pass", id = class .. ">>" .. method }
  end

  local failure_class, failure_method, failure_msg =
    line:match("^%s*FAILURE:?%s*([%w]+)>>#?([%w]+)%s*[:%-]+%s*(.+)%s*$")
  if failure_class and failure_method then
    return {
      event = "fail",
      id = failure_class .. ">>" .. failure_method,
      msg = failure_msg,
    }
  end

  local err_class, err_method, err_msg =
    line:match("^%s*ERROR:?%s*([%w]+)>>#?([%w]+)%s*[:%-]+%s*(.+)%s*$")
  if err_class and err_method then
    return {
      event = "fail",
      id = err_class .. ">>" .. err_method,
      msg = err_msg,
    }
  end

  return nil
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  line = line:match("^%s*(.-)%s*$")

  if line == "" then
    return nil
  end

  if line:match("^%+=%s*") or line:match("^%-=%s*") then
    return nil
  end

  if line:match("^%s*%.+%s*$") and not line:find(">>") then
    return nil
  end

  if line:match("^Ran %d+ tests") or line:match("^%d+ tests? passed") then
    return nil
  end

  local parsed = parse_result_line(line)
  if parsed then
    return parsed
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local cfg = runner(context)
  local cov = cfg.coverage
  if not cov then
    return nil
  end

  local spec = build_runner_spec(context, "coverage")
  local env = {}
  if cfg.env then
    for key, value in pairs(cfg.env) do
      env[key] = value
    end
  end
  if cov.env then
    for key, value in pairs(cov.env) do
      env[key] = value
    end
  end

  local coverage_run = {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = merge_env(context, env),
    report = cov.report or "coverage/smalltalk.lcov",
    reporter = cov.reporter or "lcov",
    output = cov.output or "coverage/teez.msgpack",
  }

  if cov.collect then
    coverage_run.collect = cov.collect
  end

  if cov.min_line_rate then
    coverage_run.min_line_rate = cov.min_line_rate
  end

  return coverage_run
end
