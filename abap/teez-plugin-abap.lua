-- teez runner for abapGit projects (SAP ABAP Unit)
--
-- Execution is delegated to an external command (default: abaplint run-tests).
-- Configure runners.abap in teez.config.lua — see README.md.

local DEFAULT_COMMAND = "abaplint"
local DEFAULT_RUN_ARGS = { "run-tests" }

local function runner_opts(context)
  return context.runner or {}
end

local function include_patterns(context)
  local runner = runner_opts(context)
  local patterns = runner.include
  if type(patterns) ~= "string" then
    patterns = patterns or { "**/*.abap", "**/z*test*.abap" }
  end
  if type(patterns) == "string" then
    patterns = { patterns }
  end
  return patterns
end

local function exclude_patterns(context)
  local runner = runner_opts(context)
  local patterns = runner.exclude or {}
  if type(patterns) == "string" then
    patterns = { patterns }
  end
  return patterns
end

local function path_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function collect_abap_files(context)
  local root = context.target_path
  local files = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not seen[path] and not path_excluded(path, exclude_patterns(context)) then
        seen[path] = true
        table.insert(files, path)
      end
    end
  end

  table.sort(files)
  return files
end

local function basename(path)
  return path:match("([^/\\]+)$") or path
end

local function class_name_from_path(path)
  local name = basename(path):lower()
  name = name:gsub("%.clas%.testclasses%.abap$", "")
  name = name:gsub("%.clas%.locals_imp%.abap$", "")
  name = name:gsub("%.clas%.abap$", "")
  name = name:gsub("%.prog%.abap$", "")
  name = name:gsub("%.intf%.abap$", "")
  return name
end

local function is_test_file(path)
  local lower = path:lower()
  if lower:match("%.clas%.testclasses%.abap$") then
    return true
  end
  if basename(lower):match("^z.*test") then
    return true
  end
  return false
end

local function extract_test_classes(content, fallback)
  local classes = {}
  local seen = {}

  for class_name in content:gmatch("[Cc][Ll][Aa][Ss][Ss]%s+([%w_]+)%s+[Dd][Ee][Ff][Ii][Nn][Ii][Tt][Ii][Oo][Nn][^\n]*[Ff][Oo][Rr]%s+[Tt][Ee][Ss][Tt][Ii][Nn][Gg]") do
    local id = class_name:lower()
    if not seen[id] then
      seen[id] = true
      table.insert(classes, id)
    end
  end

  for class_name in content:gmatch("[Cc][Ll][Aa][Ss][Ss]%s+([%w_]+)%s+[Ii][Mm][Pp][Ll][Ee][Mm][Ee][Nn][Tt][Aa][Tt][Ii][Oo][Nn][^\n]*[Ff][Oo][Rr]%s+[Tt][Ee][Ss][Tt][Ii][Nn][Gg]") do
    local id = class_name:lower()
    if not seen[id] then
      seen[id] = true
      table.insert(classes, id)
    end
  end

  if #classes == 0 and fallback and fallback ~= "" then
    table.insert(classes, fallback)
  end

  return classes
end

local function extract_test_methods(content, class_name)
  local methods = {}
  local seen = {}
  local class_pattern = class_name:gsub("([^%w])", "%%%1")

  for method_name in content:gmatch("[Mm][Ee][Tt][Hh][Oo][Dd]%s+([%w_]+)[^\n]*[Ff][Oo][Rr]%s+[Tt][Ee][Ss][Tt][Ii][Nn][Gg]") do
    local id = class_name .. "=>" .. method_name:lower()
    if not seen[id] then
      seen[id] = true
      table.insert(methods, id)
    end
  end

  -- Methods inside a specific test class block (best-effort).
  local block = content:match("[Cc][Ll][Aa][Ss][Ss]%s+" .. class_pattern .. "%s+[Ii][Mm][Pp][Ll][Ee][Mm][Ee][Nn][Tt][Aa][Tt][Ii][Oo][Nn.-][Ee][Nn][Dd][Cc][Ll][Aa][Ss][Ss]")
  if block then
    for method_name in block:gmatch("[Mm][Ee][Tt][Hh][Oo][Dd]%s+([%w_]+)[^\n]*[Ff][Oo][Rr]%s+[Tt][Ee][Ss][Tt][Ii][Nn][Gg]") do
      local id = class_name .. "=>" .. method_name:lower()
      if not seen[id] then
        seen[id] = true
        table.insert(methods, id)
      end
    end
  end

  return methods
