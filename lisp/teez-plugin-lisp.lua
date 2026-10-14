-- teez runner for Common Lisp projects using ASDF test-op and FiveAM.

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function runner_opts(context)
  return context.runner or {}
end

local function lisp_command(context)
  local opts = runner_opts(context)
  return opts.command or opts.lisp or "sbcl"
end

local function read_file(path)
  local result = sys.run("cat", { path })
  if result.exit_code == 0 then
    return result.stdout
  end
  return nil
end

local function normalize_system_name(name)
  name = trim(name)
  if name:sub(1, 1) == ":" then
    name = name:sub(2)
  end
  return name
end

local function system_symbol(name)
  name = normalize_system_name(name)
  if name:match("^[%w%-]+$") then
    return ":" .. name
  end
  return "'" .. name .. "'"
end

local function asd_has_test_op(content)
  if not content then
    return false
  end
  return content:match(":test%-system")
    or content:match("%(test%-op")
    or content:match("'test%-op")
    or content:match('"test%-op"')
end

local function extract_systems_from_asd(content)
  local systems = {}
  local seen = {}

  for name in content:gmatch("%(defsystem[%s]+([:%w%-]+)") do
    name = normalize_system_name(name)
    if name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(systems, name)
    end
  end

  return systems
end

local function collect_asd_files(context)
  local opts = runner_opts(context)
  local patterns = opts.include or { "**/*.asd" }
  local files = {}
  local seen = {}

  for _, pattern in ipairs(patterns) do
    if pattern:match("%.asd$") then
      for _, path in ipairs(fs.glob(context.target_path, pattern)) do
        if not seen[path] then
          seen[path] = true
          table.insert(files, path)
        end
      end
    end
  end

  if #files == 0 then
    for _, path in ipairs(fs.glob(context.target_path, "**/*.asd")) do
      if not seen[path] then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  return files
end

local function discover_systems(context)
  local opts = runner_opts(context)
  if opts.systems then
    local systems = {}
    for _, name in ipairs(opts.systems) do
      table.insert(systems, normalize_system_name(name))
    end
    return systems
  end

  if opts.system then
    return { normalize_system_name(opts.system) }
  end

  local systems = {}
  local seen = {}
  local require_test_op = opts.require_test_op
  if require_test_op == nil then
    require_test_op = true
  end

  for _, path in ipairs(collect_asd_files(context)) do
    local content = read_file(path)
    if content then
      for _, name in ipairs(extract_systems_from_asd(content)) do
        if not seen[name] and (not require_test_op or asd_has_test_op(content)) then
          seen[name] = true
          table.insert(systems, name)
        end
      end
    end
  end

  table.sort(systems)
  return systems
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

local function ensure_command_available(command)
  local result = sys.run("sh", { "-c", "command -v " .. command })
  if result.exit_code ~= 0 then
    error("lisp runner command not found on PATH: " .. command)
  end
end

local function asdf_registry_setup(context)
  local opts = runner_opts(context)
  local forms = {
    "(require :asdf)",
    string.format('(pushnew (truename %q) asdf:*central-registry*)', context.target_path),
  }

  if opts.load_path then
    for _, path in ipairs(opts.load_path) do
      table.insert(forms, string.format('(pushnew (truename %q) asdf:*central-registry*)', path))
    end
  end

  return table.concat(forms, " ")
end

local function build_eval_form(context, systems)
  local opts = runner_opts(context)
  local forms = { asdf_registry_setup(context) }

  for _, path in ipairs(collect_asd_files(context)) do
    table.insert(forms, string.format('(handler-case (asdf:load-asd %q) (error (c) (warn "teez: failed to load ~A: ~A" %q c)))', path, path))
  end

  for _, system in ipairs(systems) do
    table.insert(forms, string.format("(asdf:test-system %s)", system_symbol(system)))
  end

  if opts.eval then
    for _, expr in ipairs(opts.eval) do
      table.insert(forms, expr)
    end
  end

  return "(progn " .. table.concat(forms, " ") .. ")"
end

local function append_args(base, extra)
  if not extra then
    return base
  end
  for _, arg in ipairs(extra) do
    table.insert(base, arg)
  end
  return base
end

