local DEFAULT_INCLUDE = { "**/*_test.v", "**/tests/**/*.v" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local function merge_patterns(base, extra)
  if not extra or #extra == 0 then
    return base
  end
  local merged = {}
  for _, pattern in ipairs(base) do
    table.insert(merged, pattern)
  end
  for _, pattern in ipairs(extra) do
    table.insert(merged, pattern)
  end
  return merged
end

local function runner_patterns(context)
  local runner = context.runner or {}
  local include = merge_patterns(DEFAULT_INCLUDE, runner.include)
  local exclude = merge_patterns(DEFAULT_EXCLUDE, runner.exclude)
  return include, exclude
end

local function path_matches_any(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_test_file(path, include, exclude)
  if not path:match("%.v$") then
    return false
  end
  if #exclude > 0 and path_matches_any(path, exclude) then
    return false
  end
  return path_matches_any(path, include)
end

local function dedupe(values)
  local seen = {}
  local out = {}
  for _, value in ipairs(values) do
    if not seen[value] then
      seen[value] = true
      table.insert(out, value)
    end
  end
  return out
end

local function collect_test_files(context)
  local include, exclude = runner_patterns(context)
  local files = {}

  for _, pattern in ipairs(include) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if is_test_file(path, include, exclude) then
        table.insert(files, path)
      end
    end
  end

  return dedupe(files)
end

local function apply_filters(ids, filters)
  if not filters then
    return ids
  end

  local filtered = {}
  for _, id in ipairs(ids) do
    if filter.matches({ id = id }, filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function filter_pattern(context)
  local runner = context.runner or {}
  if runner.pattern and runner.pattern ~= "" then
    return runner.pattern
  end
  if not context.filters then
    return nil
  end
  if context.filters.name and context.filters.name ~= "" then
    return context.filters.name
  end
  if context.filters.pattern and context.filters.pattern ~= "" then
    return context.filters.pattern
  end
  return nil
end

local function append_runner_args(args, context)
  local runner = context.runner or {}
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
end

local function resolve_paths(context)
  local target = context.target_path
  if target:match("_test%.v$") or target:match("/tests/") then
    return { target }
  end

  local files = collect_test_files(context)
  if #files > 0 then
    return files
  end

  return { target }
end

local function build_test_args(context, extra_args)
  local args = { "test", "-stats" }
  append_runner_args(args, context)

  if extra_args then
    for _, arg in ipairs(extra_args) do
      table.insert(args, arg)
    end
  end

  local pattern = filter_pattern(context)
  if pattern then
    table.insert(args, "-run")
    table.insert(args, pattern)
  end

  for _, path in ipairs(resolve_paths(context)) do
    table.insert(args, path)
  end

  return args
end

function list(context)
  local files = apply_filters(collect_test_files(context), context.filters)
  table.sort(files)
  return files
end

function build_command(context)
  return {
    command = "v",
    args = build_test_args(context),
  }
end

function build_coverage_run(context)
  local args = build_test_args(context, { "-coverage" })
  local runner = context.runner or {}

  return {
    command = "v",
    args = args,
    cwd = runner.cwd,
    report = runner.coverage_report or "lcov.info",
    reporter = runner.coverage_reporter or "lcov",
    output = runner.coverage_output or "coverage/lcov.info",
    min_line_rate = runner.min_line_rate,
  }
end

function parse_line(line)
  local status, duration_ms, id =
    line:match("^%s*(OK|FAIL)%s+%[%s*%d+/%s*%d+%]%s+(?:C:%s*)?(%d+%.?%d*)%s+ms%s+(.+)%s*$")

  if status and id then
    local event = status == "OK" and "pass" or "fail"
    local result = {
      event = event,
      id = id,
    }
    if duration_ms then
      result.duration_ms = math.floor(tonumber(duration_ms) + 0.5)
    end
    if event == "fail" then
      result.msg = id
    end
    return result
  end

  if line:match("^%s*SKIP%s+") then
    local skip_id = line:match("^%s*SKIP%s+%[%s*%d+/%s*%d+%]%s+%d+%.?%d*%s+ms%s+(.+)%s*$")
      or line:match("^%s*SKIP%s+(.+)%s*$")
    if skip_id then
      return { event = "skip", id = skip_id }
    end
  end

  if line:match("^%s*Running%s+%d+%s+tests") then
    return nil
  end

  if line:match("^%s*Summary:") then
    return { event = "output", text = line }
  end

  if line:match("^%-%-") or line:match("^%s*$") then
    return nil
  end

  return { event = "output", text = line }
end
