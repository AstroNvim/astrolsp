# Changelog

## 1.0.0 (2023-12-20)


### ⚠ BREAKING CHANGES

* separate sign configuration from diagnostics and configure diagnostic signs through new diagnostic API
* drop support for AstroNvim v3 internals
* rename `setup_handlers` to `handlers`
* move defaults to configuration through setup

### Features

* add configurable LSP features ([240f8f9](https://github.com/AstroNvim/astrolsp/commit/240f8f9679f19118e5465a8e90ce9adbf4d12453))
* add types for autocompletion with `lua_ls` ([4d960a7](https://github.com/AstroNvim/astrolsp/commit/4d960a78ea62ba9944010766a9c7ed20d2042f92))
* add which-key integration to mappings table ([9cb0e24](https://github.com/AstroNvim/astrolsp/commit/9cb0e247bed7109440804dac7cb2018cd5d70e3f))
* allow setup_handler to be `false` to indicate no setup ([972e52b](https://github.com/AstroNvim/astrolsp/commit/972e52bc675001b09dbb3fbfde9d9ec874318093))
* **config:** start building initial configuration ([8fb1129](https://github.com/AstroNvim/astrolsp/commit/8fb11297afd42ae7294738401a646bfc982e3ce8))
* continue migrating more tooling ([af72687](https://github.com/AstroNvim/astrolsp/commit/af72687fdcb0d31be051538219a8611a9468e7b1))
* **formatting:** allow full disabling of formatting ([2c36f20](https://github.com/AstroNvim/astrolsp/commit/2c36f20998c6dea41774ecf1d515d944b396b42c))
* start adding LSP tooling ([ca1a764](https://github.com/AstroNvim/astrolsp/commit/ca1a764118b5520bd9f616df0de707fc55788fa4))
* **toggles:** add silent options to toggle functions ([efcc935](https://github.com/AstroNvim/astrolsp/commit/efcc93598afec665962a19f30fc8327c0b423ea8))


### Bug Fixes

* check for config existence ([b207bd2](https://github.com/AstroNvim/astrolsp/commit/b207bd2b42fe4aed77929b748cc4c2eacbbac64d))
* **config:** add correct types to `on_attach` and `capabilities` ([afec940](https://github.com/AstroNvim/astrolsp/commit/afec940003708c15dda1b9017b9b6cf7f19a0b4e))
* **config:** fix typo in default config ([c483e32](https://github.com/AstroNvim/astrolsp/commit/c483e32aef033a278519f6e81cbd49c64a87a534))
* **config:** make `formatting` options optional ([97a48af](https://github.com/AstroNvim/astrolsp/commit/97a48afced0e1d2f3449308b732ebbc680fb758d))
* extending by the default config breaks `mason-lspconfig` ([f42f300](https://github.com/AstroNvim/astrolsp/commit/f42f3009d5e08940f4092c9d376dc0ff41f68ea8))
* fix disabling semantic_tokens ([b455099](https://github.com/AstroNvim/astrolsp/commit/b455099f728cf473375aabb59aa9f87e76c0e9b9))
* **on_attach:** clear lsp reference highlighting when leaving buffer ([1a20fb5](https://github.com/AstroNvim/astrolsp/commit/1a20fb575e4e8f315405976b481a1c2b3ec49bc6))
* separate sign configuration from diagnostics and configure diagnostic signs through new diagnostic API ([d82900f](https://github.com/AstroNvim/astrolsp/commit/d82900f1b7051a7a47b7e52a9787b53bcd041d51))
* **toggles:** add missing `silent` parameter ([4175bd9](https://github.com/AstroNvim/astrolsp/commit/4175bd98098df94d47eb241b6cabdb7daa06d801))
* **toggles:** only toggle language server semantic tokens in current buffer ([979c024](https://github.com/AstroNvim/astrolsp/commit/979c024f4219235d7e6dbb4ff20e8b9e2501b54e))
* **toggles:** resolve neovim 0.9 support with `vim.lsp.get_active_clients` ([0c8ff3b](https://github.com/AstroNvim/astrolsp/commit/0c8ff3bad07e9253679688ee49063feba8705542))
* update inlay hints API ([b8daf3d](https://github.com/AstroNvim/astrolsp/commit/b8daf3dc07c63200dabb26d8a3af1d20bb8d4648))
* vim.b.autoformat_enabled should be vim.b.autoformat ([92c2b87](https://github.com/AstroNvim/astrolsp/commit/92c2b871ec16eb8d01487498f64c695d7cf2d6c6))


### Code Refactoring

* drop support for AstroNvim v3 internals ([6a141f4](https://github.com/AstroNvim/astrolsp/commit/6a141f461d93d1b582c3cab910bd0f55d6ee7b92))
* move defaults to configuration through setup ([af7dced](https://github.com/AstroNvim/astrolsp/commit/af7dced8b1fe8b2137484d9633c33aad47f7c38d))
* rename `setup_handlers` to `handlers` ([72c537e](https://github.com/AstroNvim/astrolsp/commit/72c537e28bd4a29d6bbc9fd6dc183671c5c63424))