local function build_sbcl_command(context, systems)
  local opts = runner_opts(context)
  local args = {
    "--noinform",
    "--non-interactive",
    "--disable-debugger",
    "--eval",
    build_eval_form(context, systems),
  }

  if opts.quit ~= false then
    table.insert(args, "--quit")
  end

  return {
    command = "sbcl",
    args = append_args(args, opts.args),
    cwd = opts.cwd or context.target_path,
    env = opts.env,
  }
end

local function build_ros_command(context, systems)
  local opts = runner_opts(context)
  return {
    command = "ros",
    args = append_args({ "run", "-e", build_eval_form(context, systems) }, opts.args),
    cwd = opts.cwd or context.target_path,
    env = opts.env,
  }
end

local function build_lisp_command(context, systems)
  local command = lisp_command(context)
  ensure_command_available(command)

  if command == "ros" then
    return build_ros_command(context, systems)
  end

  if command == "sbcl" then
    return build_sbcl_command(context, systems)
  end

  local opts = runner_opts(context)
  return {
    command = command,
    args = append_args({
      "--eval",
      build_eval_form(context, systems),
    }, opts.args),
    cwd = opts.cwd or context.target_path,
    env = opts.env,
  }
end

local function systems_for_context(context)
  local systems = discover_systems(context)
  if #systems == 0 then
    error("no ASDF systems with test-op found under " .. context.target_path)
  end
  return systems
end

function list(context)
  return apply_filters(systems_for_context(context), context)
end

function build_command(context)
  local systems = apply_filters(systems_for_context(context), context)
  if #systems == 0 then
    error("no ASDF test systems matched the current filters")
  end
  return build_lisp_command(context, systems)
end

function parse_line(line)
  local trimmed = trim(line)
  if trimmed == "" then
    return nil
  end

  local started = trimmed:match("^Running test%s+(.-)%s+%.%.%.?$")
  if started then
    return { event = "start", id = trim(started) }
  end

  local passed = trimmed:match("^(%S.+):%s*%((%d+)%s+assertions%s+passed%)")
  if passed then
    return { event = "pass", id = trim(passed) }
  end

  if trimmed:match("^Pass:%s*ALL%s*%(%d+%)") then
    return { event = "output", text = trimmed }
  end

  local checks = trimmed:match("^Did%s+(%d+)%s+check")
  if checks then
    return { event = "output", text = trimmed }
  end

  if trimmed:match("assertions?%s+passed") and not trimmed:match("failed") then
    return { event = "output", text = trimmed }
  end

  if trimmed:match("(%d+)%s+failure") or trimmed:match("(%d+)%s+regression") then
    return { event = "fail", id = "fiveam", msg = trimmed }
  end

  if trimmed:match("TEST%-OP.*failed") or trimmed:match("test%-op.*failed") then
    return { event = "fail", id = "asdf:test-op", msg = trimmed }
  end

  if trimmed:match("^; debugger invoked") or trimmed:match("^Unhandled") then
    return { event = "fail", id = "lisp", msg = trimmed }
  end

  return { event = "output", text = trimmed }
end

function build_coverage_run(context)
  local opts = runner_opts(context)
  if not opts.coverage then
    return nil
  end

  local systems = systems_for_context(context)
  local report = opts.coverage_report or "coverage/sb-cover.lisp"
  local forms = {
    asdf_registry_setup(context),
    "(require :sb-cover)",
    "(sb-cover:start)",
  }

  for _, system in ipairs(systems) do
    table.insert(forms, string.format("(asdf:load-system %s)", system_symbol(system)))
    table.insert(forms, string.format("(asdf:test-system %s)", system_symbol(system)))
  end

  table.insert(forms, string.format('(sb-cover:report %q)', report))
  table.insert(forms, "(sb-ext:quit)")

  local command = lisp_command(context)
  ensure_command_available(command)

  local spec = {
    command = command,
    cwd = opts.cwd or context.target_path,
    env = opts.env,
    report = report,
  }

  if command == "ros" then
    spec.args = append_args({ "run", "-e", "(progn " .. table.concat(forms, " ") .. ")" }, opts.args)
  else
    spec.args = append_args({
      "--noinform",
      "--non-interactive",
      "--disable-debugger",
      "--eval",
      "(progn " .. table.concat(forms, " ") .. ")",
    }, opts.args)
  end

  return spec
end
