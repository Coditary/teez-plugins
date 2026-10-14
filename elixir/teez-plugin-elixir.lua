local DEFAULT_INCLUDE = { "**/test/**/*_test.exs" }

local function target_path(context)
  return context.target_path or "."
end

local function include_patterns(context)
  if context.runner and context.runner.include then
    return context.runner.include
  end
  return DEFAULT_INCLUDE
end

local function path_excluded(path, pattern)
  return filter.glob_match(path, pattern)
end

local function resolve_glob_hit(target, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  if target == "." then
    return file
  end
  return target .. "/" .. file
end

local function runner_targets(context)
  local target = target_path(context)
  local patterns = include_patterns(context)

  local paths = {}
  local seen = {}
  for _, pattern in ipairs(patterns) do
    for _, file in ipairs(fs.glob(target, pattern)) do
      local resolved = resolve_glob_hit(target, file)
      local excluded = false
      if context.runner and context.runner.exclude then
        for _, exclude_pattern in ipairs(context.runner.exclude) do
          if path_excluded(resolved, exclude_pattern) then
            excluded = true
            break
          end
        end
      end
      if not excluded and not seen[resolved] then
        seen[resolved] = true
        table.insert(paths, resolved)
      end
    end
  end

  if #paths == 0 then
    return { target }
  end
  return paths
end

local function strip_ansi(line)
  return line:gsub("%\27%[[%d;]*m", "")
end

local function collect_test_ids(context)
  return runner_targets(context)
end

local function filter_test_ids(ids, context)
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

local function command_targets(context)
  local ids = filter_test_ids(collect_test_ids(context), context)
  if #ids > 0 then
    return ids
  end
  return runner_targets(context)
end

local function append_runner_args(args, context)
  if not context.runner then
    return
  end

  if context.runner.pattern then
    table.insert(args, "--only")
    table.insert(args, context.runner.pattern)
  end

  if context.runner.coverage then
    table.insert(args, "--cover")
  end

  if context.runner.args then
    for _, arg in ipairs(context.runner.args) do
      table.insert(args, arg)
    end
  end
end

local function build_mix_test_args(context)
  local args = { "test", "--color", "never" }
  append_runner_args(args, context)
  for _, target in ipairs(command_targets(context)) do
    table.insert(args, target)
  end
  return args
end

function list(context)
  return filter_test_ids(collect_test_ids(context), context)
end

function build_command(context)
  return {
    command = "mix",
    args = build_mix_test_args(context),
    env = { NO_COLOR = "1" },
  }
end

function build_list_command(context)
  local args = { "test", "--trace", "--color", "never" }
  append_runner_args(args, context)
  for _, target in ipairs(command_targets(context)) do
    table.insert(args, target)
  end
  return {
    command = "mix",
    args = args,
    env = { NO_COLOR = "1" },
  }
end

function build_coverage_run(context)
  local runner = {}
  if context.runner then
    for key, value in pairs(context.runner) do
      runner[key] = value
    end
  end
  runner.coverage = true

  return build_command({
    target_path = context.target_path,
    command = context.command,
    filters = context.filters,
    runner = runner,
  })
end

function parse_line(line)
  line = strip_ansi(line)

  local name, module = line:match("^%s*%d+%)%s+(.+)%s+%(([^)]+)%)$")
  if name and module then
    return { event = "fail", id = name .. " (" .. module .. ")", msg = line }
  end

  local trace_name = line:match("^%s*%*%s+(.+)%s+%([%d.]+ms%)")
  if trace_name then
    return { event = "pass", id = trace_name }
  end

  local test_name, test_module = line:match("^%s*(.+)%s+%(([^)]+)%)$")
  if test_name and test_module and not test_name:match("^%d+%)") and not test_name:match("%[") then
    return { event = "pass", id = test_name .. " (" .. test_module .. ")" }
  end

  local file_line = line:match("^%s*([%w%./_%-]+%_test%.exs:%d+)%s*$")
  if file_line then
    return { event = "start", id = file_line }
  end

  if line:match("^%s*%.+%s*$") and not line:match("%a") then
    local count = 0
    for _ in line:gmatch("%.") do
      count = count + 1
    end
    if count > 0 then
      return { event = "output", text = line }
    end
  end

  if line:match("%d+ tests?, %d+ failures?") or line:match("^Finished in ") then
    return { event = "output", text = line }
  end

  if line:match("^%s*%{.+}%s*$") or line:match("Excluded by filter") then
    return { event = "skip", id = line }
  end

  return nil
end
