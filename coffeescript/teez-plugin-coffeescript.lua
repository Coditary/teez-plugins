-- teez runner for CoffeeScript projects using Jasmine or Mocha (historical JS stack).

local DEFAULT_INCLUDE = { "**/*_spec.coffee", "**/spec/**" }
local DEFAULT_EXCLUDE = { "**/node_modules/**", "**/*.teez.lua" }

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function path_join(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local function relative_path(base, abs)
  base = base:gsub("/+$", "")
  abs = abs:gsub("/+$", "")
  if abs:sub(1, #base + 1) == base .. "/" then
    return abs:sub(#base + 2)
  end
  if abs == base then
    return "."
  end
  return abs
end

local function read_json_file(path)
  if not fs.exists(path) then
    return nil
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local raw = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, raw)
  if ok then
    return data
  end
  return nil
end

local function package_json(context)
  local path = path_join(context.target_path, "package.json")
  return read_json_file(path)
end

local function deps_table(pkg)
  local deps = {}
  if not pkg then
    return deps
  end
  for _, key in ipairs({ "dependencies", "devDependencies", "peerDependencies" }) do
    local section = pkg[key]
    if type(section) == "table" then
      for name, _ in pairs(section) do
        deps[name] = true
      end
    end
  end
  return deps
end

local function script_text(pkg)
  if not pkg or type(pkg.scripts) ~= "table" then
    return ""
  end
  local parts = {}
  for _, value in pairs(pkg.scripts) do
    if type(value) == "string" then
      table.insert(parts, value)
    end
  end
  return table.concat(parts, " ")
end

local function detect_framework(context)
  local runner = context.runner or {}
  if runner.framework == "mocha" or runner.framework == "jasmine" then
    return runner.framework
  end

  local pkg = package_json(context)
  local deps = deps_table(pkg)
  local scripts = script_text(pkg)

  if deps["jasmine"] or deps["jasmine-node"] or scripts:find("jasmine", 1, true) then
    return "jasmine"
  end
  if deps["mocha"] or scripts:find("mocha", 1, true) then
    return "mocha"
  end

  return runner.framework or "mocha"
end

local function coffee_require(context)
  local runner = context.runner or {}
  if runner.coffee_require then
    return runner.coffee_require
  end

  local pkg = package_json(context)
  local deps = deps_table(pkg)
  if deps["coffee-script"] then
    return "coffee-script/register"
  end
  if deps["coffeescript"] then
    return "coffeescript/register"
  end
  return "coffeescript/register"
end

local function merged_patterns(context, key, defaults)
  local runner = context.runner or {}
  local patterns = {}
  for _, pattern in ipairs(defaults) do
    table.insert(patterns, pattern)
  end
  local extra = runner[key]
  if type(extra) == "string" then
    table.insert(patterns, extra)
  elseif type(extra) == "table" then
    for _, pattern in ipairs(extra) do
      table.insert(patterns, pattern)
    end
  end
  return patterns
end

local function is_excluded(path, exclude_patterns)
  for _, pattern in ipairs(exclude_patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function discover_spec_files(context)
  local include = merged_patterns(context, "include", DEFAULT_INCLUDE)
  local exclude = merged_patterns(context, "exclude", DEFAULT_EXCLUDE)
  local seen = {}
  local files = {}

  for _, pattern in ipairs(include) do
    local matches = fs.glob(context.target_path, pattern)
    for _, match in ipairs(matches) do
      local abs = match
      if not abs:match("^/") then
        abs = path_join(context.target_path, match)
      end
      if abs:match("%.coffee$") and not seen[abs] and not is_excluded(abs, exclude) then
        seen[abs] = true
        table.insert(files, abs)
      end
    end
  end

  table.sort(files)
  return files
end

local function make_test_id(file_path, title, base_path)
  local rel = relative_path(base_path, file_path)
  if title and title ~= "" then
    return rel .. "::" .. title
  end
  return rel
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

local function collect_mocha_ids(context, files)
  if #files == 0 then
    return {}
  end

  local args = {
    "mocha",
    "--reporter",
    "json",
    "--no-color",
    "--require",
    coffee_require(context),
  }

  local runner = context.runner or {}
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end

  for _, file in ipairs(files) do
    table.insert(args, file)
  end

  local result = sys.run("npx", args, { cwd = context.target_path })
  if result.exit_code ~= 0 and result.stdout == "" then
    local fallback = {}
    for _, file in ipairs(files) do
      table.insert(fallback, make_test_id(file, nil, context.target_path))
    end
    return fallback
  end

  local ok, payload = pcall(json.decode, result.stdout)
  if not ok or type(payload) ~= "table" then
    local fallback = {}
    for _, file in ipairs(files) do
      table.insert(fallback, make_test_id(file, nil, context.target_path))
    end
    return fallback
  end

  local ids = {}
  local tests = payload.tests or {}
  for _, test in ipairs(tests) do
    local file = test.file or test.filePath
    local title = test.fullTitle or test.title
    if file and title then
      table.insert(ids, make_test_id(file, title, context.target_path))
    end
  end

  if #ids == 0 then
    for _, file in ipairs(files) do
      table.insert(ids, make_test_id(file, nil, context.target_path))
    end
  end

  return ids
end

local function collect_jasmine_ids(context, files)
  if #files == 0 then
    return {}
  end

  local ids = {}
  for _, file in ipairs(files) do
    table.insert(ids, make_test_id(file, nil, context.target_path))
  end
  return ids
end

local function selected_files(context, all_files)
  local runner = context.runner or {}
  if type(runner.files) == "table" and #runner.files > 0 then
    local selected = {}
    for _, entry in ipairs(runner.files) do
      local abs = entry
      if not abs:match("^/") then
        abs = path_join(context.target_path, entry)
      end
      table.insert(selected, abs)
    end
    return selected
  end
  return all_files
end

function list(context)
  local files = discover_spec_files(context)
  files = selected_files(context, files)
  local framework = detect_framework(context)
  local ids

  if framework == "jasmine" then
    ids = collect_jasmine_ids(context, files)
  else
    ids = collect_mocha_ids(context, files)
  end

  return apply_filters(ids, context.filters)
end

local function grep_from_filters(filters, runner)
  if runner and runner.grep then
    return runner.grep
  end
  if not filters then
    return nil
  end
  if type(filters.pattern) == "string" and filters.pattern ~= "" then
    return filters.pattern
  end
  if type(filters.name) == "string" and filters.name ~= "" then
    return filters.name
  end
  return nil
end

local function build_mocha_command(context, files)
  local runner = context.runner or {}
  local args = {
    "mocha",
    "--reporter",
    runner.reporter or "spec",
    "--require",
    coffee_require(context),
  }

  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end

  local grep = grep_from_filters(context.filters, runner)
  if grep then
    table.insert(args, "--grep")
    table.insert(args, grep)
  end

  if runner.timeout then
    table.insert(args, "--timeout")
    table.insert(args, tostring(runner.timeout))
  end

  for _, file in ipairs(files) do
    table.insert(args, file)
  end

  return {
    command = "npx",
    args = args,
    cwd = context.target_path,
  }
end

local function build_jasmine_command(context, files)
  local runner = context.runner or {}
  local args = { "jasmine" }

  if runner.config then
    table.insert(args, "--config=" .. runner.config)
  end

  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end

  local filter = grep_from_filters(context.filters, runner)
  if filter then
    table.insert(args, "--filter=" .. filter)
  end

  for _, file in ipairs(files) do
    table.insert(args, file)
  end

  local spec = {
    command = "npx",
    args = args,
    cwd = context.target_path,
    env = {
      NODE_OPTIONS = "--require " .. coffee_require(context),
    },
  }

  if runner.jasmine_config then
    spec.env.JASMINE_CONFIG_PATH = runner.jasmine_config
  end

  return spec
end

function build_command(context)
  local files = discover_spec_files(context)
  files = selected_files(context, files)

  if detect_framework(context) == "jasmine" then
    return build_jasmine_command(context, files)
  end
  return build_mocha_command(context, files)
end

local function parse_duration_ms(text)
  local ms = text:match("%((%d+)ms%)")
  if ms then
    return tonumber(ms)
  end
  local sec = text:match("%(([%d%.]+)s%)")
  if sec then
    return math.floor(tonumber(sec) * 1000)
  end
  return nil
end

local mocha_state = {
  suite_parts = {},
}

local function reset_mocha_state()
  mocha_state.suite_parts = {}
end

local function mocha_full_title(title)
  if #mocha_state.suite_parts == 0 then
    return title
  end
  return table.concat(mocha_state.suite_parts, " ") .. " " .. title
end

local function parse_mocha_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local pass = line:match("^%s*[✓✔]%s+(.+)$")
  if pass then
    local duration_ms = parse_duration_ms(pass)
    local title = pass:gsub("%s*%(%d+ms%)$", ""):gsub("%s*%([%d%.]+s%)$", "")
    return { event = "pass", id = mocha_full_title(title), duration_ms = duration_ms }
  end

  local fail_num = line:match("^%s*(%d+)%)%s+(.+)$")
  if fail_num then
    return { event = "fail", id = fail_num, msg = line }
  end

  local indent = line:match("^(%s+)(%S.+)$")
  if indent and not line:match("^%s*[✓✔✗×]") and not line:match("^%s*%d+%)") then
    local depth = math.floor(#indent / 2) + 1
    local name = trim(line)
    mocha_state.suite_parts[depth] = name
    for i = depth + 1, #mocha_state.suite_parts do
      mocha_state.suite_parts[i] = nil
    end
    return { event = "start", id = table.concat(mocha_state.suite_parts, " ") }
  end

  return { event = "output", text = line }
end

local jasmine_state = {
  current_suite = nil,
}

local function reset_jasmine_state()
  jasmine_state.current_suite = nil
end

local function parse_jasmine_line(line)
  line = trim(line)
  if line == "" or line:match("^%-+$") then
    return nil
  end

  if line:match("^Started") or line:match("^Finished") or line:match("^Randomized with seed") then
    return nil
  end

  local pass = line:match("^%s*[✓✔*]%s+(.+)$")
  if pass then
    local duration_ms = parse_duration_ms(pass)
    local title = pass:gsub("%s*%(%d+ms%)$", ""):gsub("%s*%([%d%.]+s%)$", "")
    local id = title
    if jasmine_state.current_suite then
      id = jasmine_state.current_suite .. " " .. title
    end
    return { event = "pass", id = id, duration_ms = duration_ms }
  end

  local fail = line:match("^%s*[✗×]%s+(.+)$")
  if fail then
    local title = fail
    local id = title
    if jasmine_state.current_suite then
      id = jasmine_state.current_suite .. " " .. title
    end
    return { event = "fail", id = id, msg = line }
  end

  local numbered = line:match("^(%d+)%)%s+(.+)$")
  if numbered then
    return { event = "fail", id = numbered, msg = line }
  end

  if not line:match("^%s") and not line:match("^[✓✔✗×*]") and not line:match("^%d+%)") then
    jasmine_state.current_suite = line
    return { event = "start", id = line }
  end

  return { event = "output", text = line }
end

function parse_line(line)
  local mocha_event = parse_mocha_line(line)
  if mocha_event and mocha_event.event ~= "output" then
    return mocha_event
  end

  local jasmine_event = parse_jasmine_line(line)
  if jasmine_event then
    return jasmine_event
  end

  return mocha_event or { event = "output", text = line }
end

function build_coverage_run(context)
  local runner = context.runner or {}
  local coverage = runner.coverage or {}
  if coverage.enabled == false then
    return nil
  end

  local files = discover_spec_files(context)
  files = selected_files(context, files)
  local framework = detect_framework(context)
  local nyc = coverage.command or "nyc"
  local reporter = coverage.reporter or "lcov"
  local output = coverage.output or "coverage/lcov.info"
  local report = coverage.report or output

  local args = {
    nyc,
    "--reporter=" .. reporter,
    "--report-dir",
    coverage.report_dir or "coverage",
  }

  if coverage.extension then
    for _, ext in ipairs(coverage.extension) do
      table.insert(args, "--extension")
      table.insert(args, ext)
    end
  else
    table.insert(args, "--extension")
    table.insert(args, ".coffee")
  end

  if coverage.include then
    for _, pattern in ipairs(coverage.include) do
      table.insert(args, "--include")
      table.insert(args, pattern)
    end
  end

  if coverage.exclude then
    for _, pattern in ipairs(coverage.exclude) do
      table.insert(args, "--exclude")
      table.insert(args, pattern)
    end
  end

  if coverage.nyc_args then
    for _, arg in ipairs(coverage.nyc_args) do
      table.insert(args, arg)
    end
  end

  if framework == "jasmine" then
    table.insert(args, "jasmine")
    if runner.config then
      table.insert(args, "--config=" .. runner.config)
    end
    if runner.args then
      for _, arg in ipairs(runner.args) do
        table.insert(args, arg)
      end
    end
    for _, file in ipairs(files) do
      table.insert(args, file)
    end
  else
    table.insert(args, "mocha")
    table.insert(args, "--require")
    table.insert(args, coffee_require(context))
    if runner.args then
      for _, arg in ipairs(runner.args) do
        table.insert(args, arg)
      end
    end
    for _, file in ipairs(files) do
      table.insert(args, file)
    end
  end

  return {
    command = "npx",
    args = args,
    cwd = context.target_path,
    env = framework == "jasmine" and {
      NODE_OPTIONS = "--require " .. coffee_require(context),
    } or nil,
    collect = coverage.collect,
    report = report,
    reporter = coverage.teez_reporter or "lcov",
    output = coverage.teez_output or "coverage/teez.lcov",
    min_line_rate = coverage.min_line_rate,
  }
end