end

local function discover_tests(context)
  local tests = {}
  local seen = {}

  for _, path in ipairs(collect_abap_files(context)) do
    if is_test_file(path) then
      local content = read_file(path)
      local fallback = class_name_from_path(path)
      local classes = {}

      if content and content ~= "" then
        classes = extract_test_classes(content, fallback)
      elseif fallback ~= "" then
        classes = { fallback }
      end

      for _, class_name in ipairs(classes) do
        if content and content ~= "" then
          local methods = extract_test_methods(content, class_name)
          if #methods > 0 then
            for _, id in ipairs(methods) do
              if not seen[id] then
                seen[id] = true
                table.insert(tests, id)
              end
            end
          elseif not seen[class_name] then
            seen[class_name] = true
            table.insert(tests, class_name)
          end
        elseif not seen[class_name] then
          seen[class_name] = true
          table.insert(tests, class_name)
        end
      end
    end
  end

  table.sort(tests)
  return tests
end

local function apply_filters(tests, context)
  if not context.filters then
    return tests
  end

  local filtered = {}
  for _, id in ipairs(tests) do
    if filter.matches({ id = id, path = id }, context.filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function command_name(context)
  local runner = runner_opts(context)
  return runner.command or DEFAULT_COMMAND
end

local function merge_args(defaults, runner)
  local args = {}
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
    return args
  end
  for _, arg in ipairs(defaults) do
    table.insert(args, arg)
  end
  if runner.config then
    table.insert(args, "--config")
    table.insert(args, runner.config)
  end
  if runner.package then
    table.insert(args, "--package")
    table.insert(args, runner.package)
  end
  return args
end

local function append_filter_args(args, context, runner)
  if runner.filter_flag and context.filters then
    local pattern = context.filters.pattern or context.filters.name
    if pattern and pattern ~= "" then
      table.insert(args, runner.filter_flag)
      table.insert(args, pattern)
    end
  end

  if runner.test_flag and context.filters and context.filters.ids then
    for _, id in ipairs(context.filters.ids) do
      table.insert(args, runner.test_flag)
      table.insert(args, id)
    end
  end
end

local function build_spec(context, default_args)
  local runner = runner_opts(context)
  local spec = {
    command = command_name(context),
    args = merge_args(default_args, runner),
    cwd = runner.cwd or context.target_path,
  }

  append_filter_args(spec.args, context, runner)

  if runner.env then
    spec.env = runner.env
  end

  return spec
end

function list(context)
  local runner = runner_opts(context)

  if runner.list_command then
    local output = sys.exec(runner.list_command, runner.list_args or {}, {
      cwd = runner.cwd or context.target_path,
      env = runner.env,
    })
    local tests = {}
    for line in output:gmatch("[^\r\n]+") do
      line = line:match("^%s*(.-)%s*$")
      if line ~= "" then
        table.insert(tests, line)
      end
    end
    return apply_filters(tests, context)
  end

  return apply_filters(discover_tests(context), context)
end

function build_command(context)
  return build_spec(context, DEFAULT_RUN_ARGS)
end

local function parse_json_event(line)
  if not line:match("^%s*{") then
    return nil
  end
  local ok, data = pcall(json.decode, line)
  if not ok or type(data) ~= "table" then
    return nil
  end
  if data.event then
    return data
  end
  if data.status and data.id then
    local event = data.status:lower()
    if event == "passed" or event == "ok" or event == "success" then
      event = "pass"
    elseif event == "failed" or event == "error" then
      event = "fail"
    elseif event == "skipped" or event == "skip" then
      event = "skip"
    end
    return {
      event = event,
      id = data.id,
      msg = data.message or data.msg,
      duration_ms = data.duration_ms,
    }
  end
  return nil
end

local function normalize_id(raw)
  if not raw then
    return nil
  end
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  raw = raw:gsub("^['\"]", ""):gsub("['\"]$", "")
  raw = raw:gsub("%s*[-–—:>]+>%s*", "=>")
  raw = raw:gsub("%s*/%s*", "=>")
  return raw:lower()
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = line:match("^%s*(.-)%s*$")

  local json_event = parse_json_event(trimmed)
  if json_event then
    if json_event.id then
      json_event.id = normalize_id(json_event.id)
    end
    return json_event
  end

  -- PASS ok passed ✓ ✔
  local id, msg = trimmed:match("^[✓✔]+%s*(.+)$")
  if id then
    return { event = "pass", id = normalize_id(id) }
  end

  id = trimmed:match("^[Pp][Aa][Ss][Ss][Ee][Dd]?%s*[:%-]+%s*(.+)$")
  if id then
    return { event = "pass", id = normalize_id(id) }
  end

  id = trimmed:match("^[Oo][Kk]%s*[:%-]+%s*(.+)$")
  if id then
    return { event = "pass", id = normalize_id(id) }
  end

  id = trimmed:match("[Tt]est [Mm]ethod:?%s*(.-)%s*[-–—]%s*[Pp][Aa][Ss][Ss][Ee][Dd]")
  if id then
    return { event = "pass", id = normalize_id(id) }
  end

  -- FAIL failed ✗ ✘
  id, msg = trimmed:match("^[✗✘]+%s*(.-)%s*[-–—:]\s*(.+)$")
  if id then
    return { event = "fail", id = normalize_id(id), msg = msg }
  end

  id, msg = trimmed:match("^[Ff][Aa][Ii][Ll](?:[Ee][Dd])?%s*[:%-]+%s*(.-)%s*[-–—:]\s*(.+)$")
  if id then
    return { event = "fail", id = normalize_id(id), msg = msg }
  end

  id = trimmed:match("^[Ff][Aa][Ii][Ll](?:[Ee][Dd])?%s*[:%-]+%s*(.+)$")
  if id then
    return { event = "fail", id = normalize_id(id), msg = trimmed }
  end

  id, msg = trimmed:match("[Tt]est [Mm]ethod:?%s*(.-)%s*[-–—]%s*[Ff][Aa][Ii][Ll](?:[Ee][Dd])?%s*(.*)$")
  if id then
    return { event = "fail", id = normalize_id(id), msg = msg ~= "" and msg or trimmed }
  end

  -- SKIP skipped pending
  id = trimmed:match("^[Ss][Kk][Ii][Pp](?:[Pp][Ee][Dd])?%s*[:%-]+%s*(.+)$")
  if id then
    return { event = "skip", id = normalize_id(id) }
  end

  id = trimmed:match("[Tt]est [Mm]ethod:?%s*(.-)%s*[-–—]%s*[Ss][Kk][Ii][Pp][Pp]?[Ee]?[Dd]?")
  if id then
    return { event = "skip", id = normalize_id(id) }
  end

  -- START running
  id = trimmed:match("^[Rr]unning%s+(.+)$")
  if id then
    return { event = "start", id = normalize_id(id) }
  end

  id = trimmed:match("^[Ss][Tt][Aa][Rr][Tt]%s*[:%-]+%s*(.+)$")
  if id then
    return { event = "start", id = normalize_id(id) }
  end

  if trimmed:match("[Tt]ests?%s+[Rr]un") or trimmed:match("[Ss]ummary") then
    return { event = "output", text = trimmed }
  end

  return { event = "output", text = trimmed }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  local coverage = runner.coverage
  if not coverage then
    return nil
  end

  local run_spec = build_spec(context, DEFAULT_RUN_ARGS)
  local collect_command = coverage.command or coverage.collect_command or command_name(context)
  local collect_args = coverage.args or coverage.collect_args or { "coverage", "--format", "lcov" }

  return {
    command = run_spec.command,
    args = run_spec.args,
    cwd = run_spec.cwd,
    env = run_spec.env,
    collect = {
      command = collect_command,
      args = collect_args,
      cwd = coverage.cwd or run_spec.cwd,
      env = coverage.env or run_spec.env,
    },
    report = coverage.report or "coverage/lcov.info",
    reporter = coverage.reporter or "lcov",
    output = coverage.output or "coverage/abap.lcov",
    min_line_rate = coverage.min_line_rate,
  }
end
