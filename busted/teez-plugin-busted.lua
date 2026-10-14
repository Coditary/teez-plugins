local DEFAULT_INCLUDE = { "**/*_spec.lua", "**/spec/**" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local function runner_opts(context)
  return context.runner or {}
end

local function patterns(context, key, defaults)
  local runner = runner_opts(context)
  local value = runner[key]
  if type(value) == "table" and #value > 0 then
    return value
  end
  return defaults
end

local function is_excluded(path, excludes)
  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function discover_spec_files(context)
  local root = context.target_path
  local includes = patterns(context, "include", DEFAULT_INCLUDE)
  local excludes = patterns(context, "exclude", DEFAULT_EXCLUDE)
  local files = {}
  local seen = {}

  for _, pattern in ipairs(includes) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not seen[path] and not is_excluded(path, excludes) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
end

local function append_runner_args(args, runner)
  if type(runner.args) == "table" then
    for _, value in ipairs(runner.args) do
      table.insert(args, value)
    end
  end
end

local function append_filter_args(args, context)
  local filters = context.filters
  if not filters then
    return
  end

  for _, entry in ipairs(filters) do
    if type(entry) == "table" then
      if entry.name and entry.name ~= "" then
        table.insert(args, "--filter=" .. entry.name)
      elseif entry.pattern and entry.pattern ~= "" then
        table.insert(args, "--filter=" .. entry.pattern)
      end
    elseif type(entry) == "string" and entry ~= "" then
      table.insert(args, "--filter=" .. entry)
    end
  end
end

local function append_targets(args, context)
  local files = discover_spec_files(context)
  if #files == 0 then
    table.insert(args, context.target_path)
    return
  end

  for _, path in ipairs(files) do
    table.insert(args, path)
  end
end

local function build_busted_args(context, list_mode)
  local runner = runner_opts(context)
  local args = {}

  if list_mode then
    table.insert(args, "--list")
  else
    local output = runner.output or "TAP"
    table.insert(args, "--output=" .. output)
    if runner.verbose then
      table.insert(args, "-v")
    end
  end

  append_filter_args(args, context)
  append_runner_args(args, runner)
  append_targets(args, context)

  return args
end

local function trim(line)
  return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_list_line(line)
  local trimmed = trim(line)
  if trimmed == "" then
    return nil
  end

  trimmed = trimmed:gsub("^[●✱◼◆]%s+", "")
  trimmed = trim(trimmed)

  if trimmed == "" then
    return nil
  end

  return trimmed
end

local function apply_filters(tests, filters)
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

local function list_from_busted(context)
  local args = build_busted_args(context, true)
  local output = sys.exec("busted", args)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local id = parse_list_line(line)
    if id and not seen[id] then
      seen[id] = true
      table.insert(tests, id)
    end
  end

  return tests
end

function list(context)
  local runner = runner_opts(context)
  local tests

  if runner.list_mode == "discovery" then
    tests = discover_spec_files(context)
  else
    local ok, result = pcall(function()
      return list_from_busted(context)
    end)

    if ok and type(result) == "table" and #result > 0 then
      tests = result
    else
      tests = discover_spec_files(context)
    end
  end

  return apply_filters(tests, context.filters)
end

function build_command(context)
  local runner = runner_opts(context)
  local spec = {
    command = "busted",
    args = build_busted_args(context, false),
  }

  if type(runner.env) == "table" then
    spec.env = runner.env
  end

  if runner.cwd then
    spec.cwd = runner.cwd
  end

  return spec
end

local function parse_tap_line(line)
  local pass_id = line:match("^ok %d+ %- (.*)$")
  if pass_id then
    local skip_reason = pass_id:match(" # SKIP(.*)$")
    if skip_reason then
      return {
        event = "skip",
        id = pass_id:gsub(" # SKIP.*$", ""),
        msg = trim(skip_reason),
      }
    end
    return { event = "pass", id = pass_id }
  end

  local fail_id = line:match("^not ok %d+ %- (.*)$")
  if fail_id then
    return { event = "fail", id = fail_id, msg = line }
  end

  local duration_ms = line:match("^# duration: (%d+)ms$")
  if duration_ms then
    return { event = "output", text = line }
  end

  if line:match("^#") then
    return { event = "output", text = line }
  end

  return nil
end

local function parse_plain_line(line)
  local pass_id = line:match("^%s*●%s+(.+)$")
  if pass_id then
    return { event = "pass", id = trim(pass_id) }
  end

  local fail_id = line:match("^%s*✱%s+(.+)$")
  if fail_id then
    return { event = "fail", id = trim(fail_id), msg = line }
  end

  local pending_id = line:match("^%s*[◼◆]%s+(.+)$")
  if pending_id then
    return { event = "skip", id = trim(pending_id) }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local tap = parse_tap_line(line)
  if tap then
    return tap
  end

  local plain = parse_plain_line(line)
  if plain then
    return plain
  end

  if line:match("^%s+") and not line:match("^%s*#") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  local coverage = runner.coverage or {}
  local spec = build_command(context)

  local args = { "--coverage" }
  for _, value in ipairs(spec.args) do
    table.insert(args, value)
  end

  local cwd = spec.cwd or context.target_path
  local collect_command = coverage.collect_command or "luacov"
  local collect_args = coverage.collect_args or {}

  return {
    command = spec.command,
    args = args,
    cwd = cwd,
    env = spec.env,
    collect = {
      command = collect_command,
      args = collect_args,
      cwd = coverage.collect_cwd or cwd,
    },
    report = coverage.report or "luacov.report.out",
    reporter = coverage.reporter or "lcov",
    output = coverage.output or "coverage/teez.msgpack",
    min_line_rate = coverage.min_line_rate,
  }
end
