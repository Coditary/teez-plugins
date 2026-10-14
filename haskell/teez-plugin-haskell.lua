-- teez Haskell adapter (Tasty / HUnit via cabal test or stack test)

local DEFAULT_INCLUDE = {
  "**/test/**/*.hs",
  "**/tests/**/*.hs",
  "**/*Test.hs",
  "**/*Spec.hs",
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function target_path(context)
  return context.target_path or "."
end

local function runner_cfg(context)
  if type(context.runner) == "table" then
    return context.runner
  end
  return {}
end

local function resolve_glob_hit(root, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  return root .. "/" .. file
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if type(cfg.include) == "table" and #cfg.include > 0 then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local cfg = runner_cfg(context)
  if type(cfg.exclude) == "table" then
    return cfg.exclude
  end
  return {}
end

local function path_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function command_available(name)
  local result = sys.run("sh", { "-c", "command -v " .. name .. " >/dev/null 2>&1" })
  return result.exit_code == 0
end

local function uses_stack(root, cfg)
  if cfg.tool == "stack" then
    return true
  end
  if cfg.tool == "cabal" then
    return false
  end
  return fs.exists(root .. "/stack.yaml") or fs.exists(root .. "/stack.yaml.lock")
end

local function resolve_tool(context)
  local cfg = runner_cfg(context)
  local root = target_path(context)

  if cfg.tool == "stack" or cfg.tool == "cabal" then
    if not command_available(cfg.tool) then
      error("haskell runner: configured tool '" .. cfg.tool .. "' not found on PATH")
    end
    return cfg.tool
  end

  local prefer_stack = uses_stack(root, cfg)
  if prefer_stack and command_available("stack") then
    return "stack"
  end
  if command_available("cabal") then
    return "cabal"
  end
  if command_available("stack") then
    return "stack"
  end

  error("haskell runner: need cabal or stack on PATH")
end

local function tasty_pattern(context)
  local cfg = runner_cfg(context)
  if type(cfg.pattern) == "string" and cfg.pattern ~= "" then
    return cfg.pattern
  end
  if type(cfg.test_pattern) == "string" and cfg.test_pattern ~= "" then
    return cfg.test_pattern
  end
  if type(context.filters) == "table" and type(context.filters.pattern) == "string" then
    return context.filters.pattern
  end
  return nil
end

local function build_test_options(context, extra)
  local options = { "--color=never" }
  local pattern = tasty_pattern(context)
  if pattern then
    table.insert(options, "--pattern=" .. pattern)
  end
  if extra then
    for _, option in ipairs(extra) do
      table.insert(options, option)
    end
  end
  if type(context.runner) == "table" and type(context.runner.test_options) == "table" then
    for _, option in ipairs(context.runner.test_options) do
      table.insert(options, option)
    end
  end
  return table.concat(options, " ")
end

local function append_runner_args(args, context)
  local cfg = runner_cfg(context)
  if type(cfg.args) == "table" then
    for _, arg in ipairs(cfg.args) do
      table.insert(args, arg)
    end
  end
end

local function cabal_test_args(context, test_options)
  local cfg = runner_cfg(context)
  local args = { "test" }
  if cfg.test and cfg.test ~= "" then
    table.insert(args, cfg.test)
  end
  table.insert(args, "--test-show-details=direct")
  table.insert(args, "--test-options")
  table.insert(args, test_options)
  append_runner_args(args, context)
  return args
end

local function run_options(context)
  local cfg = runner_cfg(context)
  local opts = { cwd = target_path(context) }
  if type(cfg.env) == "table" then
    opts.env = cfg.env
  end
  return opts
end

local function split_lines(text)
  local lines = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

local function is_list_tests_line(line)
  if line:match("^%s*$") then
    return false
  end
  if line:match("^%s*All tests") then
    return false
  end
  if line:match("^%s*Loaded") then
    return false
  end
  if line:match("^%s*Building") then
    return false
  end
  if line:match("^%s*Running") then
    return false
  end
  if line:match("^%s*Test suite") then
    return false
  end
  if line:match("^%s*Cases:%s") then
    return false
  end
  if line:match("^%s*%+%+%+%s") then
    return false
  end
  if line:match(":%s*(OK|FAIL|SKIP)%s*$") then
    return false
  end
  return true
end

local function discover_from_files(context)
  local root = target_path(context)
  local excludes = exclude_patterns(context)
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    for _, file in ipairs(fs.glob(root, pattern)) do
      local resolved = resolve_glob_hit(root, file)
      if not path_excluded(resolved, excludes) and not seen[resolved] then
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

local function list_via_tool(context, tool)
  local opts = run_options(context)
  local result

  if tool == "stack" then
    local args = { "test", "--test-arguments", build_test_options(context, { "--list-tests" }) }
    append_runner_args(args, context)
    result = sys.run("stack", args, opts)
  else
    local args = cabal_test_args(context, build_test_options(context, { "--list-tests" }))
    result = sys.run("cabal", args, opts)
  end

  if result.exit_code ~= 0 then
    return nil
  end

  local tests = {}
  local seen = {}
  for _, line in ipairs(split_lines(result.stdout)) do
    local id = trim(line)
    if is_list_tests_line(id) and not seen[id] then
      seen[id] = true
      table.insert(tests, id)
    end
  end

  if #tests == 0 then
    return nil
  end
  return tests
end

function list(context)
  local tool = resolve_tool(context)
  local listed = list_via_tool(context, tool)
  if listed and #listed > 0 then
    return filter_test_ids(listed, context)
  end
  return filter_test_ids(discover_from_files(context), context)
end

function build_command(context)
  local tool = resolve_tool(context)
  local opts = run_options(context)
  local spec = {
    cwd = opts.cwd,
  }
  if opts.env then
    spec.env = opts.env
  end

  if tool == "stack" then
    spec.command = "stack"
    spec.args = { "test", "--test-arguments", build_test_options(context) }
    append_runner_args(spec.args, context)
  else
    spec.command = "cabal"
    spec.args = cabal_test_args(context, build_test_options(context))
  end

  return spec
end

function build_list_command(context)
  local tool = resolve_tool(context)
  local spec = build_command(context)
  if tool == "stack" then
    spec.args = { "test", "--test-arguments", build_test_options(context, { "--list-tests" }) }
    append_runner_args(spec.args, context)
  else
    spec.args = cabal_test_args(context, build_test_options(context, { "--list-tests" }))
  end
  return spec
end

local function shallow_merge(base, overrides)
  local merged = {}
  for key, value in pairs(base) do
    merged[key] = value
  end
  if type(overrides) == "table" then
    for key, value in pairs(overrides) do
      merged[key] = value
    end
  end
  return merged
end

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

local function default_hpc_coverage(context)
  return {
    tool = "hpc",
    hpcdir = "dist/hpc/vanilla/tix",
    markup_dir = "coverage/hpc",
    report = "coverage/hpc.summary.txt",
    output = "coverage/teez.msgpack",
    reporter = "msgpack",
    mix = false,
    configure_args = { "--enable-coverage" },
  }
end

local function default_hie_coverage(context)
  return {
    tool = "hie",
    report = "coverage/lcov.info",
    output = "coverage/teez.msgpack",
    reporter = "lcov",
    mix = false,
    configure_args = { "--enable-coverage" },
  }
end

local function effective_coverage_cfg(context)
  local cfg = coverage_cfg(context)
  local tool = cfg.tool or cfg.backend or "hpc"
  if tool == "hie" then
    return shallow_merge(default_hie_coverage(context), cfg)
  end
  return shallow_merge(default_hpc_coverage(context), cfg)
end

function build_coverage_run(context)
  local tool = resolve_tool(context)
  local cov = effective_coverage_cfg(context)
  local root = target_path(context)
  local run_opts = run_options(context)
  local backend = cov.tool or cov.backend or "hpc"

  local test_options = build_test_options(context)
  local test_args
  if tool == "stack" then
    test_args = { "test" }
    if type(cov.configure_args) == "table" then
      for _, arg in ipairs(cov.configure_args) do
        table.insert(test_args, arg)
      end
    end
    table.insert(test_args, "--test-arguments")
    table.insert(test_args, test_options)
    append_runner_args(test_args, context)
  else
    test_args = cabal_test_args(context, test_options)
    if type(cov.configure_args) == "table" then
      for i = #cov.configure_args, 1, -1 do
        table.insert(test_args, 2, cov.configure_args[i])
      end
    end
  end

  local spec = {
    command = tool,
    args = test_args,
    cwd = run_opts.cwd,
    report = cov.report,
    output = cov.output,
    reporter = cov.reporter,
  }

  if type(cov.min_line_rate) == "number" then
    spec.min_line_rate = cov.min_line_rate
  end
  if run_opts.env then
    spec.env = run_opts.env
  end

  if backend == "hie" then
    local collect_cmd = cov.collect_command or "hie-coverage"
    local collect_args = cov.collect_args or { "report", "--lcov", cov.report }
    spec.collect = {
      command = collect_cmd,
      args = collect_args,
      cwd = root,
    }
    return spec
  end

  local hpcdir = cov.hpcdir or "dist/hpc/vanilla/tix"
  local markup_dir = cov.markup_dir or "coverage/hpc"
  local mix_flag = cov.mix and { "--union", "all" } or {}

  spec.collect = {
    command = "sh",
    args = {
      "-c",
      table.concat({
        "mkdir -p '" .. markup_dir .. "'",
        "hpc markup '" .. hpcdir .. "' --destdir='" .. markup_dir .. "'",
        "hpc report '" .. markup_dir .. "' > '" .. cov.report .. "'",
      }, " && "),
    },
    cwd = root,
  }

  if #mix_flag > 0 then
    spec.collect.args[2] = table.concat({
      "mkdir -p '" .. markup_dir .. "'",
      "hpc markup " .. mix_flag[1] .. " " .. mix_flag[2] .. " '" .. hpcdir .. "' --destdir='" .. markup_dir .. "'",
      "hpc report '" .. markup_dir .. "' > '" .. cov.report .. "'",
    }, " && ")
  end

  return spec
end

function parse_line(line)
  local trimmed = trim(line)
  if trimmed == "" then
    return nil
  end

  local name, result = trimmed:match("^(.-):%s*(OK|FAIL|SKIP)%s*$")
  if name and result then
    name = trim(name)
    if result == "OK" then
      return { event = "pass", id = name }
    end
    if result == "SKIP" then
      return { event = "skip", id = name }
    end
    return { event = "fail", id = name, msg = "FAIL" }
  end

  if trimmed:match("^%+%+%+%s+OK") then
    return nil
  end

  if trimmed:match("^Cases:%s") or trimmed:match("^Loaded environment from") then
    return nil
  end

  if trimmed:match("^Test suite .+: (PASS|FAIL)") then
    local suite, status = trimmed:match("^Test suite (.+): (PASS|FAIL)")
    if status == "PASS" then
      return { event = "pass", id = suite }
    end
    return { event = "fail", id = suite, msg = trimmed }
  end

  return { event = "output", text = trimmed }
end
