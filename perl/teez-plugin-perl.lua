local DEFAULT_TEST_DIR = "t"

local function runner_opts(context)
  return context.runner or {}
end

local function test_dir(context)
  local runner = runner_opts(context)
  return runner.test_dir or DEFAULT_TEST_DIR
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, arg in ipairs(extra) do
    table.insert(args, arg)
  end
end

local function prove_args(context, mode)
  local runner = runner_opts(context)
  local args = {}

  if mode == "run" and runner.lib ~= false then
    table.insert(args, "-l")
  end

  if mode == "list" or runner.recursive then
    table.insert(args, "-r")
  end

  if mode == "run" and runner.verbose ~= false then
    table.insert(args, "-v")
  end

  if mode == "list" then
    table.insert(args, "--collect")
  end

  append_args(args, runner.args)
  return args
end

local function filter_tests(tests, filters)
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

local function collect_tests(context)
  local args = prove_args(context, "list")
  table.insert(args, test_dir(context))

  local output = sys.exec("prove", args, { cwd = context.target_path })
  local tests = {}

  for line in output:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(tests, trimmed)
    end
  end

  return filter_tests(tests, context.filters)
end

local function coverage_env(runner, force)
  if not force and not runner.coverage then
    return nil
  end

  local switches = "-MDevel::Cover"
  if runner.coverage_opts then
    switches = switches .. "=" .. runner.coverage_opts
  end

  return {
    HARNESS_PERL_SWITCHES = switches,
  }
end

function list(context)
  return collect_tests(context)
end

function build_command(context)
  local runner = runner_opts(context)
  local args = prove_args(context, "run")
  local targets = { test_dir(context) }

  if context.filters then
    local tests = collect_tests(context)
    if #tests == 0 then
      error("no Perl tests matched the current filters")
    end
    targets = tests
  end

  for _, target in ipairs(targets) do
    table.insert(args, target)
  end

  local spec = {
    command = "prove",
    args = args,
    cwd = context.target_path,
  }

  local env = coverage_env(runner)
  if env then
    spec.env = env
  end

  return spec
end

function parse_line(line)
  local trimmed = line:match("^%s*(.*)$")
  if trimmed == "" then
    return nil
  end

  if trimmed:match("^%d+%.%.$") then
    return nil
  end

  if trimmed:match("^ok %d+ # skip") then
    local id = trimmed:match("^ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "skip", id = id }
  end

  if trimmed:match("^ok %d+") then
    local id = trimmed:match("^ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "pass", id = id }
  end

  if trimmed:match("^not ok %d+") then
    local id = trimmed:match("^not ok %d+ ?%-? ?(.*)$") or trimmed
    return { event = "fail", id = id, msg = trimmed }
  end

  if trimmed == "ok" then
    return { event = "pass", id = "prove" }
  end

  if trimmed == "not ok" then
    return { event = "fail", id = "prove", msg = trimmed }
  end

  return { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  local args = { "-l", "-r", "-v", test_dir(context) }
  append_args(args, runner.args)

  return {
    command = "prove",
    args = args,
    cwd = context.target_path,
    env = coverage_env(runner, true),
    collect = {
      command = "cover",
      args = { "-report", "lcov", "-output", "coverage/lcov.info" },
    },
    report = "coverage/lcov.info",
  }
end
