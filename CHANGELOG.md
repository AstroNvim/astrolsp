# Changelog

## 1.0.0 (2024-03-05)


### ⚠ BREAKING CHANGES

* remove `diagnostics` and `signs` configuration (moved to AstroCore)
* allow `lsp_handlers` to be configured in setup with fine grained control
* **config:** make `signs` table a dictionary keyed by sign name
* move user command configuration to `opts` similar to `mappings` and `autocmds`
* move autocommand configuration to `opts` similar to `mappings`
* remove `autoformat` from `features` table and only configure through `formatting` table
* separate sign configuration from diagnostics and configure diagnostic signs through new diagnostic API
* drop support for AstroNvim v3 internals
* rename `setup_handlers` to `handlers`
* move defaults to configuration through setup

### Features

* add configurable LSP features ([240f8f9](https://github.com/AstroNvim/astrolsp/commit/240f8f9679f19118e5465a8e90ce9adbf4d12453))
* add support for dynamic capabilities ([a13b926](https://github.com/AstroNvim/astrolsp/commit/a13b926580e0b28c2275dd574137e6ba77fbd722))
* add types for autocompletion with `lua_ls` ([4d960a7](https://github.com/AstroNvim/astrolsp/commit/4d960a78ea62ba9944010766a9c7ed20d2042f92))
* add which-key integration to mappings table ([9cb0e24](https://github.com/AstroNvim/astrolsp/commit/9cb0e247bed7109440804dac7cb2018cd5d70e3f))
* align conditionals across mappings, autocmds, and user commands ([0e224f3](https://github.com/AstroNvim/astrolsp/commit/0e224f395599017400228f2265b9aac059239c64))
* allow `lsp_handlers` to be configured in setup with fine grained control ([cab7d98](https://github.com/AstroNvim/astrolsp/commit/cab7d983a33db6a1cd5722bc2d330f842cd2fe17))
* allow setup_handler to be `false` to indicate no setup ([972e52b](https://github.com/AstroNvim/astrolsp/commit/972e52bc675001b09dbb3fbfde9d9ec874318093))
* **config:** make `signs` table a dictionary keyed by sign name ([b974499](https://github.com/AstroNvim/astrolsp/commit/b974499ffd7d6d94e4850b3432cd20025d45a8e1))
* **config:** start building initial configuration ([8fb1129](https://github.com/AstroNvim/astrolsp/commit/8fb11297afd42ae7294738401a646bfc982e3ce8))
* continue migrating more tooling ([af72687](https://github.com/AstroNvim/astrolsp/commit/af72687fdcb0d31be051538219a8611a9468e7b1))
* **formatting:** allow full disabling of formatting ([2c36f20](https://github.com/AstroNvim/astrolsp/commit/2c36f20998c6dea41774ecf1d515d944b396b42c))
* move autocommand configuration to `opts` similar to `mappings` ([5b0e9bd](https://github.com/AstroNvim/astrolsp/commit/5b0e9bd339e456f2288933b35d40dc414c167972))
* move user command configuration to `opts` similar to `mappings` and `autocmds` ([9180ffa](https://github.com/AstroNvim/astrolsp/commit/9180ffa30324f0347b25aebafba7338bf3be8042))
* only refresh codelens for buffer ([7fbb0a4](https://github.com/AstroNvim/astrolsp/commit/7fbb0a4e108135dd4f2a6e1cd0bcb117ab15d4d4))
* start adding LSP tooling ([ca1a764](https://github.com/AstroNvim/astrolsp/commit/ca1a764118b5520bd9f616df0de707fc55788fa4))
* **toggles:** add silent options to toggle functions ([efcc935](https://github.com/AstroNvim/astrolsp/commit/efcc93598afec665962a19f30fc8327c0b423ea8))


### Bug Fixes

* add support for partial LSP clients in neovim &lt;0.10 ([2c010a9](https://github.com/AstroNvim/astrolsp/commit/2c010a92114098d4e02f2a369c1f951c0c6d6191))
* check for config existence ([b207bd2](https://github.com/AstroNvim/astrolsp/commit/b207bd2b42fe4aed77929b748cc4c2eacbbac64d))
* **config:** add correct types to `on_attach` and `capabilities` ([afec940](https://github.com/AstroNvim/astrolsp/commit/afec940003708c15dda1b9017b9b6cf7f19a0b4e))
* **config:** fix incorrect type of `lsp_handlers` functions ([5ef4d0f](https://github.com/AstroNvim/astrolsp/commit/5ef4d0fecf781ed79cf92ab48bca1da01282a824))
* **config:** fix typo in default config ([c483e32](https://github.com/AstroNvim/astrolsp/commit/c483e32aef033a278519f6e81cbd49c64a87a534))
* **config:** make `formatting` options optional ([97a48af](https://github.com/AstroNvim/astrolsp/commit/97a48afced0e1d2f3449308b732ebbc680fb758d))
* extending by the default config breaks `mason-lspconfig` ([f42f300](https://github.com/AstroNvim/astrolsp/commit/f42f3009d5e08940f4092c9d376dc0ff41f68ea8))
* fix disabling semantic_tokens ([b455099](https://github.com/AstroNvim/astrolsp/commit/b455099f728cf473375aabb59aa9f87e76c0e9b9))
* **on_attach:** clear lsp reference highlighting when leaving buffer ([1a20fb5](https://github.com/AstroNvim/astrolsp/commit/1a20fb575e4e8f315405976b481a1c2b3ec49bc6))
* remove hard dependency on `nvim-lspconfig` ([5b21eb1](https://github.com/AstroNvim/astrolsp/commit/5b21eb1a7ad953482ee26c2918245013e03a6e61))
* separate sign configuration from diagnostics and configure diagnostic signs through new diagnostic API ([d82900f](https://github.com/AstroNvim/astrolsp/commit/d82900f1b7051a7a47b7e52a9787b53bcd041d51))
* **toggles:** add missing `silent` parameter ([4175bd9](https://github.com/AstroNvim/astrolsp/commit/4175bd98098df94d47eb241b6cabdb7daa06d801))
* **toggles:** only toggle language server semantic tokens in current buffer ([979c024](https://github.com/AstroNvim/astrolsp/commit/979c024f4219235d7e6dbb4ff20e8b9e2501b54e))
* **toggles:** resolve neovim 0.9 support with `vim.lsp.get_active_clients` ([0c8ff3b](https://github.com/AstroNvim/astrolsp/commit/0c8ff3bad07e9253679688ee49063feba8705542))
* update inlay hints API ([b8daf3d](https://github.com/AstroNvim/astrolsp/commit/b8daf3dc07c63200dabb26d8a3af1d20bb8d4648))
* vim.b.autoformat_enabled should be vim.b.autoformat ([92c2b87](https://github.com/AstroNvim/astrolsp/commit/92c2b871ec16eb8d01487498f64c695d7cf2d6c6))


### Performance Improvements

* improve autocmd performance for self deletion ([764d652](https://github.com/AstroNvim/astrolsp/commit/764d652a8172a729c7102584b8062c4d7ec843da))
* improve performance of clearing progress messages and dynamic registration ([1a00f1f](https://github.com/AstroNvim/astrolsp/commit/1a00f1f39cacc67d10144f6d6046533180e5a1f2))
* optimize `on_attach` conditional checks ([3e75599](https://github.com/AstroNvim/astrolsp/commit/3e7559973dce6a95e44e4425904fb432743c0f97))
* remove `deepcopy` in `on_attach` function ([2b594b0](https://github.com/AstroNvim/astrolsp/commit/2b594b0ed2637648370a69d1614a22e9a97ddd60))


### Code Refactoring

* drop support for AstroNvim v3 internals ([6a141f4](https://github.com/AstroNvim/astrolsp/commit/6a141f461d93d1b582c3cab910bd0f55d6ee7b92))
* move defaults to configuration through setup ([af7dced](https://github.com/AstroNvim/astrolsp/commit/af7dced8b1fe8b2137484d9633c33aad47f7c38d))
* remove `autoformat` from `features` table and only configure through `formatting` table ([2781aff](https://github.com/AstroNvim/astrolsp/commit/2781afff8216ad1a0acb98215d2f23915227556d))
* remove `diagnostics` and `signs` configuration (moved to AstroCore) ([0206a70](https://github.com/AstroNvim/astrolsp/commit/0206a70337b0af689b8b6b2db8d88ea844da6f32))
* rename `setup_handlers` to `handlers` ([72c537e](https://github.com/AstroNvim/astrolsp/commit/72c537e28bd4a29d6bbc9fd6dc183671c5c63424))
