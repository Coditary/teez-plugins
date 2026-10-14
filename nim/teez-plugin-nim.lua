local DEFAULT_INCLUDE = {
  "**/tests/**/*.nim",
  "**/*_test.nim",
}

local function runner_cfg(context)
  return (context and context.runner) or {}
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if cfg.include then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local cfg = runner_cfg(context)
  return cfg.exclude or {}
end

local function resolve_glob_hit(target, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  if target == "." or target == "" then
    return file
  end
  return target .. "/" .. file
end

local function is_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function runner_targets(context)
  local target = context.target_path or "."
  local includes = include_patterns(context)
  local excludes = exclude_patterns(context)
  local paths = {}
  local seen = {}

  for _, pattern in ipairs(includes) do
    for _, file in ipairs(fs.glob(target, pattern)) do
      local resolved = resolve_glob_hit(target, file)
      if not is_excluded(resolved, excludes) and not seen[resolved] then
        seen[resolved] = true
        table.insert(paths, resolved)
      end
    end
  end

  table.sort(paths)
  if #paths > 0 then
    return paths
  end
  return { target }
end

local function find_nimble_root(start_path)
  local path = start_path or "."
  if path == "" then
    path = "."
  end

  local current = path
  for _ = 1, 32 do
    local matches = fs.glob(current, "*.nimble")
    if #matches > 0 then
      return current, resolve_glob_hit(current, matches[1])
    end

    if current == "." or current == "/" then
      break
    end

    local parent = current:match("^(.*)/[^/]+$")
    if not parent or parent == current then
      parent = "."
    end
    current = parent
  end

  return nil, nil
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
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

local function run_mode(context)
  local cfg = runner_cfg(context)
  if cfg.run_mode then
    return cfg.run_mode
  end
  return "auto"
end

local function should_use_nimble(context, _targets)
  local mode = run_mode(context)
  if mode == "file" then
    return false
  end

  local nimble_root = find_nimble_root(context.target_path)
  if not nimble_root then
    return false
  end
  if mode == "nimble" then
    return true
  end

  local target = context.target_path or "."
  if target:match("%.nim$") then
    return false
  end

  if context.filters and context.filters.names then
    return false
  end

  return true
end

local function nim_compile_args(context, coverage)
  local args = { "c", "-r", "--hints:off", "--warnings:off" }
  local cfg = runner_cfg(context)

  if coverage then
    local cov = cfg.coverage or {}
    local backend = cov.backend or "gcov"
    if backend == "llvm" then
      table.insert(args, "--cc:clang")
      table.insert(args, "--passC:-fprofile-instr-generate")
      table.insert(args, "--passL:-fprofile-instr-generate")
    else
      table.insert(args, "--gcov:stdlib")
    end
  end

  append_args(args, cfg.nim_args)
  return args
end

local function shell_quote(value)
  if value:find("'", 1, true) then
    return '"' .. value:gsub('"', '\\"') .. '"'
  end
  return "'" .. value .. "'"
end

local function build_file_run(context, targets, coverage)
  local nimble_root = find_nimble_root(context.target_path)
  local cwd = nimble_root or context.target_path or "."
  local cfg = runner_cfg(context)
  local commands = {}

  for _, target in ipairs(targets) do
    local parts = { "nim" }
    for _, arg in ipairs(nim_compile_args(context, coverage)) do
      table.insert(parts, shell_quote(arg))
    end
    table.insert(parts, shell_quote(target))
    table.insert(commands, table.concat(parts, " "))
  end

  return {
    command = "sh",
    args = { "-c", table.concat(commands, " && ") },
    cwd = cwd,
  }
end

function list(context)
  local tests = runner_targets(context)
  return apply_filters(tests, context.filters)
end

function build_command(context)
  local targets = apply_filters(runner_targets(context), context.filters)
  local cfg = runner_cfg(context)
  local nimble_root = find_nimble_root(context.target_path)
  local cwd = nimble_root or context.target_path or "."

  if should_use_nimble(context, targets) and nimble_root then
    local args = { "test" }
    append_args(args, cfg.args)
    return {
      command = "nimble",
      args = args,
      cwd = cwd,
    }
  end

  if #targets == 0 or (targets[1] == (context.target_path or ".") and #targets == 1) then
    local discovered = runner_targets(context)
    if #discovered > 0 and discovered[1] ~= (context.target_path or ".") then
      targets = discovered
    end
  end

  return build_file_run(context, targets, false)
end

local current_suite = nil
local last_failed_id = nil

function parse_line(line)
  if line == "" then
    return nil
  end

  local suite = line:match("^%[Suite%]%s+(.+)%s*$")
  if suite then
    current_suite = suite
    last_failed_id = nil
    return nil
  end

  local ok_name = line:match("^%s*%[OK%]%s+(.+)%s*$")
  if ok_name then
    local id = ok_name
    if current_suite then
      id = current_suite .. "::" .. ok_name
    end
    last_failed_id = nil
    return { event = "pass", id = id }
  end

  local skipped_name = line:match("^%s*%[SKIPPED%]%s+(.+)%s*$")
  if skipped_name then
    local id = skipped_name
    if current_suite then
      id = current_suite .. "::" .. skipped_name
    end
    last_failed_id = nil
    return { event = "skip", id = id }
  end

  local failed_name = line:match("^%s*%[FAILED%]%s+(.+)%s*$")
  if failed_name then
    local id = failed_name
    if current_suite then
      id = current_suite .. "::" .. failed_name
    end
    last_failed_id = id
    return { event = "fail", id = id, msg = "FAILED" }
  end

  local dots_ok = line:match("^%s+(.+)%s+%.%.%.%s+OK")
  if dots_ok then
    local id = dots_ok
    if current_suite then
      id = current_suite .. "::" .. dots_ok
    end
    last_failed_id = nil
    return { event = "pass", id = id }
  end

  local dots_failed = line:match("^%s+(.+)%s+%.%.%.%s+FAILED")
  if dots_failed then
    local id = dots_failed
    if current_suite then
      id = current_suite .. "::" .. dots_failed
    end
    last_failed_id = id
    return { event = "fail", id = id, msg = "FAILED" }
  end

  if line:match("^%s+Error:") or line:match("^Error:") then
    local id = last_failed_id or "compile"
    return { event = "fail", id = id, msg = line:match("^%s*(.+)$") }
  end

  if last_failed_id and line:match("^%s+%S") then
    return { event = "output", text = line }
  end

  return nil
end

local function effective_coverage_cfg(context)
  local cfg = runner_cfg(context)
  local cov = {}
  if config and config.coverage then
    for key, value in pairs(config.coverage) do
      cov[key] = value
    end
  end
  if cfg.coverage then
    for key, value in pairs(cfg.coverage) do
      cov[key] = value
    end
  end
  return cov
end

function build_coverage_run(context)
  local cov = effective_coverage_cfg(context)
  local tool = cov.tool or "gcovr"
  local backend = cov.backend or "gcov"
  local targets = apply_filters(runner_targets(context), context.filters)
  local run = build_file_run(context, targets, true)

  if should_use_nimble(context, targets) and find_nimble_root(context.target_path) then
    local cfg = runner_cfg(context)
    local args = { "test" }
    append_args(args, cfg.args)
    if backend == "llvm" then
      table.insert(args, "--passNimFlags:--cc:clang")
      table.insert(args, "--passNimFlags:--passC:-fprofile-instr-generate")
      table.insert(args, "--passNimFlags:--passL:-fprofile-instr-generate")
    else
      table.insert(args, "--passNimFlags:--gcov:stdlib")
    end
    run = {
      command = "nimble",
      args = args,
      cwd = run.cwd,
    }
  end

  local collect
  if tool == "llvm-cov" or backend == "llvm" then
    collect = {
      command = "sh",
      args = {
        "-c",
        "llvm-profdata merge -sparse default.profraw -o default.profdata && "
          .. "llvm-cov export -instr-profile=default.profdata "
          .. (cov.binary or "tests/test_all") .. " -format=lcov > "
          .. (cov.report or "coverage/lcov.info"),
      },
    }
  else
    collect = {
      command = "gcovr",
      args = cov.collect_args or {
        "--root",
        ".",
        "--exclude-unreachable-branches",
        "--exclude-throw-branches",
        "--print-summary",
        "-o",
        cov.report or "coverage/lcov.info",
      },
    }
  end

  return {
    command = run.command,
    args = run.args,
    cwd = run.cwd,
    collect = collect,
    report = cov.report or "coverage/lcov.info",
    reporter = cov.reporter or "msgpack",
    output = cov.output or "coverage/teez.msgpack",
    min_line_rate = cov.min_line_rate,
  }
end
