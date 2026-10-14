-- ServiceNow Automated Test Framework (ATF) runner for teez.
-- Default transport: `snc atf` CLI. Override via runners.servicenow.command for REST/curl.

local DEFAULT_COMMAND = "snc"
local DEFAULT_LIST_SUBCOMMAND = { "atf", "list", "--format", "json" }
local DEFAULT_RUN_SUBCOMMAND = { "atf", "run", "--format", "json" }

local function runner_opts(context)
  return context.runner or {}
end

local function include_patterns(context)
  local opts = runner_opts(context)
  if opts.include and #opts.include > 0 then
    return opts.include
  end
  return { "**/atf/**", "**/*_test.xml" }
end

local function exclude_patterns(context)
  local opts = runner_opts(context)
  return opts.exclude or {}
end

local function path_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function collect_metadata_files(context)
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
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function extract_xml_ids(content, path)
  local ids = {}

  for sys_id in content:gmatch('<sys_atf_[^>]+sys_id="([^"]+)"') do
    table.insert(ids, sys_id)
  end
  for sys_id in content:gmatch("<sys_id>([^<]+)</sys_id>") do
    if sys_id:match("^[%x]+$") and #sys_id == 32 then
      table.insert(ids, sys_id)
    end
  end
  for name in content:gmatch('<name>([^<]+)</name>') do
    if name ~= "" then
      table.insert(ids, path .. "::" .. name)
    end
  end

  return ids
end

local function unique(values)
  local out = {}
  local seen = {}
  for _, value in ipairs(values) do
    if value ~= "" and not seen[value] then
      seen[value] = true
      table.insert(out, value)
    end
  end
  return out
end

local function parse_list_output(output)
  local tests = {}

  local decoded = nil
  if output:match("^%s*[%[{]") then
    local ok, data = pcall(json.decode, output)
    if ok then
      decoded = data
    end
  end

  if type(decoded) == "table" then
    local items = decoded.tests or decoded.suites or decoded.results or decoded
    if type(items) == "table" then
      for _, item in ipairs(items) do
        if type(item) == "string" then
          table.insert(tests, item)
        elseif type(item) == "table" then
          local id = item.sys_id or item.id or item.name
          if id then
            table.insert(tests, tostring(id))
          end
        end
      end
    end
    return unique(tests)
  end

  for line in output:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^#") then
      table.insert(tests, trimmed)
    end
  end

  return unique(tests)
end

local function list_from_metadata(context)
  local tests = {}
  for _, path in ipairs(collect_metadata_files(context)) do
    local content = read_file(path)
    if not content then
      local ok, data = pcall(function()
        return sys.exec("snc", { "file", "read", path })
      end)
      if ok then
        content = data
      end
    end
    if content then
      for _, id in ipairs(extract_xml_ids(content, path)) do
        table.insert(tests, id)
      end
    else
      table.insert(tests, path)
    end
  end
  return unique(tests)
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

local function split_command(command)
  local parts = {}
  for part in command:gmatch("%S+") do
    table.insert(parts, part)
  end
  return parts[1], { table.unpack(parts, 2) }
end

local function append_runner_args(args, opts)
  if opts.args then
    for _, arg in ipairs(opts.args) do
      table.insert(args, arg)
    end
  end
  if opts.instance then
    table.insert(args, "--instance")
    table.insert(args, opts.instance)
  end
  if opts.suite then
    table.insert(args, "--suite")
    table.insert(args, opts.suite)
  end
  if opts.test then
    table.insert(args, "--test")
    table.insert(args, opts.test)
  end
  if opts.browser then
    table.insert(args, "--browser")
    table.insert(args, opts.browser)
  end
  return args
end

local function build_default_list_spec(context)
  local opts = runner_opts(context)
  local args = { table.unpack(DEFAULT_LIST_SUBCOMMAND) }
  append_runner_args(args, opts)
  if context.target_path and context.target_path ~= "" then
    table.insert(args, context.target_path)
  end
  return {
    command = opts.command or DEFAULT_COMMAND,
    args = args,
    env = opts.env,
    cwd = opts.cwd,
  }
end

local function build_default_run_spec(context)
  local opts = runner_opts(context)
  local args = { table.unpack(DEFAULT_RUN_SUBCOMMAND) }
  append_runner_args(args, opts)
  if context.target_path and context.target_path ~= "" then
    table.insert(args, context.target_path)
  end
  return {
    command = opts.command or DEFAULT_COMMAND,
    args = args,
    env = opts.env,
    cwd = opts.cwd,
  }
end

local function build_custom_command_spec(context, command)
  local opts = runner_opts(context)
  local cmd, args = split_command(command)
  args = append_runner_args(args, opts)
  if context.target_path and context.target_path ~= "" then
    table.insert(args, context.target_path)
  end
  return {
    command = cmd,
    args = args,
    env = opts.env,
    cwd = opts.cwd,
  }
