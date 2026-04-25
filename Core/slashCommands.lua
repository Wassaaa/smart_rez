local SmartRez = _G.SmartRez

function SmartRez:ChatCommand(msg)
  local raw = self:TrimText(msg)
  local command = raw:lower()
  local tsmsRestriction, tsmsLabel = raw:match("^tsms%s+(%S+)%s+(.+)$")
  local tsmMailLabel = raw:match("^tsm%s+mail%s+(.+)$")
  local tsmLabel = raw:match("^tsm%s+(.+)$")
  local proxyArg = raw:match("^proxy%s+(.+)$")
  local proxyUiArg = raw:match("^proxyui%s*(.*)$")
  local probeArg = raw:match("^probe%s*(.*)$")

  if command == "" or command == "config" then
    self:OpenSettingsCategory()
  elseif command == "value" then
    self:ShowBagValuePopup()
  elseif command == "setup" or command == "items" then
    self:ShowAutomationConfigWindow()
  elseif command == "proxyui" or proxyUiArg then
    local proxyUiValue = self:TrimText(proxyUiArg or ""):lower()
    if proxyUiValue == "" or proxyUiValue == "toggle" then
      local visible = not (self.IsProfessionProxyFrameVisible and self:IsProfessionProxyFrameVisible())
      self:SetProfessionProxyFrameVisible(visible)
      print("Smart Rez: profession proxy tag " .. (visible and "shown." or "hidden."))
    elseif proxyUiValue == "on" or proxyUiValue == "show" then
      self:SetProfessionProxyFrameVisible(true)
      print("Smart Rez: profession proxy tag shown.")
    elseif proxyUiValue == "off" or proxyUiValue == "hide" then
      self:SetProfessionProxyFrameVisible(false)
      print("Smart Rez: profession proxy tag hidden.")
    elseif proxyUiValue == "reset" then
      if self.ResetProfessionProxyFramePosition then
        self:ResetProfessionProxyFramePosition()
      end
      print("Smart Rez: profession proxy tag position reset.")
    else
      print("Smart Rez: use /sr proxyui on|off|toggle|reset")
    end
  elseif command == "proxy" or proxyArg then
    local proxyValue = self:TrimText(proxyArg or "")
    local proxyCommand = proxyValue:lower()
    if proxyCommand == "off" or proxyCommand == "disable" or proxyCommand == "hide" then
      self:SetProfessionProxyEnabled(false)
      print("Smart Rez: profession proxy disabled.")
    else
      local professionID
      if proxyValue == "" then
        professionID = self.GetDefaultProfessionProxyProfessionID and self:GetDefaultProfessionProxyProfessionID() or nil
      else
        professionID = self.GetProfessionProxyProfessionID and self:GetProfessionProxyProfessionID(proxyValue) or nil
      end

      if professionID then
        if self:OpenProfessionProxy(professionID) then
          print("Smart Rez: opening profession proxy for " .. self:GetProfessionProxyLabel(professionID) .. ".")
        end
      else
        print("Smart Rez: no learned proxy profession found. Try /sr proxy enchanting")
      end
    end
  elseif command == "probe" or probeArg then
    local probeValue = self:TrimText(probeArg or ""):lower()
    if probeValue == "" or probeValue == "toggle" then
      self:ToggleMenuProbe()
    elseif probeValue == "on" or probeValue == "enable" then
      self:SetMenuProbeEnabled(true)
    elseif probeValue == "off" or probeValue == "disable" then
      self:SetMenuProbeEnabled(false)
    elseif probeValue == "state" or probeValue == "status" or probeValue == "once" then
      self:PrintMenuProbeState("menu probe state")
    else
      print("Smart Rez: use /sr probe on|off|toggle|state")
    end
  elseif tsmsRestriction and tsmsLabel then
    self:ClickVisibleTSMButton(tsmsLabel, tsmsRestriction)
  elseif tsmMailLabel then
    self:ClickVisibleTSMButton(tsmMailLabel, "mail")
  elseif tsmLabel then
    self:ClickVisibleTSMButton(tsmLabel)
  elseif command == "on" then
    self:SetEnabled(true)
  elseif command == "off" then
    self:SetEnabled(false)
  elseif command == "toggle" then
    self:ToggleEnabled()
  elseif command == "pop" then
    self:ToggleOverrideBindingPopup()
  else
    print(
    "Smart Rez commands: /sr, /sr value, /sr on, /sr off, /sr toggle, /sr pop, /sr setup, /sr proxy [profession|off], /sr proxyui on|off|toggle|reset, /sr probe on|off|toggle|state, /sr tsm <label>, /sr tsm mail <label>, /sr tsms <mail|ah|prof> <label>")
  end
end
