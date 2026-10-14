local DEFAULT_INCLUDE = { "**/*.Tests.ps1", "**/Tests/**" }

local function resolve_shell()
  local pwsh = sys.run("pwsh", { "-NoProfile", "-Command", "exit 0" })
  if pwsh.exit_code == 0 then
    return "pwsh"
  end

  local powershell = sys.run("powershell", { "-NoProfile", "-Command", "exit 0" })
  if powershell.exit_code == 0 then
    return "powershell"
  end

  error("pwsh or powershell not found on PATH")
end

local function ps_quote(value)
  return "'" .. value:gsub("'", "''") .. "'"
end

local function merge_patterns(context)
  local runner = context.runner or {}
  local include = runner.include or DEFAULT_INCLUDE
  local exclude = runner.exclude or {}
  return include, exclude
end

local function collect_targets(context)
  local include, exclude = merge_patterns(context)
  local root = context.target_path
  local seen = {}
  local targets = {}

  for _, pattern in ipairs(include) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not seen[path] then
        local excluded = false
        for _, ex in ipairs(exclude) do
          if filter.glob_match(path, ex) then
            excluded = true
            break
          end
        end
        if not excluded then
          seen[path] = true
          table.insert(targets, path)
        end
      end
    end
  end

  table.sort(targets)
  return targets
end

local function build_path_argument(context)
  local targets = collect_targets(context)
  if #targets == 0 then
    return ps_quote(context.target_path)
  end

  local quoted = {}
  for _, path in ipairs(targets) do
    table.insert(quoted, ps_quote(path))
  end
  return "@(" .. table.concat(quoted, ", ") .. ")"
end

local function append_runner_args(script, context)
  local runner = context.runner or {}
  if runner.args then
    for _, arg in ipairs(runner.args) do
      script = script .. " " .. arg
    end
  end
  return script
end

local function append_filter_args(script, context)
  if not context.filters then
    return script
  end

  local filters = context.filters
  if filters.name and filters.name ~= "" then
    script = script .. " -FullNameFilter " .. ps_quote(filters.name)
  end
  if filters.pattern and filters.pattern ~= "" then
    script = script .. " -FullNameFilter " .. ps_quote(filters.pattern)
  end
  if filters.tag and filters.tag ~= "" then
    script = script .. " -TagFilter " .. ps_quote(filters.tag)
  end

  return script
end

local function build_run_script(context)
  local target = ps_quote(context.target_path)
  local paths = build_path_argument(context)
  local script = string.format(
    "$ErrorActionPreference = 'Continue'; Set-Location %s; Invoke-Pester -Path %s -Output Detailed",
    target,
    paths
  )
  script = append_runner_args(script, context)
  script = append_filter_args(script, context)
  return script
end

local function clean_test_id(raw)
  if not raw then
    return nil
  end
  local id = raw:gsub("%s+%d+ms.*$", "")
  return id:match("^%s*(.-)%s*$")
end

local function parse_result_line(line)
  local patterns = {
    { prefix = "%[%+%]", event = "pass" },
    { prefix = "%[%-%]", event = "fail" },
    { prefix = "%[?%]", event = "skip" },
    { prefix = "%[!%]", event = "skip" },
  }

  for _, pattern in ipairs(patterns) do
    local id, duration = line:match(
      "^%s*" .. pattern.prefix .. "%s+(.+)%s+(%d+)ms"
    )
    if id then
      local event = {
        event = pattern.event,
        id = clean_test_id(id),
      }
      if duration then
        event.duration_ms = tonumber(duration)
      end
      if pattern.event == "fail" then
        event.msg = line
      end
      return event
    end

    local bare_id = line:match("^%s*" .. pattern.prefix .. "%s+(.+)$")
    if bare_id then
      local event = {
        event = pattern.event,
        id = clean_test_id(bare_id),
      }
      if pattern.event == "fail" then
        event.msg = line
      end
      return event
    end
  end

  return nil
end

function list(context)
  local shell = resolve_shell()
  local target = ps_quote(context.target_path)
  local paths = build_path_argument(context)
  local script = string.format(
    "$ErrorActionPreference = 'Stop'; Set-Location %s; $result = Invoke-Pester -Path %s -List -PassThru -Output None; if ($null -ne $result -and $null -ne $result.Tests) { $result.Tests | ForEach-Object { $_.Path } }",
    target,
    paths
  )
  script = append_filter_args(script, context)

  local output = sys.exec(shell, { "-NoProfile", "-Command", script })
  local tests = {}

  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      if not context.filters or filter.matches({ id = line }, context.filters) then
        table.insert(tests, line)
      end
    end
  end

  return tests
end

function build_command(context)
  return {
    command = resolve_shell(),
    args = { "-NoProfile", "-Command", build_run_script(context) },
  }
end

function build_coverage_run(context)
  local shell = resolve_shell()
  local target = ps_quote(context.target_path)
  local paths = build_path_argument(context)
  local coverage_dir = (context.runner or {}).coverage_dir or "coverage"
  local coverage_file = coverage_dir .. "/pester-coverage.xml"
  local quoted_coverage_file = ps_quote(coverage_file)

  local script = string.format(
    [[$ErrorActionPreference = 'Continue'; Set-Location %s; $coveragePaths = @(Get-ChildItem -Path %s -Recurse -File -Filter *.ps1 | Where-Object { $_.Name -notmatch '\.Tests\.ps1$' } | Select-Object -ExpandProperty FullName); if ($coveragePaths.Count -eq 0) { $coveragePaths = @(Get-ChildItem -Path %s -Recurse -File -Filter *.ps1 | Select-Object -ExpandProperty FullName) }; Invoke-Pester -Path %s -Output Detailed -CodeCoverage $coveragePaths -CodeCoverageOutputFile %s]],
    target,
    ps_quote(context.target_path),
    ps_quote(context.target_path),
    paths,
    quoted_coverage_file
  )
  script = append_runner_args(script, context)
  script = append_filter_args(script, context)

  return {
    command = shell,
    args = { "-NoProfile", "-Command", script },
    report = coverage_file,
    reporter = "jacoco",
    output = coverage_dir .. "/teez-coverage.msgpack",
  }
end

function parse_line(line)
  if line == "" or line:match("^%s*$") then
    return nil
  end

  if line:match("^%s*Describing%s") or line:match("^%s*Context%s") then
    return { event = "output", text = line }
  end

  if line:match("^%s*Discovery%s") or line:match("^%s*Running%s") or line:match("^%s*Tests%s") then
    return { event = "output", text = line }
  end

  local result = parse_result_line(line)
  if result then
    return result
  end

  if line:match("^%s*[✓✔]") then
    return {
      event = "pass",
      id = clean_test_id(line:gsub("^%s*[✓✔]%s*", "")),
    }
  end

  if line:match("^%s*[×✗]") then
    return {
      event = "fail",
      id = clean_test_id(line:gsub("^%s*[×✗]%s*", "")),
      msg = line,
    }
  end

  return { event = "output", text = line }
end