end

function list(context)
  local opts = runner_opts(context)

  if opts.list_command then
    local cmd, args = split_command(opts.list_command)
    local output = sys.exec(cmd, args, { env = opts.env, cwd = opts.cwd })
    return apply_filters(parse_list_output(output), context)
  end

  local spec = build_default_list_spec(context)
  local ok, output = pcall(function()
    return sys.exec(spec.command, spec.args, { env = spec.env, cwd = spec.cwd })
  end)
  if ok and output and output ~= "" then
    local tests = apply_filters(parse_list_output(output), context)
    if #tests > 0 then
      return tests
    end
  end

  return apply_filters(list_from_metadata(context), context)
end

function build_list_command(context)
  local opts = runner_opts(context)
  if opts.list_command then
    return build_custom_command_spec(context, opts.list_command)
  end
  return build_default_list_spec(context)
end

function build_command(context)
  local opts = runner_opts(context)

  if opts.run_command then
    return build_custom_command_spec(context, opts.run_command)
  end

  if opts.command and opts.command ~= DEFAULT_COMMAND then
    local args = append_runner_args({}, opts)
    if context.target_path and context.target_path ~= "" then
      table.insert(args, context.target_path)
    end
    return {
      command = opts.command,
      args = args,
      env = opts.env,
      cwd = opts.cwd,
    }
  end

  return build_default_run_spec(context)
end

local function event_from_table(data)
  if type(data) ~= "table" then
    return nil
  end

  local status = data.status or data.result or data.state or data.outcome
  local id = data.id or data.sys_id or data.test or data.name or data.test_name
  local msg = data.msg or data.message or data.error or data.failure

  if status then
    local normalized = tostring(status):lower()
    if normalized:match("pass") or normalized == "success" or normalized == "ok" then
      return {
        event = "pass",
        id = id and tostring(id) or "atf-test",
        duration_ms = data.duration_ms or data.duration,
      }
    end
    if normalized:match("fail") or normalized == "error" then
      return {
        event = "fail",
        id = id and tostring(id) or "atf-test",
        msg = msg and tostring(msg) or normalized,
        duration_ms = data.duration_ms or data.duration,
      }
    end
    if normalized:match("skip") then
      return {
        event = "skip",
        id = id and tostring(id) or "atf-test",
      }
    end
    if normalized:match("start") or normalized == "running" then
      return {
        event = "start",
        id = id and tostring(id) or "atf-test",
      }
    end
  end

  if data.event then
    local event = tostring(data.event):lower()
    if event == "pass" or event == "fail" or event == "skip" or event == "start" or event == "output" then
      local result = { event = event }
      if id then
        result.id = tostring(id)
      end
      if msg then
        result.msg = tostring(msg)
      end
      if data.text then
        result.text = tostring(data.text)
      end
      if data.duration_ms or data.duration then
        result.duration_ms = data.duration_ms or data.duration
      end
      return result
    end
  end

  return nil
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil
  end

  if trimmed:match("^%s*[%[{]") then
    local ok, data = pcall(json.decode, trimmed)
    if ok then
      local event = event_from_table(data)
      if event then
        return event
      end
    end
  end

  local pass_id = trimmed:match("^PASS[%s:]+(.+)$") or trimmed:match("^%[PASS%]%s*(.+)$")
  if pass_id then
    return { event = "pass", id = pass_id }
  end

  local fail_id, fail_msg = trimmed:match("^FAIL[%s:]+([^:]+):%s*(.+)$")
  if not fail_id then
    fail_id = trimmed:match("^FAIL[%s:]+(.+)$") or trimmed:match("^%[FAIL%]%s*(.+)$")
  end
  if fail_id then
    return {
      event = "fail",
      id = fail_id,
      msg = fail_msg or trimmed,
    }
  end

  local skip_id = trimmed:match("^SKIP[%s:]+(.+)$") or trimmed:match("^%[SKIP%]%s*(.+)$")
  if skip_id then
    return { event = "skip", id = skip_id }
  end

  local start_id = trimmed:match("^START[%s:]+(.+)$") or trimmed:match("^Running[%s:]+(.+)$")
  if start_id then
    return { event = "start", id = start_id }
  end

  local atf_pass = trimmed:match("ATF.*Test%s+(.+)%s+passed")
  if atf_pass then
    return { event = "pass", id = atf_pass }
  end

  local atf_fail = trimmed:match("ATF.*Test%s+(.+)%s+failed")
  if atf_fail then
    return { event = "fail", id = atf_fail, msg = trimmed }
  end

  return { event = "output", text = trimmed }
end
