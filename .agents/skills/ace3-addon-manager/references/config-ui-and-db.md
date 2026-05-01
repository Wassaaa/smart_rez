# Config, UI, and DB

## AceDB-3.0

- Use `AceDB-3.0`:New in `OnInitialize`.
- Match the DB name passed to `:New(...)` with the SavedVariables declaration in the `.toc`.
- Choose scopes intentionally:
  - `profile` for user-tunable settings shared by the active profile
  - `char` for per-character state
  - broader scopes only when the feature really needs them
- Use namespaces for module-owned state when modules have distinct storage needs.

## AceDBOptions-3.0

- Prefer `LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)` instead of hand-rolling profile controls.
- Mount the returned table under an options group such as `options.args.profiles`.

## AceConfig-3.0

- Register options with `RegisterOptionsTable(appName, options[, slashCommands])`.
- Keep one top-level `group` node with `args`.
- Reuse group-level `get`, `set`, `handler`, `disabled`, or `hidden` when that keeps the table readable.
- Common option types worth reaching for first: `toggle`, `range`, `input`, `select`, `execute`, `description`, `keybinding`, `color`, and nested `group`.

## AceConfigDialog-3.0 and AceConfigRegistry-3.0

- Use `AddToBlizOptions` to place the options table in Blizzard settings.
- Use `AceConfigRegistry:NotifyChange(appName)` after DB-backed changes that should refresh visible options.
- Keep `appName` stable and unique.

## AceGUI-3.0

- Use AceGUI when the UX needs dynamic windows, custom workflows, tab groups, scroll areas, or richer layouts than an options table can express.
- Set a layout on every container. The common ones are `Flow`, `List`, and `Fill`.
- Set widget widths explicitly unless `SetFullWidth` or a fill layout already makes the sizing intent obvious.
- Release transient windows on close, and release child widgets before redrawing dynamic content.
- `ScrollFrame` and `TabGroup` flows usually need an outer container set to `Fill`.

## AceTab-3.0

- Treat it as an advanced and lightly-documented option.
- The official AceTab page says the library is not yet finalized.
- Inspect current source before introducing it, and prefer ordinary slash parsing or AceConfigCmd unless tab completion is a real requirement.

## Small options template

```lua
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local options = {
  type = "group",
  name = ADDON_NAME,
  args = {
    enabled = {
      type = "toggle",
      name = "Enable",
      order = 10,
      get = function()
        return self.db.profile.enabled
      end,
      set = function(_, value)
        self.db.profile.enabled = value
        AceConfigRegistry:NotifyChange(ADDON_NAME)
      end,
    },
  },
}

AceConfig:RegisterOptionsTable(ADDON_NAME, options)
AceConfigDialog:AddToBlizOptions(ADDON_NAME, ADDON_NAME)
```

## Decision rule

- Use AceConfig for settings.
- Use AceGUI for workflows.
- Use both when the addon needs a normal settings panel and a richer task-specific window.
