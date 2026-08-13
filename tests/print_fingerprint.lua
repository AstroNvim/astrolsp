local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
package.path = tests_dir .. "/?.lua;" .. package.path
io.stdout:write(require("test_environment").specification_hash, "\n")
