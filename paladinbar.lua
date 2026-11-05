-- pfUI-PaladinBar
-- A pfUI third-party module for paladins (modelled on pfUI-TotemBar):
--   * one button each for Aura, Libram, Seal and Judgement
--   * hover a button to open the list of everything known for it
--       left-click  -> cast / equip it
--       right-click -> make it the active one
--   * Judgement button: shows the Judgement icon and, in its top right corner,
--     the seal that will be used. Hover it to pick that seal in the seal list.

-- global API (usable from macros, /run and key bindings)
pfPaladinBar = pfPaladinBar or {}

BINDING_HEADER_PFPALADINBAR = "pfUI Paladin Bar"
BINDING_NAME_PFPALADINBAR_AURA = "Cast active aura"
BINDING_NAME_PFPALADINBAR_SEAL = "Cast active seal"
BINDING_NAME_PFPALADINBAR_JUDGEMENT = "Judgement (with chosen seal)"
BINDING_NAME_PFPALADINBAR_LIBRAM = "Equip active libram"

pfUI:RegisterModule("paladinbar", "vanilla", function()
  local _, class = UnitClass("player")

  -- [[ default configuration ]] --
  local defaults = {
    enable      = "1",
    aura        = "",                                  -- active aura (spell name)
    libram      = "",                                  -- active libram (item name)
    seal        = "",                                  -- active seal (spell name)
    judgeseal   = "",                                  -- seal used by the Judgement button (spell name)
    judgefirst  = "1",                                 -- Judgement button casts the chosen seal first if it is not up
    judgecheck  = "1",                                 -- skip Judgement when its debuff is already on the target
    order       = "aura,libram,seal,judgement",        -- bar order
    enable_libram = "1",
    hidestances = "1",                                 -- hide pfUI's stance bar (it lists the paladin auras)
    reverse     = "0",
    size        = "30",
    spacing     = "2",
    direction   = "HORIZONTAL",
    flyout      = "TOP",
    hover       = "1",
    timer       = "1",
    showbg      = "1",
  }
  for key, value in pairs(defaults) do
    pfUI:UpdateConfig("paladinbar", nil, key, value)
  end

  if class ~= "PALADIN" then
    _G.pfPaladinBar.Cast = function() end
    _G.pfPaladinBar.Judge = function() end
    _G.pfPaladinBar.CastAura = function() end
    _G.pfPaladinBar.CastSeal = function() end
    _G.pfPaladinBar.EquipLibram = function() end
    return
  end

  local cfg = C.paladinbar
  local PREFIX = "|cff33ffccpf|rPaladinBar: "

  local GROUPS = { "aura", "libram", "seal", "judgement" }
  local VALID = { aura = true, libram = true, seal = true, judgement = true }
  local RELIC_SLOT = 18   -- ranged slot, used as relic / libram slot

  local function Enabled(el)
    if el == "libram" then return cfg.enable_libram == "1" end
    return true
  end

  local LABEL = { aura = T["Aura"], libram = T["Libram"], seal = T["Seal"], judgement = T["Judgement"] }
  local COLOR = {
    aura      = { .95, .8, .3 },
    libram    = { .6, .4, .2 },
    seal      = { 1, .55, .15 },
    judgement = { .4, .7, 1 },
  }

  -- spell icons (locale independent) --
  local AURA_TEXTURES = {
    ["spell_holy_devotionaura"] = true,      -- Devotion Aura
    ["spell_holy_auraoflight"] = true,       -- Retribution Aura
    ["spell_holy_mindsooth"] = true,         -- Concentration Aura
    ["spell_shadow_sealofkings"] = true,     -- Shadow Resistance Aura
    ["spell_frost_wizardmark"] = true,       -- Frost Resistance Aura
    ["spell_fire_sealoffire"] = true,        -- Fire Resistance Aura
    ["spell_holy_mindvision"] = true,        -- Sanctity Aura
    ["spell_holy_crusaderaura"] = true,      -- Crusader Aura
  }
  local SEAL_TEXTURES = {
    ["ability_thunderbolt"] = true,          -- Seal of Righteousness
    ["spell_holy_holysmite"] = true,         -- Seal of the Crusader
    ["ability_warrior_innerrage"] = true,    -- Seal of Command
    ["spell_holy_healingaura"] = true,       -- Seal of Light
    ["spell_holy_righteousnessaura"] = true, -- Seal of Wisdom
    ["spell_holy_sealofwrath"] = true,       -- Seal of Justice
  }
  local JUDGEMENT_TEXTURES = {
    ["spell_holy_righteousfury"] = true,     -- Judgement
  }
  local JUDGEMENT_NAMES = {
    ["judgement"] = true, ["judgment"] = true,
    ["jugement"] = true, ["richturteil"] = true,
  }

  -- "none" choice: nothing is cast / no seal is forced
  local NONE = "none"
  local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- red cross
  local NONE_TEXT = "|T" .. NONE_ICON .. "|t |cffff5555" .. T["None"] .. "|r"   -- no ":" (dropdown splits on it)

  local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  end

  -- [[ spellbook scan ]] --
  local known = { aura = {}, libram = {}, seal = {}, judgement = {} }
  local byname = {}

  local function ShortTexture(tex)
    if not tex then return "" end
    local _, _, short = string.find(tex, "([^\\]+)$")
    return string.lower(short or tex)
  end

  local function Classify(short, lname)
    if JUDGEMENT_TEXTURES[short] or JUDGEMENT_NAMES[lname] then return "judgement" end
    if AURA_TEXTURES[short] or string.find(lname, " aura$") or string.find(lname, "^aura d") then return "aura" end
    if SEAL_TEXTURES[short] or string.find(lname, "^seal of") or string.find(lname, "^sceau")
      or string.find(lname, "^siegel") then return "seal" end
    return nil
  end

  -- [[ librams (relic slot) ]] --
  local relicCache = {}

  local function ItemIdFromLink(link)
    local _, _, id = string.find(link or "", "item:(%d+)")
    return tonumber(id)
  end

  local function ItemNameFromLink(link)
    local _, _, name = string.find(link or "", "%[(.+)%]")
    return name
  end

  -- a paladin libram: Nampower item data first (relic slot, armor subclass libram),
  -- GetItemInfo's equip slot + subtype / name otherwise
  local function IsLibram(id, name)
    if relicCache[id] ~= nil then return relicCache[id] end
    local result
    if GetItemStatsField then
      local ok, inv = pcall(GetItemStatsField, id, "inventoryType")
      if ok and inv then
        local okSub, sub = pcall(GetItemStatsField, id, "subclass")
        if inv ~= 28 then
          result = false
        elseif okSub and sub ~= nil then
          result = (sub == 7)   -- relic, armor subclass libram
        end
      end
    end
    if result == nil then
      local info = { GetItemInfo(id) }
      if not info[1] then return false end   -- not cached yet, retry later
      local isRelic, isLibram = false, false
      for k = 1, 12 do
        if info[k] == "INVTYPE_RELIC" then isRelic = true end
        if type(info[k]) == "string" and string.find(string.lower(info[k]), "libram", 1, true) then isLibram = true end
      end
      if name and string.find(string.lower(name), "^libram") then isLibram = true end
      result = isRelic and isLibram
    end
    relicCache[id] = result
    return result
  end

  local function ScanLibrams()
    for _, entry in pairs(known.libram) do
      if byname[entry.name] == entry then byname[entry.name] = nil end
    end
    known.libram = {}

    local function add(link, icon, bag, slot)
      local id = ItemIdFromLink(link)
      local name = ItemNameFromLink(link)
      if not id or not name or byname[name] or not IsLibram(id, name) then return end
      local entry = { name = name, element = "libram", itemId = id, icon = icon, bag = bag, slot = slot, equipped = not bag }
      byname[name] = entry
      table.insert(known.libram, entry)
    end

    -- equipped one first
    add(GetInventoryItemLink("player", RELIC_SLOT), GetInventoryItemTexture("player", RELIC_SLOT))
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) or 0 do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local icon = GetContainerItemInfo(bag, slot)
          add(link, icon, bag, slot)
        end
      end
    end
  end

  local function EquippedRelicId()
    return ItemIdFromLink(GetInventoryItemLink("player", RELIC_SLOT))
  end

  local function EquipLibram(entry)
    if not entry or EquippedRelicId() == entry.itemId then return end
    if CursorHasItem and CursorHasItem() then return end
    -- the item may have moved since the last scan
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) or 0 do
        if ItemIdFromLink(GetContainerItemLink(bag, slot)) == entry.itemId then
          PickupContainerItem(bag, slot)
          EquipCursorItem(RELIC_SLOT)
          if CursorHasItem and CursorHasItem() then ClearCursor() end   -- refused (e.g. combat)
          return
        end
      end
    end
  end

  local function Scan()
    for _, el in pairs(GROUPS) do known[el] = {} end
    byname = {}

    -- spellbook indexes in Mounts / Companions / Toys tabs
    local collection = {}
    if GetNumSpellTabs and GetSpellTabInfo then
      for tab = 1, GetNumSpellTabs() or 0 do
        local tabname, _, offset, count = GetSpellTabInfo(tab)
        local lname = string.lower(tabname or "")
        if offset and count and (string.find(lname, "mount") or string.find(lname, "companion")
          or string.find(lname, "toy") or string.find(lname, "monture") or string.find(lname, "compagnon")
          or string.find(lname, "jouet") or string.find(lname, "reittier") or string.find(lname, "haustier")
          or string.find(lname, "spielzeug")) then
          for idx = offset + 1, offset + count do collection[idx] = true end
        end
      end
    end

    local i = 1
    while true do
      local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
      if not name then break end

      if not collection[i] then
        local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
        local el = Classify(ShortTexture(tex), string.lower(name))
        if el then
          local entry = byname[name]
          if not entry then
            entry = { name = name, element = el }
            byname[name] = entry
            table.insert(known[el], entry)
          end
          -- spellbook lists ranks in ascending order: the last one wins
          entry.index, entry.rank, entry.icon = i, rank, tex
          entry.licon = tex and string.lower(tex)
        end
      end

      i = i + 1
    end

    ScanLibrams()

    -- pick a sensible default the first time
    for _, el in pairs({ "aura", "libram", "seal" }) do
      if (cfg[el] == nil or cfg[el] == "") and known[el][1] then
        cfg[el] = known[el][1].name
      end
    end
    if (cfg.judgeseal == nil or cfg.judgeseal == "") and known.seal[1] then
      cfg.judgeseal = (byname[cfg.seal] and cfg.seal) or known.seal[1].name
    end
  end

  local function GetActive(el)
    local list = known[el]
    if not list or not list[1] then return nil end
    if el == "judgement" then return list[1] end
    local want = cfg[el]
    if want == NONE then return nil end
    if want and byname[want] and byname[want].element == el then
      return byname[want]
    end
    -- a libram we no longer carry: don't swap to some other item
    if el == "libram" and want and want ~= "" then return nil end
    return list[1]
  end

  -- the seal the Judgement button works with (nil = just judge whatever is up)
  local function GetJudgeSeal()
    local want = cfg.judgeseal
    if want == NONE then return nil end
    if want and want ~= "" and byname[want] and byname[want].element == "seal" then
      return byname[want]
    end
    return GetActive("seal")
  end

  local function SpellString(entry)
    if entry.rank and entry.rank ~= "" then
      return entry.name .. "(" .. entry.rank .. ")"
    end
    return entry.name
  end

  -- [[ buffs on the player ]] --
  -- icon (lowercase) -> seconds left (0 = no duration), rebuilt at most every 0.1s
  local buffcache = { t = -10, map = {} }
  local function Buffs(now, fresh)
    now = now or GetTime()
    if not fresh and now >= buffcache.t and now - buffcache.t < .1 then return buffcache.map end
    local map = {}
    for i = 0, 31 do
      local idx = GetPlayerBuff(i, "HELPFUL")
      if not idx or idx < 0 then break end
      local tex = GetPlayerBuffTexture(idx)
      if tex then map[string.lower(tex)] = GetPlayerBuffTimeLeft(idx) or 0 end
    end
    buffcache.t, buffcache.map = now, map
    return map
  end

  local function IsUp(entry, fresh)
    return entry and entry.licon and Buffs(nil, fresh)[entry.licon] ~= nil
  end

  -- [[ casting ]] --
  local function Cast(entry)
    if not entry then return end
    if entry.element == "libram" then
      EquipLibram(entry)
    else
      CastSpellByName(SpellString(entry))
    end
  end

  -- Judgement: with "cast chosen seal first" the click casts the chosen seal when it
  -- is not up on you, otherwise (or when the option is off) the Judgement itself.
  -- seals whose judgement leaves no debuff on the target (never checked)
  local NODEBUFF_TEXTURES = {
    ["ability_thunderbolt"] = true,          -- Righteousness (damage only)
    ["ability_warrior_innerrage"] = true,    -- Command (damage only)
  }

  local function TargetHasDebuff(entry)
    if not entry or not entry.licon or not UnitExists("target") then return nil end
    for i = 1, 40 do
      local tex = UnitDebuff("target", i)
      if not tex then break end
      if string.lower(tex) == entry.licon then return true end
    end
    return nil
  end

  -- true when Judgement would be wasted: the chosen seal's judgement debuff is
  -- already on the target (only checked when that seal is, or will be, the one used)
  local function JudgementApplied(seal, fresh)
    if cfg.judgecheck ~= "1" or not seal or NODEBUFF_TEXTURES[ShortTexture(seal.icon)] then return nil end
    if cfg.judgefirst ~= "1" and not IsUp(seal, fresh) then return nil end
    return TargetHasDebuff(seal)
  end

  -- real cooldown only: 1.5s or less is the global cooldown
  local function OnCooldown(entry)
    local start, duration = GetSpellCooldown(entry.index, BOOKTYPE_SPELL)
    return start and start > 0 and duration and duration > 1.5
  end

  -- returns true when it cast something (the chosen seal or the Judgement),
  -- false + a reason when it did nothing:
  --   "unavailable" (no Judgement / feature off), "cooldown", "applied"
  local function Judge()
    local judgement = GetActive("judgement")
    if not judgement then return false, "unavailable" end
    if OnCooldown(judgement) then return false, "cooldown" end
    local seal = GetJudgeSeal()
    if JudgementApplied(seal, true) then return false, "applied" end   -- debuff already on the target
    if cfg.judgefirst == "1" and seal and not IsUp(seal, true) then
      Cast(seal)
    else
      Cast(judgement)
    end
    return true
  end

  local function ParseOrder()
    local order, seen = {}, {}
    for el in string.gfind(string.lower(cfg.order or ""), "%a+") do
      if VALID[el] and not seen[el] then
        table.insert(order, el)
        seen[el] = true
      end
    end
    for _, el in pairs(GROUPS) do
      if not seen[el] then table.insert(order, el) end
    end
    return order
  end

  -- [[ the bar ]] --
  local bar = CreateFrame("Frame", "pfPaladinBar", UIParent)
  bar.buttons = {}

  local function DefaultBorder(button)
    button:SetBackdropBorderColor(GetStringColor(pfUI_config.appearance.border.color))
  end

  local function ShowNoneTooltip(button, el, main)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["None"], 1, .33, .33)
    if el == "judgement" then
      GameTooltip:AddLine(main and "No seal is forced: Judgement judges whatever seal is up."
        or "Judge whatever seal is up, never cast a seal first.", 1, 1, 1)
    else
      GameTooltip:AddLine(main and ("No " .. LABEL[el] .. " is selected. Pick one in the list.")
        or ("Right-click: select no " .. LABEL[el]), 1, 1, 1)
    end
    GameTooltip:Show()
  end

  -- button = the button hovered, entry = what it shows, main = it is a bar button,
  -- judge = it is a seal in the Judgement list
  local function ShowTooltip(button, entry, main, judge)
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local verb = "Cast"
    if entry.element == "libram" then
      verb = "Equip"
      if entry.equipped then GameTooltip:SetInventoryItem("player", RELIC_SLOT)
      else GameTooltip:SetBagItem(entry.bag, entry.slot) end
    else
      GameTooltip:SetSpell(entry.index, BOOKTYPE_SPELL)
    end
    GameTooltip:AddLine(" ")
    if judge then
      GameTooltip:AddDoubleLine("Click", "Use this seal for Judgement", 1, 1, 1, .2, 1, .8)
    elseif entry.element == "judgement" then
      local seal = GetJudgeSeal()
      GameTooltip:AddDoubleLine("Left-click", (cfg.judgefirst == "1" and seal)
        and ("Seal first (" .. seal.name .. "), then Judgement") or "Judgement", 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Hover", "Choose the seal", 1, 1, 1, .2, 1, .8)
    elseif main then
      GameTooltip:AddDoubleLine("Left-click", verb .. " " .. entry.name, 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Pin the " .. LABEL[entry.element] .. " list", 1, 1, 1, .2, 1, .8)
    else
      GameTooltip:AddDoubleLine("Left-click", verb, 1, 1, 1, .2, 1, .8)
      GameTooltip:AddDoubleLine("Right-click", "Set as active " .. LABEL[entry.element], 1, 1, 1, .2, 1, .8)
    end
    GameTooltip:Show()
  end

  local function CreateBarButton(name, parent)
    local b = CreateFrame("Button", name, parent)
    b:SetWidth(30)
    b:SetHeight(30)
    CreateBackdrop(b, nil, true)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(.08, .92, .08, .92)
    SetAllPointsOffset(b.icon, b, 2)

    b.hl = b:CreateTexture(nil, "OVERLAY")
    b.hl:SetAllPoints(b.icon)
    b.hl:SetTexture(1, 1, 1, .2)
    b.hl:Hide()

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
  end

  local function SetActive(el, name)
    if el == "judgement" then
      if name ~= NONE and (not byname[name] or byname[name].element ~= "seal") then return end
      cfg.judgeseal = name
    else
      if name ~= NONE and (not byname[name] or byname[name].element ~= el) then return end
      cfg[el] = name
    end
    bar:Refresh()
  end

  -- flyout buttons
  local function FlyOnClick()
    local el = this.el
    if this.none then
      if el == "judgement" or arg1 == "RightButton" then
        SetActive(el, NONE)
        ShowNoneTooltip(this, el)
      end
      return
    end
    if not this.entry then return end
    if el == "judgement" then
      -- the list holds seals: any click picks the seal for Judgement
      SetActive(el, this.entry.name)
      ShowTooltip(this, this.entry, nil, true)
    elseif arg1 == "RightButton" then
      SetActive(el, this.entry.name)
      ShowTooltip(this, this.entry)
    else
      Cast(this.entry)
    end
  end

  local function FlyOnEnter()
    this.hl:Show()
    if this.none then ShowNoneTooltip(this, this.el)
    else ShowTooltip(this, this.entry, nil, this.el == "judgement") end
  end

  local function FlyOnLeave()
    this.hl:Hide()
    GameTooltip:Hide()
  end

  local function FlyoutOnUpdate()
    if this.pinned then return end
    if MouseIsOver(this) or MouseIsOver(this.owner) then
      this.leave = nil
    else
      this.leave = this.leave or GetTime()
      if GetTime() - this.leave > .3 then this:Hide() end
    end
  end

  -- bar buttons
  local function MainOnClick()
    if arg1 == "RightButton" then
      local fly = this.fly
      if fly:IsShown() and fly.pinned then
        fly.pinned = nil
        fly:Hide()
      else
        fly.pinned = true
        fly.leave = nil
        fly:Show()
      end
    elseif this.element == "judgement" then
      Judge()
    else
      Cast(GetActive(this.element))
    end
  end

  local function MainOnEnter()
    this.hl:Show()
    if cfg.hover == "1" then
      this.fly.leave = nil
      this.fly:Show()
    end
    local entry = GetActive(this.element)
    if entry then ShowTooltip(this, entry, true) else ShowNoneTooltip(this, this.element, true) end
  end

  local function MainOnLeave()
    this.hl:Hide()
    GameTooltip:Hide()
  end

  for _, el in pairs(GROUPS) do
    local b = CreateBarButton("pfPaladinBar" .. el, bar)
    b.element = el

    b.cdbg = CreateFrame("Frame", nil, b)
    b.cdbg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.cd = CreateFrame(COOLDOWN_FRAME_TYPE or "Model", "pfPaladinBar" .. el .. "Cooldown", b.cdbg, "CooldownFrameTemplate")
    b.cd.pfCooldownType = "ALL"

    b.textframe = CreateFrame("Frame", nil, b)
    b.textframe:SetAllPoints(b)
    b.textframe:SetFrameLevel(b:GetFrameLevel() + 4)
    b.timer = b.textframe:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    b.timer:SetPoint("BOTTOM", b, "BOTTOM", 0, 3)

    if el == "judgement" then
      -- small corner icon (top right): the seal Judgement works with
      b.secframe = CreateFrame("Frame", nil, b.textframe)
      b.secframe:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
      b.secframe:SetWidth(12)
      b.secframe:SetHeight(12)
      CreateBackdrop(b.secframe, nil, true)
      b.secframe.icon = b.secframe:CreateTexture(nil, "OVERLAY")
      b.secframe.icon:SetTexCoord(.08, .92, .08, .92)
      SetAllPointsOffset(b.secframe.icon, b.secframe, 1)
      b.secframe:Hide()
    end

    b:SetScript("OnClick", MainOnClick)
    b:SetScript("OnEnter", MainOnEnter)
    b:SetScript("OnLeave", MainOnLeave)

    b.fly = CreateFrame("Frame", nil, b)
    b.fly.owner = b
    b.fly.buttons = {}
    b.fly:SetFrameStrata("DIALOG")
    b.fly:SetScript("OnUpdate", FlyoutOnUpdate)
    b.fly:Hide()

    bar.buttons[el] = b
  end

  function bar:BuildFlyout(el)
    local b = self.buttons[el]
    local fly = b.fly
    -- the Judgement list is the list of seals; the chosen one is outlined
    local chosen
    local source
    if el == "judgement" then
      source = known.seal
      chosen = GetJudgeSeal()
    else
      source = known[el]
      chosen = GetActive(el)
    end
    local list = {}
    for _, entry in pairs(source) do table.insert(list, entry) end
    table.insert(list, NONE)
    local size, spacing, dir = self.size, self.spacing, cfg.flyout
    local count = table.getn(list)
    local step = size + spacing

    for i = 1, count do
      local f = fly.buttons[i]
      if not f then
        f = CreateBarButton(nil, fly)
        f:SetScript("OnClick", FlyOnClick)
        f:SetScript("OnEnter", FlyOnEnter)
        f:SetScript("OnLeave", FlyOnLeave)
        fly.buttons[i] = f
      end

      local isNone = list[i] == NONE
      f.el = el
      f.entry = (not isNone) and list[i] or nil
      f.none = isNone and el or nil
      f:SetWidth(size)
      f:SetHeight(size)
      f:ClearAllPoints()
      if dir == "BOTTOM" then
        f:SetPoint("TOP", fly, "TOP", 0, -(i - 1) * step)
      elseif dir == "LEFT" then
        f:SetPoint("RIGHT", fly, "RIGHT", -(i - 1) * step, 0)
      elseif dir == "RIGHT" then
        f:SetPoint("LEFT", fly, "LEFT", (i - 1) * step, 0)
      else
        f:SetPoint("BOTTOM", fly, "BOTTOM", 0, (i - 1) * step)
      end

      f.icon:SetTexture(isNone and NONE_ICON or list[i].icon)
      if (isNone and not chosen) or (not isNone and list[i] == chosen) then
        f:SetBackdropBorderColor(COLOR[el][1], COLOR[el][2], COLOR[el][3], 1)
      else
        DefaultBorder(f)
      end
      f:Show()
    end

    for i = count + 1, table.getn(fly.buttons) do
      fly.buttons[i]:Hide()
    end

    local length = math.max(count * size + (count - 1) * spacing, 1)
    fly:ClearAllPoints()
    if dir == "BOTTOM" then
      fly:SetPoint("TOP", b, "BOTTOM", 0, -spacing)
      fly:SetWidth(size) fly:SetHeight(length)
    elseif dir == "LEFT" then
      fly:SetPoint("RIGHT", b, "LEFT", -spacing, 0)
      fly:SetWidth(length) fly:SetHeight(size)
    elseif dir == "RIGHT" then
      fly:SetPoint("LEFT", b, "RIGHT", spacing, 0)
      fly:SetWidth(length) fly:SetHeight(size)
    else
      fly:SetPoint("BOTTOM", b, "TOP", 0, spacing)
      fly:SetWidth(size) fly:SetHeight(length)
    end
  end

  function bar:Refresh()
    for _, el in pairs(GROUPS) do
      local b = self.buttons[el]
      local entry = GetActive(el)
      if known[el][1] then
        b.cdstart, b.cdduration = nil, nil
        b.tcolor, b.secshowing = 0, nil   -- force the next tick to redraw timer and corner icon
        if entry then
          b.icon:SetTexture(entry.icon)
          b.showing = entry
          -- the border is owned by the OnUpdate tick (lit / default), not set here:
          -- setting it here made it flash on every refresh
        else
          b.icon:SetTexture(NONE_ICON)
          b.icon:SetVertexColor(1, 1, 1)
          b.timer:SetText("")
          CooldownFrame_SetTimer(b.cd, 0, 0, 0)
          DefaultBorder(b)
        end
        self:BuildFlyout(el)
      end
    end
  end

  -- hide pfUI's own stance bar (pfActionBarStances, where paladin auras show up)
  -- while this bar is enabled
  local function SuppressStances()
    local stances = _G.pfActionBarStances
    if not stances then return end
    local hide = cfg.enable == "1" and cfg.hidestances == "1"

    if not stances.pfPaladinBarHooked then
      stances.pfPaladinBarHooked = true
      local origShow = stances.Show
      stances.origShow = origShow
      stances.Show = function(self)
        if cfg.enable == "1" and cfg.hidestances == "1" then return self:Hide() end
        return origShow(self)
      end
    end

    if hide then
      stances:Hide()
    elseif C.bars and C.bars.bar11 and C.bars.bar11.enable == "1" and GetNumShapeshiftForms() > 0 then
      stances:Show()
    end
  end

  function bar:UpdateConfig()
    SuppressStances()

    if cfg.enable ~= "1" then
      self:Hide()
      return
    end

    local size = tonumber(cfg.size) or 30
    local spacing = tonumber(cfg.spacing) or 2
    local horizontal = cfg.direction ~= "VERTICAL"
    self.size, self.spacing = size, spacing

    local shown, prev = 0, nil
    local order = ParseOrder()
    if cfg.reverse == "1" then
      local reversed = {}
      for i = table.getn(order), 1, -1 do table.insert(reversed, order[i]) end
      order = reversed
    end
    for _, el in ipairs(order) do
      local b = self.buttons[el]
      if known[el][1] and Enabled(el) then
        shown = shown + 1
        b:SetWidth(size)
        b:SetHeight(size)
        b.cdbg:SetWidth(size - 3)
        b.cdbg:SetHeight(size - 3)
        if b.secframe then
          local corner = math.floor(size * .42 + .5)
          b.secframe:SetWidth(corner)
          b.secframe:SetHeight(corner)
        end
        b:ClearAllPoints()
        if not prev then
          b:SetPoint("TOPLEFT", self, "TOPLEFT", spacing, -spacing)
        elseif horizontal then
          b:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        else
          b:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        end
        b:Show()
        prev = b
      else
        b.fly:Hide()
        b:Hide()
      end
    end

    if shown == 0 then
      self:Hide()
      return
    end

    local long = spacing + shown * (size + spacing)
    local short = size + spacing * 2
    self:SetWidth(horizontal and long or short)
    self:SetHeight(horizontal and short or long)

    if cfg.showbg == "1" then
      CreateBackdrop(self)
      self.backdrop:Show()
    elseif self.backdrop then
      self.backdrop:Hide()
    end

    self:Show()
    self:Refresh()
  end

  -- timer text: only rebuilt (and set) when what it shows changes
  local function FormatTime(remain)
    if remain >= 60 then return math.ceil(remain / 60) .. "m" end
    return math.floor(remain + .5)
  end

  local function SetTimerText(b, color, value)
    if b.tcolor ~= color or b.tvalue ~= value then
      b.tcolor, b.tvalue = color, value
      b.timer:SetText(color and (color .. value .. "|r") or "")
    end
  end

  local function SetIconTint(b, entry, bright)
    local v = bright and 1 or .55
    if IsSpellUsable and entry.name then
      local usable, oom = IsSpellUsable(entry.name)
      if usable == 0 and oom == 1 then
        b.icon:SetVertexColor(.4 * v, .5 * v, 1 * v)
        return
      end
    end
    b.icon:SetVertexColor(v, v, v)
  end

  bar:SetScript("OnUpdate", function()
    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + .1

    local buffs = Buffs(now)
    for _, el in pairs(GROUPS) do
      local b = this.buttons[el]
      local entry = b:IsShown() and GetActive(el)
      if entry and el == "libram" then
        -- glow the border while the selected libram is equipped
        if entry.itemId == EquippedRelicId() then
          b:SetBackdropBorderColor(COLOR.libram[1], COLOR.libram[2], COLOR.libram[3], 1)
          b.icon:SetVertexColor(1, 1, 1)
        else
          DefaultBorder(b)
          b.icon:SetVertexColor(.6, .6, .6)
        end
        SetTimerText(b, nil, nil)
      elseif entry then
        -- cooldown wheel
        local start, duration, enable = GetSpellCooldown(entry.index, BOOKTYPE_SPELL)
        if start ~= b.cdstart or duration ~= b.cdduration then
          b.cdstart, b.cdduration = start, duration
          CooldownFrame_SetTimer(b.cd, start, duration, enable)
        end

        if b.showing ~= entry then
          b.showing = entry
          b.icon:SetTexture(entry.icon)
        end

        if el == "judgement" then
          local seal = GetJudgeSeal()
          local sealUp = seal and buffs[seal.licon] ~= nil
          if seal then
            if b.secshowing ~= seal then
              b.secshowing = seal
              b.secframe.icon:SetTexture(seal.icon)
            end
            if sealUp then
              b.secframe:SetBackdropBorderColor(COLOR.judgement[1], COLOR.judgement[2], COLOR.judgement[3], 1)
              b.secframe.icon:SetVertexColor(1, 1, 1)
            else
              DefaultBorder(b.secframe)
              b.secframe.icon:SetVertexColor(.5, .5, .5)
            end
            b.secframe:Show()
          else
            b.secshowing = nil
            b.secframe:Hide()
          end
          -- dimmed while the debuff is already on the target (nothing to judge)
          SetIconTint(b, entry, not JudgementApplied(seal))
          SetTimerText(b, nil, nil)
        else
          -- aura / seal: dimmed while it is not up on you
          local left = buffs[entry.licon]
          SetIconTint(b, entry, left ~= nil)
          if left ~= nil then
            b:SetBackdropBorderColor(COLOR[el][1], COLOR[el][2], COLOR[el][3], 1)
          else
            DefaultBorder(b)
          end
          if el == "seal" and cfg.timer == "1" and left and left > 0 then
            SetTimerText(b, "|cffffffff", FormatTime(left))
          else
            SetTimerText(b, nil, nil)
          end
        end
      end
    end
  end)

  -- [[ events ]] --
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("SPELLS_CHANGED")
  events:RegisterEvent("LEARNED_SPELL_IN_TAB")
  events:RegisterEvent("BAG_UPDATE")
  events:RegisterEvent("UNIT_INVENTORY_CHANGED")
  events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  events:RegisterEvent("PLAYER_AURAS_CHANGED")
  events:SetScript("OnEvent", function()
    if event == "PLAYER_AURAS_CHANGED" then
      buffcache.t = -10
      return
    elseif event == "BAG_UPDATE" or event == "UNIT_INVENTORY_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
      if event ~= "UNIT_INVENTORY_CHANGED" or arg1 == "player" then this.bagdirty = true end
      return
    end
    this.dirty = true
  end)
  local function LibramSig()
    local sig = ""
    for _, e in pairs(known.libram) do
      sig = sig .. e.name .. ":" .. tostring(e.bag) .. ":" .. tostring(e.slot) .. "|"
    end
    return sig .. tostring(cfg.libram)
  end

  events:SetScript("OnUpdate", function()
    if this.dirty then
      this.dirty, this.bagdirty = nil, nil
      Scan()
      bar:UpdateConfig()
    elseif this.bagdirty then
      this.bagdirty = nil
      -- bag events are frequent: only rebuild the bar when the librams changed
      local before = LibramSig()
      ScanLibrams()
      if cfg.libram == "" and known.libram[1] then cfg.libram = known.libram[1].name end
      if LibramSig() ~= before then bar:UpdateConfig() end
    end

    -- pfUI creates / shows its stance bar on its own schedule: keep it hidden
    local now = GetTime()
    if (this.stancecheck or 0) <= now then
      this.stancecheck = now + .5
      local stances = _G.pfActionBarStances
      if stances and cfg.enable == "1" and cfg.hidestances == "1"
        and (not stances.pfPaladinBarHooked or stances:IsShown()) then
        SuppressStances()
      end
    end
  end)

  bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
  UpdateMovable(bar, true)
  Scan()
  bar:UpdateConfig()

  -- [[ public API ]] --
  -- casts unless it is already up; force = always cast
  local function CastElement(el, force)
    el = el and string.lower(el)
    if not VALID[el] or not Enabled(el) then return false end
    if el == "judgement" then
      return Judge()
    end
    local entry = GetActive(el)
    if not entry then return false end
    if not force and el ~= "libram" and IsUp(entry, true) then return false end
    Cast(entry)
    return true
  end

  local function Cycle(el, dir)
    local list = (el == "judgement") and known.seal or known[el]
    local count = list and table.getn(list) or 0
    if count == 0 then return end
    local current = (el == "judgement") and GetJudgeSeal() or GetActive(el)
    local idx = current and 1 or 0
    for i = 1, count do
      if list[i] == current then idx = i end
    end
    idx = idx + dir
    if idx > count then idx = 1 elseif idx < 1 then idx = count end
    SetActive(el, list[idx].name)
    Print(LABEL[el] .. ": " .. list[idx].name)
  end

  local function FindByName(el, query)
    local list = (el == "judgement") and known.seal or known[el]
    query = string.lower(query)
    for _, entry in pairs(list or {}) do
      if string.lower(entry.name) == query then return entry end
    end
    for _, entry in pairs(list or {}) do
      if string.find(string.lower(entry.name), query, 1, true) then return entry end
    end
  end

  _G.pfPaladinBar.Cast = CastElement
  _G.pfPaladinBar.CastAura = function(force) return CastElement("aura", force) end
  _G.pfPaladinBar.CastSeal = function(force) return CastElement("seal", force) end
  _G.pfPaladinBar.Judge = Judge
  _G.pfPaladinBar.EquipLibram = function() return CastElement("libram") end
  _G.pfPaladinBar.Next = function(el) if VALID[el] then Cycle(el, 1) end end
  _G.pfPaladinBar.Prev = function(el) if VALID[el] then Cycle(el, -1) end end
  _G.pfPaladinBar.SetActive = function(el, name)
    if VALID[el] and name and string.lower(name) == NONE then SetActive(el, NONE) return end
    local entry = VALID[el] and name and FindByName(el, name)
    if entry then SetActive(el, entry.name) end
  end
  _G.pfPaladinBar.GetActive = function(el)
    local entry = VALID[el] and ((el == "judgement") and GetJudgeSeal() or GetActive(el))
    return entry and entry.name
  end

  _G.SLASH_PFPALADINBAR1 = "/paladinbar"
  _G.SLASH_PFPALADINBAR2 = "/ppb"
  _G.SlashCmdList["PFPALADINBAR"] = function(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "judge" then cmd = "judgement" end

    if VALID[cmd] then
      CastElement(cmd, string.lower(rest) == "force")
    elseif (cmd == "next" or cmd == "prev") and VALID[string.lower(rest)] then
      Cycle(string.lower(rest), cmd == "next" and 1 or -1)
    elseif cmd == "set" then
      local _, _, el, name = string.find(rest, "^(%a+)%s+(.+)$")
      el = el and string.lower(el)
      if el == "judge" then el = "judgement" end
      if el and VALID[el] and name and string.lower(name) == NONE then
        SetActive(el, NONE)
        Print(LABEL[el] .. ": " .. T["None"])
        return
      end
      local entry = el and VALID[el] and FindByName(el, name)
      if entry then
        SetActive(el, entry.name)
        Print(LABEL[el] .. ": " .. entry.name)
      else
        Print("unknown group or name. Examples: /paladinbar set aura devotion, /paladinbar set judgement wisdom")
      end
    elseif cmd == "list" then
      for _, el in ipairs(ParseOrder()) do
        local entry = (el == "judgement") and GetJudgeSeal() or GetActive(el)
        Print(LABEL[el] .. ": " .. (entry and entry.name or "-"))
      end
    elseif cmd == "scan" then
      Scan()
      bar:UpdateConfig()
      Print("spellbook rescanned.")
    else
      Print("commands:")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar aura|seal |cffaaaaaa- cast the active aura / seal if it is not up")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar judgement |cffaaaaaa- same as clicking the Judgement button")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar libram |cffaaaaaa- equip the active libram")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar <aura|seal> force |cffaaaaaa- cast it even if it is up")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar next|prev <group> |cffaaaaaa- cycle the active aura / libram / seal / judgement seal")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar set <group> <name|none> |cffaaaaaa- e.g. /paladinbar set judgement wisdom")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar list |cffaaaaaa- show the selection")
      DEFAULT_CHAT_FRAME:AddMessage("  /paladinbar scan |cffaaaaaa- rescan the spellbook and bags")
    end
  end

  -- [[ pfUI config GUI ]] --
  if pfUI.gui and pfUI.gui.CreateGUIEntry then
    local positions = {
      "TOP:" .. T["Top"],
      "BOTTOM:" .. T["Bottom"],
      "LEFT:" .. T["Left"],
      "RIGHT:" .. T["Right"],
    }

    local function Values(el)
      return function()
        local values = {}
        local source = (el == "judgement") and known.seal or known[el]
        for _, entry in pairs(source) do
          table.insert(values, entry.name .. ":" .. entry.name)
        end
        table.insert(values, NONE .. ":" .. NONE_TEXT)
        return values
      end
    end

    local update = function() bar:UpdateConfig() end

    pfUI.gui.CreateGUIEntry(T["Thirdparty"], T["Paladin Bar"], function()
      local CreateConfig = pfUI.gui.CreateConfig

      CreateConfig(update, T["Enable Paladin Bar"], cfg, "enable", "checkbox")
      CreateConfig(update, T["Hide pfUI Stance Bar (aura buttons)"], cfg, "hidestances", "checkbox")

      CreateConfig(nil, T["Selection"], nil, nil, "header")
      CreateConfig(update, T["Aura"], cfg, "aura", "dropdown", Values("aura"))
      CreateConfig(update, T["Libram"], cfg, "libram", "dropdown", Values("libram"))
      CreateConfig(update, T["Seal"], cfg, "seal", "dropdown", Values("seal"))
      CreateConfig(update, T["Judgement Seal"], cfg, "judgeseal", "dropdown", Values("judgement"))

      CreateConfig(nil, T["Judgement"], nil, nil, "header")
      CreateConfig(update, T["Cast The Chosen Seal First If It Is Not Up"], cfg, "judgefirst", "checkbox")
      CreateConfig(update, T["Skip Judgement If Its Debuff Is Already On The Target"], cfg, "judgecheck", "checkbox")

      CreateConfig(nil, T["Libram"], nil, nil, "header")
      CreateConfig(update, T["Enable Libram Swap"], cfg, "enable_libram", "checkbox")

      CreateConfig(nil, T["Layout"], nil, nil, "header")
      CreateConfig(update, T["Button Order (aura,libram,seal,judgement)"], cfg, "order", nil, nil, nil, nil, "STRING")
      CreateConfig(update, T["Button Size"], cfg, "size")
      CreateConfig(update, T["Spacing"], cfg, "spacing", "dropdown", pfUI.gui.dropdowns.spacing)
      CreateConfig(update, T["Bar Direction"], cfg, "direction", "dropdown", pfUI.gui.dropdowns.orientation)
      CreateConfig(update, T["Reverse Button Order"], cfg, "reverse", "checkbox")
      CreateConfig(update, T["List Direction"], cfg, "flyout", "dropdown", positions)
      CreateConfig(update, T["Open List On Mouseover"], cfg, "hover", "checkbox")
      CreateConfig(update, T["Show Seal Timer"], cfg, "timer", "checkbox")
      CreateConfig(update, T["Show Background"], cfg, "showbg", "checkbox")
    end)
  end
end)
