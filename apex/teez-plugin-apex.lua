local DEFAULT_INCLUDE = {
  "**/classes/*Test.cls",
  "**/tests/**",
}

local ANCHOR_FILES = {
  "sfdx-project.json",
  "sf-project.json",
}

local OUTCOMES = {
  Pass = "pass",
  Fail = "fail",
  CompileFail = "fail",
  Skip = "skip",
}

local function trim(text)
  if not text then
    return ""
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function join_path(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

local function append_unique(list, seen, value)
  if value == nil or value == "" or seen[value] then
    return
  end
  seen[value] = true
  table.insert(list, value)
end

local function merge_patterns(context)
  local patterns = {}

  if context.runner and context.runner.include then
    for _, pattern in ipairs(context.runner.include) do
      table.insert(patterns, pattern)
    end
  end

  if #patterns == 0 then
    patterns = DEFAULT_INCLUDE
  end

  return patterns
end

local function find_project_root(start_path)
  local path = start_path
  while path and path ~= "" do
    for _, anchor in ipairs(ANCHOR_FILES) do
      if fs.exists(join_path(path, anchor)) then
        return path
      end
    end

    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == path then
      break
    end
    path = parent
  end

  return start_path
end

local function read_file(path)
  local handle = io.open(path, "r")
  if handle then
    local content = handle:read("*a")
    handle:close()
    return content
  end

  local result = sys.run("cat", { path })
  if result.exit_code ~= 0 then
    return nil
  end
  return result.stdout
end

local function class_name_from_path(path)
  local file_name = path:match("([^/]+)$")
  if not file_name then
    return nil
  end

  local class_name = file_name:match("^(.+)%.cls$")
  if class_name and class_name ~= "" then
    return class_name
  end

  return nil
end

local function class_name_from_source(content)
  local class_name = content:match("@[%s]*[Ii]s[%s]*[Tt]est[%s]*.-class%s+([%w_]+)")
  if class_name then
    return class_name
  end

  return content:match("class%s+([%w_]+)")
end

local function discover_methods_in_source(class_name, content)
  local methods = {}
  local seen = {}

  for method_name in content:gmatch("@[%s]*[Ii]s[%s]*[Tt]est[%s]*.-[%w_]+%s+([%w_]+)%s*%(") do
    append_unique(methods, seen, class_name .. "." .. method_name)
  end

  for annotation, method_name in content:gmatch("(@[%s]*[Ii]s[%s]*[Tt]est[%s]*.-)[\r\n]+[%w_%s]+([%w_]+)%s*%(") do
    if annotation then
      append_unique(methods, seen, class_name .. "." .. method_name)
    end
  end

  return methods
end

local function discover_local_tests(context)
  local tests = {}
  local seen = {}
  local root = find_project_root(context.target_path)

  for _, pattern in ipairs(merge_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if path:match("%.cls$") then
        local class_name = class_name_from_path(path)
        local content = read_file(path)

        if not class_name and content then
          class_name = class_name_from_source(content)
        end

        if class_name then
          append_unique(tests, seen, class_name)

          if content and content ~= "" then
            for _, method_id in ipairs(discover_methods_in_source(class_name, content)) do
              append_unique(tests, seen, method_id)
            end
          end
        end
      end
    end
  end

  return tests
end

local function discover_org_tests(context)
  local root = find_project_root(context.target_path)
  local result = sys.run("sf", { "apex", "list", "test", "--json" }, { cwd = root })
  if result.exit_code ~= 0 or trim(result.stdout) == "" then
    return nil
  end

  local ok, payload = pcall(json.decode, result.stdout)
  if not ok or type(payload) ~= "table" then
    return nil
  end

  local records = payload.result or payload.records or payload
  if type(records) ~= "table" then
    return nil
  end

  local tests = {}
  local seen = {}

  for _, record in ipairs(records) do
    local class_name = record.Name or record.name
    if type(class_name) == "string" then
      append_unique(tests, seen, class_name)
    end
  end

  if #tests == 0 then
    return nil
  end

  return tests
end

local function apply_filters(tests, filters)
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
  local tests = discover_local_tests(context)
  if #tests == 0 then
    local org_tests = discover_org_tests(context)
    if org_tests then
      tests = org_tests
    end
  end

  return apply_filters(tests, context.filters)
end

local function tests_for_run(tests)
  local methods = {}
  local classes = {}
  local classes_with_methods = {}

  for _, id in ipairs(tests) do
    local class_name, method_name = id:match("^([^%.]+)%.(.+)$")
    if method_name then
      table.insert(methods, id)
      classes_with_methods[class_name] = true
    else
      classes[id] = true
    end
  end

  local run_tests = {}
  for class_name, _ in pairs(classes) do
    if not classes_with_methods[class_name] then
      table.insert(run_tests, class_name)
    end
  end
  for _, method_id in ipairs(methods) do
    table.insert(run_tests, method_id)
  end

  table.sort(run_tests)
  return run_tests
end

local function runner_args(context)
  if context.runner and context.runner.args then
    return context.runner.args
  end
  return {}
end

local function build_base_args(context, result_format)
  local root = find_project_root(context.target_path)
  local tests = tests_for_run(collect_tests(context))
  local args = {
    "apex",
    "run",
    "test",
    "--result-format",
    result_format,
    "--synchronous",
  }

  for _, extra in ipairs(runner_args(context)) do
    table.insert(args, extra)
  end

  if #tests > 0 then
    table.insert(args, "--tests")
    table.insert(args, table.concat(tests, ","))
  else
    local test_level = "RunLocalTests"
    if context.runner and context.runner.test_level then
      test_level = context.runner.test_level
    end
    table.insert(args, "--test-level")
    table.insert(args, test_level)
  end

  return {
    command = "sf",
    args = args,
    cwd = root,
  }
end

function list(context)
  return collect_tests(context)
end

function build_command(context)
  return build_base_args(context, "human")
end

function build_coverage_run(context)
  local spec = build_base_args(context, "json")
  table.insert(spec.args, "--code-coverage")

  local output_dir = "coverage/apex"
  if context.runner and context.runner.coverage_output_dir then
    output_dir = context.runner.coverage_output_dir
  end

  table.insert(spec.args, "--output-dir")
  table.insert(spec.args, output_dir)

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    report = output_dir,
    reporter = "json",
    output = "coverage/teez-apex-coverage.json",
  }
end

local function parse_json_test_record(record)
  if type(record) ~= "table" then
    return nil
  end

  local id = record.FullName or record.fullName
  if not id and record.ApexClass and record.MethodName then
    id = record.ApexClass.Name .. "." .. record.MethodName
  elseif not id and record.ApexClass and record.ApexClass.Name then
    id = record.ApexClass.Name
  end

  local outcome = record.Outcome or record.outcome
  if not id or not outcome then
    return nil
  end

  local event = OUTCOMES[outcome] or outcome:lower()
  if event == "pass" then
    local result = { event = "pass", id = id }
    if record.RunTime then
      result.duration_ms = record.RunTime
    end
    return result
  end

  if event == "fail" then
    local msg = record.Message or record.message or record.StackTrace or record.stackTrace
    return { event = "fail", id = id, msg = msg or outcome }
  end

  if event == "skip" then
    return { event = "skip", id = id }
  end

  return { event = "output", text = json.encode(record) }
end

local function parse_json_line(line)
  local trimmed = trim(line)
  if trimmed == "" or trimmed:sub(1, 1) ~= "{" then
    return nil
  end

  local ok, payload = pcall(json.decode, trimmed)
  if not ok or type(payload) ~= "table" then
    return nil
  end

  if type(payload.tests) == "table" then
    return nil
  end

  if payload.event then
    return payload
  end

  return parse_json_test_record(payload)
end

local function parse_human_result_line(line)
  if line:match("^=+") then
    return nil
  end

  if line:match("^TEST NAME") or line:match("^NAME%s") then
    return nil
  end

  if line:match("^%-+$") then
    return nil
  end

  local parts = {}
  for part in line:gmatch("%S+") do
    table.insert(parts, part)
  end

  if #parts < 2 then
    return nil
  end

  local outcome = parts[2]
  local event = OUTCOMES[outcome]
  if not event then
    return nil
  end

  local id = parts[1]
  local duration_ms = tonumber(parts[#parts])
  local msg = nil

  if #parts > 3 then
    local message_parts = {}
    local last_index = #parts
    if duration_ms then
      last_index = #parts - 1
    end
    for index = 3, last_index do
      table.insert(message_parts, parts[index])
    end
    msg = table.concat(message_parts, " ")
    if msg == "" then
      msg = nil
    end
  end

  if event == "pass" then
    local result = { event = "pass", id = id }
    if duration_ms then
      result.duration_ms = duration_ms
    end
    return result
  end

  if event == "fail" then
    return { event = "fail", id = id, msg = msg or outcome }
  end

  if event == "skip" then
    return { event = "skip", id = id }
  end

  return nil
end

function parse_line(line)
  local json_event = parse_json_line(line)
  if json_event then
    return json_event
  end

  local human_event = parse_human_result_line(line)
  if human_event then
    return human_event
  end

  if trim(line) == "" then
    return nil
  end

  return { event = "output", text = line }
end
