local input = ""
local running = true

local function respond(id, result)
  local body = vim.json.encode { jsonrpc = "2.0", id = id, result = result }
  io.stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  io.stdout:flush()
end

local function handle(message)
  if message.method == "initialize" then
    respond(message.id, { capabilities = { documentFormattingProvider = true } })
  elseif message.method == "initialized" then
    return
  elseif message.method == "shutdown" then
    respond(message.id, vim.NIL)
  elseif message.method == "exit" then
    running = false
  end
end

local function consume()
  while true do
    local header_end = input:find("\r\n\r\n", 1, true)
    if not header_end then return end

    local header = input:sub(1, header_end - 1)
    local content_length = header:match "[Cc]ontent%-[Ll]ength:%s*(%d+)"
    assert(content_length, "Missing Content-Length header")

    local body_start = header_end + 4
    local body_end = body_start + tonumber(content_length) - 1
    if #input < body_end then return end

    local body = input:sub(body_start, body_end)
    input = input:sub(body_end + 1)
    handle(vim.json.decode(body))
  end
end

vim.fn.stdioopen {
  on_stdin = function(_, data, _)
    input = input .. table.concat(data, "\n")
    consume()
  end,
}

vim.wait(math.huge, function() return not running end, 1)
