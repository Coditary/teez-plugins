local DEFAULT_INCLUDE = { "**/Tests/**", "**/*Test*.vi" }
local DEFAULT_EXCLUDE = { "**/_support/**", "**/utilities/**", "**/support/**" }

local function runner_opts(context)
  return context.runner or {}
end

local function merge_patterns(context)
  local runner = runner_opts(context)
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

local function normalize_path(path)
  return (path:gsub("\\", "/"))
end

local function relative_to(base, path)
  local norm_base = normalize_path(base)
  local norm_path = normalize_path(path)

  if norm_base:sub(-1) ~= "/" then
    norm_base = norm_base .. "/"
  end

  if norm_path:sub(1, #norm_base) ~= norm_base then
    return norm_path
  end

  return norm_path:sub(#norm_base + 1)
end

local function matches_any(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_test_vi(path)
  local norm = normalize_path(path)
  if not norm:match("%.vi$") then
    return false
  end
  if norm:match("[/\\]Tests[/\\]") then
    return true
  end
  local name = norm:match("([^/]+)$") or norm
  return name:match("Test") ~= nil
end

local function find_lvproj(context)
  local runner = runner_opts(context)
  if runner.lvproj then
    local candidate = runner.lvproj
    if not candidate:match("^[/\\]") and not candidate:match("^%a:[/\\]") then
      candidate = context.target_path .. "/" .. candidate
    end
    if fs.exists(candidate) then
      return candidate
    end
    error("labview runner.lvproj not found: " .. runner.lvproj)
  end

  local projects = fs.glob(context.target_path, "*.lvproj")
  if #projects == 0 then
    error("no .lvproj found under " .. context.target_path)
  end
  if #projects > 1 and not runner.lvproj then
    error("multiple .lvproj files found; set runners.labview.lvproj")
  end
  return projects[1]
end

local function resolve_command(context)
  local runner = runner_opts(context)
  local command = runner.command
  if not command or command == "" then
    error("runners.labview.command is required (e.g. LabVIEW.exe, labview, vi-server)")
  end
  return command
end

local function collect_test_vis(context)
  local include, exclude = merge_patterns(context)
  local seen = {}
  local tests = {}

  local all_vis = fs.glob(context.target_path, "**/*.vi")
  for _, vi_path in ipairs(all_vis) do
    local rel = relative_to(context.target_path, vi_path)
    if not is_test_vi(rel) then
      goto continue
    end
    if not matches_any(rel, include) then
      goto continue
    end
    if matches_any(rel, exclude) then
      goto continue
    end
    if seen[rel] then
      goto continue
    end
    seen[rel] = true
    table.insert(tests, rel)
    ::continue::
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
    if filter.matches({ id = id }, context.filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function append_args(args, extra)
  if not extra then
    return
  end
  if type(extra) == "string" then
    table.insert(args, extra)
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function build_labview_args(context, tests)
  local runner = runner_opts(context)
  local args = {}

  if runner.passive ~= false then
    table.insert(args, "-passive")
  end
  if runner.nostdwin then
    table.insert(args, "-nostdwin")
  end
  if runner.server or runner.command == "vi-server" then
    table.insert(args, "-server")
  end

  local lvproj = find_lvproj(context)
  table.insert(args, "-root")
  table.insert(args, lvproj)

  append_args(args, runner.args)

  local batch_vi = runner.batch_vi or runner.runner_vi
  if not batch_vi then
    error("runners.labview.batch_vi is required (VI Tester batch runner VI path)")
  end
  table.insert(args, batch_vi)

  for _, test_id in ipairs(tests) do
    table.insert(args, test_id)
  end

  return args, lvproj
end

function list(context)
  local tests = collect_test_vis(context)
  return apply_filters(tests, context)
end

function build_command(context)
  local command = resolve_command(context)
  local tests = collect_test_vis(context)
  tests = apply_filters(tests, context)

  local args, _ = build_labview_args(context, tests)
  local runner = runner_opts(context)

  local spec = {
    command = command,
    args = args,
  }

  if runner.env then
    spec.env = {}
    for key, value in pairs(runner.env) do
      spec.env[key] = value
    end
  end

  if #tests > 0 then
    spec.env = spec.env or {}
    spec.env.TEEZ_LABVIEW_TESTS = json.encode(tests)
  end

  if runner.cwd then
    spec.cwd = runner.cwd
  else
    spec.cwd = context.target_path
  end

  return spec
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_duration_seconds(text)
  if not text then
    return nil
  end
  local seconds = text:match("([%d%.]+)%s*s")
  if seconds then
    return math.floor(tonumber(seconds) * 1000)
  end
  local ms = text:match("([%d%.]+)%s*ms")
  if ms then
    return math.floor(tonumber(ms))
  end
  return nil
end

local function event_from_status(status, id, msg, duration_ms)
  local event = status
  if event == "pass" or event == "fail" or event == "skip" then
    local result = { event = event, id = id }
    if msg and msg ~= "" then
      result.msg = msg
    end
    if duration_ms then
      result.duration_ms = duration_ms
    end
    return result
  end
  return nil
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = trim(line)
  if trimmed == "" then
    return nil
  end

  -- JUnit XML fragments (single-line reporters)
  local xml_status = trimmed:match("^<testcase%s+[^>]*name=\"([^\"]+)\"")
  if xml_status then
    local classname = trimmed:match("classname=\"([^\"]+)\"")
    local time = trimmed:match("time=\"([^\"]+)\"")
    local id = classname and (classname .. "::" .. xml_status) or xml_status
    local duration_ms = time and math.floor(tonumber(time) * 1000) or nil

    if trimmed:match("<failure") or trimmed:match("<error") then
      local msg = trimmed:match("<failure[^>]*>([^<]+)</failure>")
        or trimmed:match("<error[^>]*>([^<]+)</error>")
        or trimmed
      return event_from_status("fail", id, msg, duration_ms)
    end
    if trimmed:match("<skipped") then
      return event_from_status("skip", id, nil, duration_ms)
    end
    return event_from_status("pass", id, nil, duration_ms)
  end

  -- [PASS] id / [FAIL] id: message
  local bracket_status, bracket_id, bracket_msg = trimmed:match("^%[(PASS|FAIL|SKIP)%]%s+([^:]+):%s*(.*)$")
  if not bracket_status then
    bracket_status, bracket_id = trimmed:match("^%[(PASS|FAIL|SKIP)%]%s+(.+)$")
  end
  if bracket_status then
    return event_from_status(
      bracket_status:lower(),
      trim(bracket_id),
      bracket_msg and trim(bracket_msg) or nil,
      parse_duration_seconds(trimmed)
    )
  end

  -- PASS: Test.vi::Case (1.2 s) / FAIL: ...
  local colon_status, colon_id, colon_msg = trimmed:match("^(PASS|FAIL|SKIP):%s+([^:]+):%s*(.*)$")
  if not colon_status then
    colon_status, colon_id = trimmed:match("^(PASS|FAIL|SKIP):%s+(.+)$")
  end
  if colon_status then
    local id = trim(colon_id)
    local duration_ms = parse_duration_seconds(id)
    if duration_ms then
      id = trim(id:gsub("%s*%([%d%.]+%s*[ms]?s?%)$", ""))
    end
    return event_from_status(
      colon_status:lower(),
      id,
      colon_msg and trim(colon_msg) or nil,
      duration_ms or parse_duration_seconds(trimmed)
    )
  end

  -- PASS Test.vi::Case / FAIL Test.vi::Case message
  local plain_status, plain_id, plain_msg = trimmed:match("^(PASS|FAIL|SKIP)%s+([^:]+):%s*(.*)$")
  if not plain_status then
    plain_status, plain_id = trimmed:match("^(PASS|FAIL|SKIP)%s+(.+)$")
  end
  if plain_status then
    return event_from_status(
      plain_status:lower(),
      trim(plain_id),
      plain_msg and trim(plain_msg) or nil,
      parse_duration_seconds(trimmed)
    )
  end

  -- VI Tester summary / runner banners
  if trimmed:match("^Running%s+test") or trimmed:match("^Test%s+[Ss]uite:") then
    return { event = "output", text = trimmed }
  end

  if trimmed:match("^=+$") or trimmed:match("^%-+$") then
    return nil
  end

  return { event = "output", text = trimmed }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  if not runner.coverage then
    return nil
  end

  local command = resolve_command(context)
  local tests = apply_filters(collect_test_vis(context), context)
  local args, lvproj = build_labview_args(context, tests)

  local coverage_vi = runner.coverage_vi or runner.coverage_runner_vi
  if coverage_vi then
    table.insert(args, coverage_vi)
  end

  local spec = {
    command = command,
    args = args,
    cwd = runner.cwd or context.target_path,
    report = runner.coverage_report or "coverage/labview-coverage.xml",
    reporter = runner.coverage_reporter or "junit",
    output = runner.coverage_output or "coverage/teez-labview.xml",
  }

  if runner.coverage_collect then
    spec.collect = runner.coverage_collect
  elseif runner.coverage_tool then
    spec.collect = {
      command = runner.coverage_tool,
      args = runner.coverage_tool_args or {},
    }
  end

  if runner.min_line_rate then
    spec.min_line_rate = runner.min_line_rate
  end

  spec.env = {}
  if runner.env then
    for key, value in pairs(runner.env) do
      spec.env[key] = value
    end
  end
  spec.env.TEEZ_LABVIEW_COVERAGE = "1"
  if #tests > 0 then
    spec.env.TEEZ_LABVIEW_TESTS = json.encode(tests)
  end
  spec.env.TEEZ_LABVIEW_PROJECT = lvproj

  return spec
end
