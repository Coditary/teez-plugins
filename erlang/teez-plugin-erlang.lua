local DEFAULT_INCLUDES = {
  "**/test/**/*.erl",
  "**/*_SUITE.erl",
}

local parse_state = {
  eunit_module = nil,
}

local function runner_opts(context)
  return context.runner or {}
end

local function test_mode(context)
  local mode = runner_opts(context).mode or "eunit"
  if mode ~= "eunit" and mode ~= "ct" then
    return "eunit"
  end
  return mode
end

local function append_args(dest, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(dest, value)
  end
end

local function module_from_path(path)
  local base = path:match("([^/\\]+)%.erl$")
  if not base then
    return nil
  end
  return base
end

local function patterns_for(context)
  local opts = runner_opts(context)
  if opts.include then
    return opts.include
  end
  return DEFAULT_INCLUDES
end

local function excluded_by_runner(path, context)
  local opts = runner_opts(context)
  if not opts.exclude then
    return false
  end
  for _, pattern in ipairs(opts.exclude) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function discover_modules(context, suite_only)
  local root = context.target_path
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(patterns_for(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not excluded_by_runner(path, context) then
        local module_name = module_from_path(path)
        if module_name then
          local is_suite = module_name:match("_SUITE$") ~= nil
          if suite_only then
            if is_suite and not seen[module_name] then
              seen[module_name] = true
              table.insert(tests, module_name)
            end
          elseif not is_suite and not seen[module_name] then
            seen[module_name] = true
            table.insert(tests, module_name)
          end
        end
      end
    end
  end

  table.sort(tests)
  return tests
end

local function parse_eunit_list_output(output)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^===>") then
      local module_name, function_name = trimmed:match("^([%w_]+):([%w_]+)$")
      local id = module_name and function_name and (module_name .. ":" .. function_name) or trimmed
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  if #tests == 0 then
    return nil
  end
  return tests
end

local function try_eunit_list(context)
  local result = sys.run("rebar3", { "eunit", "--list" }, { cwd = context.target_path })
  if result.exit_code ~= 0 then
    return nil
  end
  return parse_eunit_list_output(result.stdout)
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

local function collect_eunit_tests(context)
  local listed = try_eunit_list(context)
  if listed then
    return listed
  end
  return discover_modules(context, false)
end

local function collect_ct_tests(context)
  local suites = discover_modules(context, true)
  local tests = {}

  for _, suite in ipairs(suites) do
    table.insert(tests, suite)
  end

  return tests
end

function list(context)
  local mode = test_mode(context)
  local tests

  if mode == "ct" then
    tests = collect_ct_tests(context)
  else
    tests = collect_eunit_tests(context)
  end

  return apply_filters(tests, context)
end

local function join(values, sep)
  return table.concat(values, sep)
end

local function selection_from_filters(context)
  if not context.filters then
    return nil
  end

  local tests = list({ target_path = context.target_path, runner = context.runner })
  local selected = apply_filters(tests, { target_path = context.target_path, runner = context.runner, filters = context.filters })
  if #selected == 0 then
    return nil
  end
  return selected
end

local function apply_eunit_selection(args, context)
  local opts = runner_opts(context)

  if opts.test then
    table.insert(args, "--test=" .. opts.test)
    return
  end

  if opts.module then
    table.insert(args, "--module=" .. opts.module)
    return
  end

  local selected = selection_from_filters(context)
  if not selected then
    return
  end

  local by_module = {}
  local modules_only = {}
  for _, id in ipairs(selected) do
    local module_name, function_name = id:match("^([%w_]+):([%w_]+)$")
    if module_name and function_name then
      local bucket = by_module[module_name]
      if not bucket then
        bucket = {}
        by_module[module_name] = bucket
      end
      table.insert(bucket, function_name)
    elseif id:match("^[%w_]+$") then
      table.insert(modules_only, id)
    end
  end

  local specs = {}
  for module_name, functions in pairs(by_module) do
    table.insert(specs, module_name .. ":" .. join(functions, "+"))
  end

  if #specs > 0 then
    table.sort(specs)
    table.insert(args, "--test=" .. join(specs, ","))
    return
  end

  if #modules_only > 0 then
    table.sort(modules_only)
    table.insert(args, "--module=" .. join(modules_only, ","))
  end
end

local function apply_ct_selection(args, context)
  local opts = runner_opts(context)

  if opts.suite then
    table.insert(args, "--suite=" .. opts.suite)
  end
  if opts.group then
    table.insert(args, "--group=" .. opts.group)
  end
  if opts.case then
    table.insert(args, "--case=" .. opts.case)
  end
  if opts.suite or opts.group or opts.case then
    return
  end

  local selected = selection_from_filters(context)
  if not selected or #selected == 0 then
    return
  end

  local suites = {}
  local cases = {}
  local seen_suite = {}
  local seen_case = {}

  for _, id in ipairs(selected) do
    local suite, case_name = id:match("^([%w_]+):([%w_]+)$")
    if suite and case_name then
      if not seen_case[id] then
        seen_case[id] = true
        table.insert(cases, case_name)
      end
      if not seen_suite[suite] then
        seen_suite[suite] = true
        table.insert(suites, suite)
      end
    elseif id:match("_SUITE$") and not seen_suite[id] then
      seen_suite[id] = true
      table.insert(suites, id)
    end
  end

  if #suites > 0 then
    table.sort(suites)
    table.insert(args, "--suite=" .. join(suites, ","))
  end
  if #cases > 0 then
    table.sort(cases)
    table.insert(args, "--case=" .. join(cases, ","))
  end
end

function build_command(context)
  local mode = test_mode(context)
  local args = { mode }

  if mode == "eunit" then
    table.insert(args, "--verbose")
    apply_eunit_selection(args, context)
  else
    table.insert(args, "--readable=true")
    apply_ct_selection(args, context)
  end

  append_args(args, runner_opts(context).args)

  return {
    command = "rebar3",
    args = args,
    cwd = context.target_path,
  }
end

local function parse_ct_line(line)
  local suite, case_name, status = line:match(
    "^%%%s+([%w_]+)%s+==>%s+([%w_]+):%s+(OK|FAILED|SKIPPED)%s*$"
  )
  if not suite then
    return nil
  end

  local id = suite .. ":" .. case_name
  if status == "OK" then
    return { event = "pass", id = id }
  end
  if status == "FAILED" then
    return { event = "fail", id = id, msg = line }
  end
  return { event = "skip", id = id }
end

local function parse_eunit_module_line(line)
  local module_name = line:match("^%s*module%s+'([^']+)'%s*$")
  if not module_name then
    return nil
  end

  parse_state.eunit_module = module_name
  return { event = "start", id = module_name }
end

local function parse_eunit_case_line(line)
  local module_name = parse_state.eunit_module
  if not module_name then
    return nil
  end

  local case_name = line:match("^%s+([%w_]+)%.+")
  if not case_name then
    return nil
  end

  local id = module_name .. ":" .. case_name
  if line:match("%*failed%*") then
    return { event = "fail", id = id, msg = line:match("^%s*(.+)$") or line }
  end
  if line:match("%.%.%.+ok%s*$") or line:match("%.ok%s*$") then
    return { event = "pass", id = id }
  end

  return nil
end

local function parse_summary_line(line)
  local count, failures = line:match("(%d+)%s+tests?,?%s+(%d+)%s+fail")
  if count and failures then
    return { event = "output", text = line }
  end
  return nil
end

function parse_line(line)
  if line:match("^===>") then
    return nil
  end

  local ct = parse_ct_line(line)
  if ct then
    return ct
  end

  local module_event = parse_eunit_module_line(line)
  if module_event then
    return module_event
  end

  local eunit_case = parse_eunit_case_line(line)
  if eunit_case then
    return eunit_case
  end

  local summary = parse_summary_line(line)
  if summary then
    return summary
  end

  if line:match("%S") then
    return { event = "output", text = line }
  end

  return nil
end

function build_coverage_run(context)
  local mode = test_mode(context)
  local run_args = { "do", mode, "--cover" }
  append_args(run_args, runner_opts(context).args)

  return {
    command = "rebar3",
    args = run_args,
    cwd = context.target_path,
    collect = {
      command = "rebar3",
      args = { "cover", "--verbose" },
      cwd = context.target_path,
    },
    report = "_build/test/cover/index.html",
  }
end
