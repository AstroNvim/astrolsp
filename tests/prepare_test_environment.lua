#!/usr/bin/env -S nvim -l

local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

package.path = tests_dir .. "/?.lua;" .. package.path
require("test_environment").enable_ci_recovery()
dofile(tests_dir .. "/bootstrap.lua")
