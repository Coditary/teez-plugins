local current_contract = nil

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function test_id(contract, test_name)
  if contract and contract ~= "" then
    return contract .. "::" .. test_name
  end
  return test_name
end

local function should_include_file(path, context)
  local runner = context.runner or {}
  local include = runner.include
  local exclude = runner.exclude

  if include then
    local matched = false
    for _, pattern in ipairs(include) do
      if filter.glob_match(path, pattern) then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end

  if exclude then
    for _, pattern in ipairs(exclude) do
      if filter.glob_match(path, pattern) then
        return false
      end
    end
  end

  return true
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

local function parse_list_output(output, context)
  local tests = {}
  local file = nil
  local contract = nil

  for line in output:gmatch("[^\r\n]+") do
    line = trim(line)
    if line == "" then
      goto continue
    end

    if line:match("^%[") then
      goto continue
    end

    if not line:match("^%s") then
      file = line
      contract = nil
      goto continue
    end

    local contract_name = line:match("^  (%S+)")
    if contract_name and not line:match("^    ") then
      contract = contract_name
      goto continue
    end

    local test_name = line:match("^    (%S+)")
    if test_name and contract and should_include_file(file, context) then
      table.insert(tests, test_id(contract, test_name))
    end

    ::continue::
  end

  return tests
end

local function append_runner_args(args, context)
  local runner = context.runner or {}
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
end

local function append_filter_args(args, context)
  if not context.filters then
    return
  end

  local pattern = context.filters.pattern or context.filters.name
  if pattern and pattern ~= "" then
    table.insert(args, "--match-test")
    table.insert(args, pattern)
  end
end

function list(context)
  local args = { "test", "--list" }
  append_runner_args(args, context)

  local output = sys.exec("forge", args)
  local tests = parse_list_output(output, context)
  return apply_filters(tests, context)
end

function build_command(context)
  local args = { "test", "-vvv" }
  append_filter_args(args, context)
  append_runner_args(args, context)

  return {
    command = "forge",
    args = args,
    cwd = context.target_path,
  }
end

function build_coverage_run(context)
  local args = { "coverage", "--report", "lcov" }
  append_filter_args(args, context)
  append_runner_args(args, context)

  return {
    command = "forge",
    args = args,
    cwd = context.target_path,
    report = "lcov.info",
    reporter = "lcov",
  }
end

function parse_line(line)
  local suite = line:match("^Running %d+ tests for [^:]+:(.+)$")
  if suite then
    current_contract = trim(suite)
    return { event = "output", text = line }
  end

  local fail_msg, fail_test = line:match("^%[FAIL: ([^%]]+)%] (%S+)%(")
  if fail_test then
    return {
      event = "fail",
      id = test_id(current_contract, fail_test),
      msg = fail_msg,
    }
  end

  local fail_test_plain = line:match("^%[FAIL%] (%S+)%(")
  if fail_test_plain then
    return {
      event = "fail",
      id = test_id(current_contract, fail_test_plain),
      msg = line,
    }
  end

  local pass_test = line:match("^%[PASS%] (%S+)%(")
  if pass_test then
    return {
      event = "pass",
      id = test_id(current_contract, pass_test),
    }
  end

  local skip_test = line:match("^%[SKIP%] (%S+)%(")
  if skip_test then
    return {
      event = "skip",
      id = test_id(current_contract, skip_test),
    }
  end

  if line:match("^%[") or line:match("^Suite result:") then
    return { event = "output", text = line }
  end

  return nil
end
