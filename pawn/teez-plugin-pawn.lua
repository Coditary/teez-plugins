local DEFAULT_INCLUDE = { "**/tests/**/*.pwn", "**/*_test.pwn" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local function runner_cfg(context)
  return context.runner or {}
end

local function merge_patterns(context)
  local runner = runner_cfg(context)
  local include = {}
  local exclude = {}

  for _, pattern in ipairs(DEFAULT_INCLUDE) do
    table.insert(include, pattern)
  end
  for _, pattern in ipairs(runner.include or {}) do
    table.insert(include, pattern)
  end

  for _, pattern in ipairs(DEFAULT_EXCLUDE) do
    table.insert(exclude, pattern)
  end
  for _, pattern in ipairs(runner.exclude or {}) do
    table.insert(exclude, pattern)
  end

  return include, exclude
end

local function is_excluded(path, exclude_patterns)
  for _, pattern in ipairs(exclude_patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function relativize(path, root)
  local prefix = root:gsub("/+$", "") .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

local function collect_test_scripts(context)
  local include_patterns, exclude_patterns = merge_patterns(context)
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if not is_excluded(path, exclude_patterns) then
        local id = relativize(path, context.target_path)
        if not seen[id] then
          seen[id] = true
          table.insert(tests, id)
        end
      end
    end
  end

  table.sort(tests)
  return tests
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

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function read_pawno_include_dirs(target_path)
  local cfg_path = target_path .. "/pawno.cfg"
  if not fs.exists(cfg_path) then
    return {}
  end

  local dirs = {}
  local result = sys.run("cat", { cfg_path })
  if result.exit_code ~= 0 then
    return dirs
  end

  for line in result.stdout:gmatch("[^\r\n]+") do
    local dir = line:match("^%-i(.+)$") or line:match("^%-i%s+(.+)$")
    if dir and dir ~= "" then
      table.insert(dirs, dir)
    end
  end
  return dirs
end

local function build_pawncc_args(context, test_file)
  local runner = runner_cfg(context)
  local args = {}

  append_args(args, runner.args)

  local include_dirs = runner.include_dirs
  if not include_dirs then
    include_dirs = read_pawno_include_dirs(context.target_path)
    if #include_dirs == 0 then
      include_dirs = { "include", "tests" }
    end
  end

  for _, dir in ipairs(include_dirs) do
    table.insert(args, "-i" .. dir)
  end

  if runner.defines then
    for _, define in ipairs(runner.defines) do
      table.insert(args, "-d" .. define)
    end
  end

  if runner.output_dir then
    local stem = test_file:match("([^/]+)%.pwn$") or "test"
    table.insert(args, "-o" .. runner.output_dir .. "/" .. stem .. ".amx")
  end

  table.insert(args, test_file)
  return args
end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function uses_sampctl(context)
  local runner = runner_cfg(context)
  return runner.sampctl == true or runner.mode == "sampctl"
end

local function resolve_compiler(context)
  local runner = runner_cfg(context)
  return runner.command or "pawncc"
end

local function resolve_test_targets(context)
  local tests = apply_filters(collect_test_scripts(context), context.filters)
  if #tests > 0 then
    return tests
  end
  return { "." }
end

function list(context)
  return apply_filters(collect_test_scripts(context), context.filters)
end

function build_command(context)
  local runner = runner_cfg(context)
  local targets = resolve_test_targets(context)

  if runner.test_command then
    local args = {}
    append_args(args, runner.test_args)
    append_args(args, targets)
    return {
      command = runner.test_command,
      args = args,
      env = runner.env,
      cwd = runner.cwd,
    }
  end

  if uses_sampctl(context) then
    local args = { "test" }
    append_args(args, runner.args)
    if #targets == 1 and targets[1] ~= "." then
      append_args(args, targets)
    end
    return {
      command = "sampctl",
      args = args,
      env = runner.env,
      cwd = runner.cwd or context.target_path,
    }
  end

  local compiler = resolve_compiler(context)
  local runner_bin = runner.runner

  if not runner_bin then
    if #targets == 1 then
      return {
        command = compiler,
        args = build_pawncc_args(context, targets[1]),
        env = runner.env,
        cwd = runner.cwd or context.target_path,
      }
    end

    local steps = {}
    for _, test_file in ipairs(targets) do
      local compile_args = build_pawncc_args(context, test_file)
      local compile_cmd = shell_quote(compiler)
      for _, arg in ipairs(compile_args) do
        compile_cmd = compile_cmd .. " " .. shell_quote(arg)
      end
      table.insert(steps, compile_cmd)
    end

    return {
      command = "sh",
      args = { "-c", table.concat(steps, " && ") },
      env = runner.env,
      cwd = runner.cwd or context.target_path,
    }
  end

  local steps = {}
  for _, test_file in ipairs(targets) do
    local compile_args = build_pawncc_args(context, test_file)
    local compile_cmd = shell_quote(compiler)
    for _, arg in ipairs(compile_args) do
      compile_cmd = compile_cmd .. " " .. shell_quote(arg)
    end
    table.insert(steps, compile_cmd)
  end

  local run_cmd = shell_quote(runner_bin)
  if runner.runner_args then
    for _, arg in ipairs(runner.runner_args) do
      run_cmd = run_cmd .. " " .. shell_quote(arg)
    end
  end

  table.insert(steps, run_cmd)

  return {
    command = "sh",
    args = { "-c", table.concat(steps, " && ") },
    env = runner.env,
    cwd = runner.cwd or context.target_path,
  }
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local pass_id = line:match("^PASS:?%s+(.+)$")
  if pass_id then
    return { event = "pass", id = pass_id }
  end

  local fail_id, fail_msg = line:match("^FAIL:?%s+([^:]+)%s*:%s*(.+)$")
  if not fail_id then
    fail_id, fail_msg = line:match("^FAIL:?%s+(%S+)%s*(.*)$")
  end
  if fail_id then
    local msg = fail_msg
    if msg == "" then
      msg = line
    end
    return { event = "fail", id = fail_id, msg = msg }
  end

  pass_id = line:match("^%[%+%]%s+(.+)$")
  if pass_id then
    return { event = "pass", id = pass_id }
  end

  fail_id, fail_msg = line:match("^%[%-%]%s+([^:]+)%s*:%s*(.+)$")
  if not fail_id then
    fail_id = line:match("^%[%-%]%s+(.+)$")
  end
  if fail_id then
    return { event = "fail", id = fail_id, msg = fail_msg or line }
  end

  local skip_id = line:match("^SKIP:?%s+(.+)$")
  if skip_id then
    return { event = "skip", id = skip_id }
  end

  if line:match("^=+$") or line:match("^%-+$") then
    return nil
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = runner_cfg(context)
  local coverage = runner.coverage
  if not coverage then
    return nil
  end

  if uses_sampctl(context) then
    local args = { "test", "--cover" }
    append_args(args, runner.args)
    return {
      command = "sampctl",
      args = args,
      cwd = runner.cwd or context.target_path,
      report = "coverage/lcov.info",
      reporter = "lcov",
      output = "coverage/teez.msgpack",
    }
  end

  local spec = build_command(context)
  if type(coverage) == "table" then
    if coverage.collect then
      spec.collect = coverage.collect
    end
    spec.report = coverage.report or "coverage/lcov.info"
    spec.reporter = coverage.reporter or "lcov"
    spec.output = coverage.output or "coverage/teez.msgpack"
    if coverage.min_line_rate then
      spec.min_line_rate = coverage.min_line_rate
    end
  else
    spec.report = "coverage/lcov.info"
    spec.reporter = "lcov"
    spec.output = "coverage/teez.msgpack"
  end

  return spec
end
