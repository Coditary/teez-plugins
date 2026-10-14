local DEFAULT_INCLUDES = { "**/*Test*.pas", "**/tests/**/*.pas" }
local active_tool = "fpcunit"

local function runner_cfg(context)
  return context.runner or {}
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function path_join(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function strip_ext(path)
  return path:gsub("%.[^%.]+$", "")
end

local function relative_path(root, path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  if path:sub(1, #root) == root then
    return path:sub(#root + 1):gsub("^/", "")
  end
  return path
end

local function on_path(command)
  local result = sys.run("sh", { "-c", "command -v " .. shell_quote(command) .. " >/dev/null 2>&1" })
  return result.exit_code == 0
end

local function tool_name(context)
  local tool = runner_cfg(context).tool or "fpcunit"
  if tool ~= "dunitx" and tool ~= "fpcunit" then
    return "fpcunit"
  end
  return tool
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  local patterns = {}
  local seen = {}

  local function add(pattern)
    if pattern and pattern ~= "" and not seen[pattern] then
      seen[pattern] = true
      table.insert(patterns, pattern)
    end
  end

  if cfg.include then
    if type(cfg.include) == "table" then
      for _, pattern in ipairs(cfg.include) do
        add(pattern)
      end
    else
      add(cfg.include)
    end
  end

  for _, pattern in ipairs(DEFAULT_INCLUDES) do
    add(pattern)
  end

  return patterns
end

local function exclude_patterns(context)
  local cfg = runner_cfg(context)
  local patterns = { "**/*.teez.lua" }
  if cfg.exclude then
    if type(cfg.exclude) == "table" then
      for _, pattern in ipairs(cfg.exclude) do
        table.insert(patterns, pattern)
      end
    else
      table.insert(patterns, cfg.exclude)
    end
  end
  return patterns
end

local function is_excluded(path, excludes)
  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_test_pas(path)
  return path:match("%.pas$") and not path:match("%.pp%.pas$")
end

local function find_project(root)
  for _, pattern in ipairs({ "*.lpi", "*.dpr", "*.lpr" }) do
    local hits = fs.glob(root, pattern)
    if hits and #hits > 0 then
      table.sort(hits)
      return hits[1], pattern:sub(3)
    end
  end
  return nil, nil
end

local function find_test_program(root, cfg, project_path, project_ext)
  if cfg.test_program and cfg.test_program ~= "" then
    local candidate = cfg.test_program
    if not candidate:match("^/") then
      candidate = path_join(root, candidate)
    end
    if fs.exists(candidate) then
      return candidate
    end
  end

  local preferred = {
    "testrunner.lpr",
    "testrunner.dpr",
    "tests.lpr",
    "tests.dpr",
    "alltests.lpr",
    "alltests.dpr",
  }
  for _, name in ipairs(preferred) do
    local candidate = path_join(root, name)
    if fs.exists(candidate) then
      return candidate
    end
  end

  for _, pattern in ipairs({ "**/*Test*.lpr", "**/*Test*.dpr", "**/tests/*.lpr", "**/tests/*.dpr" }) do
    local hits = fs.glob(root, pattern)
    if hits and #hits > 0 then
      table.sort(hits)
      return hits[1]
    end
  end

  if project_path and (project_ext == "lpr" or project_ext == "dpr") then
    return project_path
  end

  return nil
end

local function default_binary_name(test_program, cfg)
  if cfg.binary_name and cfg.binary_name ~= "" then
    return cfg.binary_name
  end
  return basename(strip_ext(test_program))
end

local function fpc_unit_paths(tool)
  if tool == "dunitx" then
    return { "-dDUNITX" }
  end
  return { "-dFPCUNIT" }
end

local function collect_test_files(context)
  local root = context.target_path
  local includes = include_patterns(context)
  local excludes = exclude_patterns(context)
  local files = {}
  local seen = {}

  for _, pattern in ipairs(includes) do
    local hits = fs.glob(root, pattern)
    if hits then
      for _, path in ipairs(hits) do
        if is_test_pas(path) and not is_excluded(path, excludes) and not seen[path] then
          seen[path] = true
          table.insert(files, path)
        end
      end
    end
  end

  table.sort(files)
  return files
end

local function test_id_from_path(root, path)
  return strip_ext(relative_path(root, path))
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

function list(context)
  local files = collect_test_files(context)
  local ids = {}
  for _, path in ipairs(files) do
    table.insert(ids, test_id_from_path(context.target_path, path))
  end
  return apply_filters(ids, context.filters)
end

local function build_dir(context)
  local cfg = runner_cfg(context)
  if cfg.build_dir and cfg.build_dir ~= "" then
    if cfg.build_dir:match("^/") then
      return cfg.build_dir
    end
    return path_join(context.target_path, cfg.build_dir)
  end
  return path_join(context.target_path, ".teez", "pascal")
end

local function append_table(dest, src)
  if not src then
    return dest
  end
  for _, value in ipairs(src) do
    table.insert(dest, value)
  end
  return dest
end

local function build_fpc_args(context, test_program, for_coverage)
  local cfg = runner_cfg(context)
  local tool = tool_name(context)
  local args = { "-Mobjfpc", "-Sc", "-Sg", "-Sh" }
  append_table(args, fpc_unit_paths(tool))

  if for_coverage then
    append_table(args, cfg.coverage_fpc_options or { "-Pi", "-O-", "-gl" })
  else
    append_table(args, cfg.fpc_options)
  end

  if cfg.unit_paths then
    for _, unit_path in ipairs(cfg.unit_paths) do
      table.insert(args, "-Fu" .. unit_path)
    end
  end

  table.insert(args, "-FE" .. build_dir(context))
  table.insert(args, "-o" .. default_binary_name(test_program, cfg))
  table.insert(args, test_program)
  return args
end

local function run_binary_command(context, test_program, for_coverage)
  local cfg = runner_cfg(context)
  local out_dir = build_dir(context)
  local binary = path_join(out_dir, default_binary_name(test_program, cfg))
  local tool = tool_name(context)

  local run_args = {}
  if cfg.run_args then
    append_table(run_args, cfg.run_args)
  end
  if tool == "dunitx" and not cfg.quiet then
    table.insert(run_args, "--consolemode=DXMPlain")
  end

  local fpc_args = build_fpc_args(context, test_program, for_coverage)
  local script = table.concat({
    "set -e",
    "mkdir -p " .. shell_quote(out_dir),
    shell_quote("fpc") .. " " .. table.concat(fpc_args, " "),
    shell_quote(binary) .. " " .. table.concat(run_args, " "),
  }, " && ")

  return {
    command = "sh",
    args = { "-c", script },
    cwd = context.target_path,
  }
end

local function build_lazbuild_command(context, project_path, test_program, for_coverage)
  local cfg = runner_cfg(context)
  local out_dir = build_dir(context)
  local binary = path_join(out_dir, default_binary_name(test_program, cfg))
  local args = { project_path, "--build-mode=" .. (cfg.build_mode or "Debug") }

  if cfg.lazarus_target and cfg.lazarus_target ~= "" then
    table.insert(args, "--target=" .. cfg.lazarus_target)
  end

  if for_coverage and cfg.lazarus_coverage_options then
    for _, opt in ipairs(cfg.lazarus_coverage_options) do
      table.insert(args, opt)
    end
  end

  local run_args = {}
  if cfg.run_args then
    append_table(run_args, cfg.run_args)
  end

  local script
  if cfg.lazarus_output then
    binary = cfg.lazarus_output
    if not binary:match("^/") then
      binary = path_join(context.target_path, binary)
    end
    script = table.concat({
      "set -e",
      shell_quote("lazbuild") .. " " .. table.concat(args, " "),
      shell_quote(binary) .. " " .. table.concat(run_args, " "),
    }, " && ")
  else
    script = table.concat({
      "set -e",
      "mkdir -p " .. shell_quote(out_dir),
      shell_quote("lazbuild") .. " " .. table.concat(args, " "),
      shell_quote("fpc") .. " "
        .. table.concat(build_fpc_args(context, test_program, for_coverage), " "),
      shell_quote(binary) .. " " .. table.concat(run_args, " "),
    }, " && ")
  end

  return {
    command = "sh",
    args = { "-c", script },
    cwd = context.target_path,
  }
end

local function resolve_run_command(context, for_coverage)
  local cfg = runner_cfg(context)
  local root = context.target_path
  local project_path, project_ext = find_project(root)
  local test_program = find_test_program(root, cfg, project_path, project_ext)

  if not test_program then
    error("pascal runner: no test program found (.lpr/.dpr); set runners.pascal.test_program")
  end

  local use_lazbuild = cfg.use_lazbuild
  if use_lazbuild == nil then
    use_lazbuild = project_ext == "lpi" and on_path("lazbuild")
  end

  if use_lazbuild and project_path and project_ext == "lpi" then
    if not on_path("lazbuild") then
      error("pascal runner: lazarus project found but lazbuild is not on PATH")
    end
    return build_lazbuild_command(context, project_path, test_program, for_coverage)
  end

  return run_binary_command(context, test_program, for_coverage)
end

function build_command(context)
  active_tool = tool_name(context)
  return resolve_run_command(context, false)
end

function build_coverage_run(context)
  local cfg = runner_cfg(context)
  if not cfg.coverage then
    return nil
  end

  active_tool = tool_name(context)
  local spec = resolve_run_command(context, true)
  local output = cfg.coverage_output or "coverage/lcov.info"
  local report_dir = output:match("^(.+)/[^/]+$") or "coverage"

  spec.collect = {
    command = "lcov",
    args = {
      "--capture",
      "--directory",
      build_dir(context),
      "--output-file",
      output,
      "--ignore-errors",
      "source",
    },
  }

  if cfg.lcov_remove_patterns then
    for _, pattern in ipairs(cfg.lcov_remove_patterns) do
      table.insert(spec.collect.args, "--remove")
      table.insert(spec.collect.args, output)
      table.insert(spec.collect.args, pattern)
    end
  end

  spec.report = output
  spec.reporter = cfg.coverage_reporter or "lcov"
  spec.output = cfg.coverage_teez_output or path_join(report_dir, "teez.msgpack")
  spec.min_line_rate = cfg.min_line_rate
  return spec
end

local function parse_fpcunit_line(line)
  local suite, msg = line:match("^%s*([^%.]+%.[^%.%s]+)%s*%.%.%.%s*FAILED%s*:%s*(.*)$")
  if suite then
    return { event = "fail", id = suite, msg = msg }
  end

  suite = line:match("^%s*([^%.]+%.[^%.%s]+)%s*%.%.%.%s*ERROR%s*:%s*(.*)$")
  if suite then
    return { event = "fail", id = suite, msg = suite .. ": " .. (msg or "ERROR") }
  end

  suite = line:match("^%s*([^%.]+%.[^%.%s]+)%s*%.%.%.%s*OK%s*")
  if suite then
    local duration_ms = line:match(":%s*([%d%.]+)%s*$")
    local event = { event = "pass", id = suite }
    if duration_ms then
      event.duration_ms = math.floor((tonumber(duration_ms) or 0) * 1000)
    end
    return event
  end

  if line:match("^OK:%s*%d+") or line:match("^%s*No errors found") then
    return { event = "output", text = line }
  end

  if line:match("^FAILED:%s*%d+") or line:match("^%s*There were errors") then
    return { event = "output", text = line }
  end

  return nil
end

local function parse_dunitx_line(line)
  local id, msg = line:match("^%[FAIL%]%s*(.-)%s*%-%s*(.*)$")
  if id then
    return { event = "fail", id = id, msg = msg }
  end

  id = line:match("^%[ERROR%]%s*(.+)$")
  if id then
    return { event = "fail", id = id, msg = line }
  end

  id = line:match("^%[PASS%]%s*(.+)$")
  if id then
    return { event = "pass", id = id }
  end

  id = line:match("^%[SKIP%]%s*(.+)$")
  if id then
    return { event = "skip", id = id }
  end

  id, msg = line:match("^%s*FAILED:%s*(.-)%s*%-%s*(.*)$")
  if id then
    return { event = "fail", id = id, msg = msg }
  end

  id = line:match("^%s*PASSED:%s*(.+)$")
  if id then
    return { event = "pass", id = id }
  end

  return nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local event
  if active_tool == "dunitx" then
    event = parse_dunitx_line(line) or parse_fpcunit_line(line)
  else
    event = parse_fpcunit_line(line) or parse_dunitx_line(line)
  end

  if event then
    return event
  end

  if line:match("^[%.FE]$") or line:match("^[%.FE%s]+$") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
