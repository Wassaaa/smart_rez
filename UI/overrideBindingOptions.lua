local SmartRez = _G.SmartRez
local APP_NAME = SmartRez.appName

function SmartRez:BuildOverrideBindingOptions()
  local args = {
    general = {
      type = "group",
      name = "Override keybind settings",
      inline = true,
      order = 10,
      args = {
        enabled = {
          type = "toggle",
          name = "Enable Smart Rez override binds",
          order = 10,
          set = function(_, value)
            SmartRez:SetEnabled(value)
          end,
          get = function()
            return SmartRez:GetConfigDB().enabled
          end,
        },
        help = {
          type = "description",
          name = "These keys only take over while Smart Rez mode is enabled.",
          order = 20,
          fontSize = "medium",
        },
        capture = {
          type = "description",
          name = "Click a bind field, then press any key, mouse button, or mouse wheel. Press Escape to clear.",
          order = 30,
          fontSize = "medium",
        },
      },
    },
    tsmlabelclick = {
      type = "group",
      name = "TSM Label Click",
      inline = true,
      order = 15,
      args = {
        help = {
          type = "description",
          name = "Controls the shared cooldown for /sr tsm and /sr tsms label clicks.",
          order = 10,
          fontSize = "medium",
        },
        showmacroerrors = {
          type = "toggle",
          name = "Show macro error messages",
          desc = "Print chat errors when /sr tsm or /sr tsms can't find the needed TSM UI or button.",
          order = 15,
          set = function(_, value)
            SmartRez:SetTSMLabelClickShowMacroErrors(value)
          end,
          get = function()
            return SmartRez:GetTSMLabelClickShowMacroErrors()
          end,
        },
        cooldown = {
          type = "range",
          name = "TSM label click cooldown",
          desc = "Shared cooldown for /sr tsm and /sr tsms button clicks.",
          order = 20,
          min = 0,
          max = 1,
          step = 0.05,
          isPercent = false,
          set = function(_, value)
            SmartRez:SetTSMLabelClickCooldown(value)
          end,
          get = function()
            return SmartRez:GetTSMLabelClickCooldown()
          end,
        },
      },
    },
    utility = {
      type = "group",
      name = "Utility",
      inline = true,
      order = 20,
      args = {
        proxyuitoggle = {
          type = "toggle",
          name = "Show profession proxy tag",
          desc = "Shows the small movable rez_proxy tag while the profession proxy backend is active.",
          order = 5,
          set = function(_, value)
            if SmartRez.SetProfessionProxyFrameVisible then
              SmartRez:SetProfessionProxyFrameVisible(value)
            end
          end,
          get = function()
            if SmartRez.IsProfessionProxyFrameVisible then
              return SmartRez:IsProfessionProxyFrameVisible()
            end
            return true
          end,
        },
        proxyuireset = {
          type = "execute",
          name = "Reset Proxy Tag Position",
          order = 8,
          func = function()
            if SmartRez.ResetProfessionProxyFramePosition then
              SmartRez:ResetProfessionProxyFramePosition()
            end
          end,
        },
        debugtoggle = {
          type = "toggle",
          name = "Debug",
          desc = "Print lightweight chat debug messages for Smart Rez modules.",
          order = 9,
          width = "full",
          set = function(_, value)
            SmartRez:SetDebugEnabled(value)
          end,
          get = function()
            return SmartRez:GetDebugEnabled()
          end,
        },
        openpopup = {
          type = "execute",
          name = "Open Popup UI",
          order = 10,
          func = function()
            SmartRez:ShowOverrideBindingPopup()
          end,
        },
        openconfig = {
          type = "execute",
          name = "Open Setup",
          order = 15,
          func = function()
            SmartRez:ShowAutomationConfigWindow()
          end,
        },
        slashhint = {
          type = "description",
          name =
          "Slash commands: /sr, /sr on, /sr off, /sr toggle, /sr pop, /sr setup, /sr proxy [profession|off], /sr proxyui on|off|toggle|reset, /sr probe on|off|toggle|state, /sr tsm <label>, /sr tsms <mail|ah|prof> <label>",
          order = 25,
          fontSize = "medium",
        },
      },
    },
    lowmode = {
      type = "group",
      name = "Low Mode",
      inline = true,
      order = 21,
      args = {
        help = {
          type = "description",
          name = "Low Mode hides the UI and applies a small set of low graphics CVars. Snapshot your preferred normal settings here if they change.",
          order = 5,
          fontSize = "medium",
        },
        status = {
          type = "description",
          name = function()
            local enabled = SmartRez.IsLowModeEnabled and SmartRez:IsLowModeEnabled()
            return "Low Mode: " .. (enabled and SmartRez:Colorize("7EE787", "Enabled") or SmartRez:Colorize("FFB86C", "Disabled"))
          end,
          order = 10,
          fontSize = "medium",
        },
        snapshotstatus = {
          type = "description",
          name = function()
            return "Low Mode Snapshot: " .. SmartRez:Colorize("79C0FF", SmartRez.GetLowModeSnapshotSummary and SmartRez:GetLowModeSnapshotSummary() or "Unavailable")
          end,
          order = 15,
          fontSize = "medium",
        },
        toggle = {
          type = "execute",
          name = "Toggle Low Mode",
          order = 20,
          func = function()
            if _G.LowModeToggleBtn and _G.LowModeToggleBtn.Click then
              _G.LowModeToggleBtn:Click("LeftButton")
            end
          end,
        },
        snapshot = {
          type = "execute",
          name = "Snapshot Current Settings",
          desc = "Overwrite the saved normal-settings snapshot with your current graphics/UI settings.",
          order = 25,
          func = function()
            if SmartRez.CaptureLowModeSnapshot then
              local _, message = SmartRez:CaptureLowModeSnapshot(true)
              if message then
                print("SmartRez:", message)
              end
            end
          end,
        },
      },
    },
  }

  for index, action in ipairs(self:GetOverrideBindingActions()) do
    args.general.args[action.key] = {
      type = "keybinding",
      name = action.label,
      order = 40 + index,
      set = function(_, value)
        SmartRez:SetOverrideBindingValue(action.key, value or "")
      end,
      get = function()
        local binding = SmartRez:GetOverrideBindingValue(action.key)
        if binding == "" then
          return nil
        end
        return binding
      end,
    }
  end

  return {
    type = "group",
    name = APP_NAME,
    args = args,
  }
end
