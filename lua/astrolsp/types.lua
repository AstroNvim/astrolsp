---@meta

---@class AstroLSPFeatureOpts
---@field autoformat boolean?
---@field codelens boolean?
---@field diagnostics_mode integer?
---@field inlay_hints boolean?
---@field lsp_handlers boolean?
---@field semantic_tokens boolean?

---@class AstroLSPFormatOnSaveOpts
---@field enabled boolean?
---@field allow_filetypes string[]?
---@field ignore_filetypes string[]?

---@class AstroLSPFormatOpts
---@field format_on_save boolean|AstroLSPFormatOnSaveOpts?
---@field disabled string[]?
---@field timeout_ms integer?
---@field filter (fun(client):boolean)?

---@class AstroLSPConfig
---@field features AstroLSPFeatureOpts?
---@field capabilities table?
---@field config lspconfig.options?
---@field diagnostics table?
---@field flags table?
---@field formatting AstroLSPFormatOpts?
---@field handlers table<string|integer,fun(server:string,opts:_.lspconfig.options)|boolean?>?
---@field mappings table<string,table<string,table|boolean>>?
---@field servers string[]?
---@field on_attach fun(client,bufnr)?
