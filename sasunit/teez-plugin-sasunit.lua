local DEFAULT_DRIVER = "run_tests.sas"
local DEFAULT_INCLUDE = { "**/tests/**/*.sas", "**/ex_*/*.sas" }

local function trim(value)
  return (value:match("^%s*(.-)%s*$") or value)
end

local function sas_executable(context)
  local runner = context.runner or {}
  return runner.sas or runner.sas_executable or "sas"
end

local function runner_patterns(context, key, fallback)
  local runner = context.runner or {}
  local patterns = runner[key]
  if patterns == nil then
    return fallback
  end
  return patterns
end

local function matches_any(path, patterns)
  if not patterns then
    return false
  end
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function relative_path(root, path)
  local prefix = root
  if not prefix:match("/$") then
    prefix = prefix .. "/"
  end
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

local function discover_test_files(context)
  local root = context.target_path
  local includes = runner_patterns(context, "include", DEFAULT_INCLUDE)
  local excludes = runner_patterns(context, "exclude", {})
  local files = {}
  local seen = {}

  for _, pattern in ipairs(includes) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      local rel = relative_path(root, path)
      if rel ~= "" and not seen[rel] and not matches_any(rel, excludes) then
        seen[rel] = true
        table.insert(files, rel)
      end
    end
  end

  table.sort(files)
  return files
end

local function scenario_id_for_file(file)
  local tests_match = file:match("^(tests/[^/]+)")
  if tests_match then
    return tests_match
  end

  local ex_match = file:match("^(ex_[^/]+)")
  if ex_match then
    return ex_match
  end

  return file:match("^([^/]+)") or file
end

local function discover_test_folders(context)
  local folders = {}
  local seen = {}

  for _, file in ipairs(discover_test_files(context)) do
    local id = scenario_id_for_file(file)
    if id and not seen[id] then
      seen[id] = true
      table.insert(folders, id)
    end
  end

  table.sort(folders)
  return folders
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

local function driver_path(context)
  local runner = context.runner or {}
  local driver = runner.driver or runner.batch_driver or DEFAULT_DRIVER
  if driver:match("^/") then
    return driver
  end
  return context.target_path .. "/" .. driver
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function merge_env(spec, extra)
  if not extra then
    return
  end
  spec.env = spec.env or {}
  for key, value in pairs(extra) do
    spec.env[key] = value
  end
end

local function build_sas_spec(context, opts)
  local runner = context.runner or {}
  local args = {}

  append_args(args, runner.sas_args)
  table.insert(args, "-sysin")
  table.insert(args, opts.driver or driver_path(context))

  if runner.log then
    table.insert(args, "-log")
    table.insert(args, runner.log)
  end

  if runner.print then
    table.insert(args, "-print")
    table.insert(args, runner.print)
  end

  append_args(args, runner.args)
  append_args(args, opts.extra_args)

  local spec = {
    command = sas_executable(context),
    args = args,
    cwd = runner.cwd or context.target_path,
  }

  merge_env(spec, runner.env)
  merge_env(spec, opts.env)

  if context.filters then
    spec.env = spec.env or {}
    spec.env.TEEZ_SASUNIT_FILTERS = json.encode(context.filters)
  end

  if runner.scenario then
    spec.env = spec.env or {}
    spec.env.SASUNIT_SCENARIO = runner.scenario
  end

  return spec
end

function list(context)
  return apply_filters(discover_test_folders(context), context.filters)
end

function build_command(context)
  return build_sas_spec(context, {})
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local id, status = line:match("^Testscenario:%s*(.-)%s+(PASSED|FAILED)")
  if id and status then
    return {
      event = status == "PASSED" and "pass" or "fail",
      id = trim(id),
      msg = status == "FAILED" and line or nil,
    }
  end

  id, status = line:match("^Testfall:%s*(.-)%s+(BESTANDEN|FEHLGESCHLAGEN)")
  if id and status then
    return {
      event = status == "BESTANDEN" and "pass" or "fail",
      id = trim(id),
      msg = status == "FEHLGESCHLAGEN" and line or nil,
    }
  end

  id = line:match("Test%s*scenario%s*[\"']([^\"']+)[\"']")
  if id then
    local upper = line:upper()
    if upper:find("PASSED", 1, true) or upper:find("BESTANDEN", 1, true) then
      return { event = "pass", id = trim(id) }
    end
    if upper:find("FAILED", 1, true) or upper:find("FEHLGESCHLAGEN", 1, true) then
      return { event = "fail", id = trim(id), msg = line }
    end
    if upper:find("SKIP", 1, true) or upper:find("SKIPPED", 1, true) then
      return { event = "skip", id = trim(id) }
    end
  end

  id, status = line:match("%*%*%*%s*Testcase%s+([^:]+):%s*(PASS|FAIL|FAILED|PASSED)")
  if id and status then
    return {
      event = (status == "PASS" or status == "PASSED") and "pass" or "fail",
      id = trim(id),
      msg = line,
    }
  end

  id = line:match("=====+%s*Test%s*Scenario:%s*([^=]+)=%s*=====+")
  if id then
    return { event = "start", id = trim(id) }
  end

  if line:match("SASUnit") and (line:match("[Ff]ail") or line:match("FEHLER")) then
    id = line:match("scenario%s*[\"']?([^\"']+)[\"']?")
      or line:match("Testscenario%s*([^%s]+)")
      or "sasunit"
    return { event = "fail", id = trim(id), msg = line }
  end

  if line:match("ERROR:") and line:match("[Tt]est") then
    id = line:match("Testscenario%s*([^%s]+)") or line:match("Test%s*scenario%s*[\"']([^\"']+)[\"']")
    if id then
      return { event = "fail", id = trim(id), msg = line }
    end
  end

  return nil
end

function build_coverage_run(context)
  local runner = context.runner or {}
  if not runner.coverage then
    return nil
  end

  local coverage = runner.coverage
  if type(coverage) ~= "table" then
    coverage = {}
  end

  local extra_args = { "-cov" }
  append_args(extra_args, coverage.sas_args)

  local spec = build_sas_spec(context, {
    driver = coverage.driver or runner.coverage_driver,
    extra_args = extra_args,
    env = coverage.env,
  })

  local collect = coverage.collect
  if not collect and coverage.collect_command then
    collect = {
      command = coverage.collect_command,
      args = coverage.collect_args or {},
    }
  end

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = spec.env,
    collect = collect,
    report = coverage.report or "coverage/sasunit.lcov",
    reporter = coverage.reporter or "lcov",
    output = coverage.output or "coverage/teez.msgpack",
    min_line_rate = coverage.min_line_rate,
  }
end
