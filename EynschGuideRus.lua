-- EynschGuideRus.lua
-- Простой аддон-гайд для WoW 1.12.1.

local mainFrame
local choiceFrame
local settingsFrame

local stepRows       = {}
local scrollFrame
local scrollChild
local scrollSlider
local headerFS

local contentWidth   = 320
local rowSpacing     = 4
local minRowHeight   = 24
local lineHeight     = 12
local rowPadding     = 6
local numColWidth    = 30

local currentGuide   = 1
local currentStep    = 1
local filtered       = {}

-- ============================================================
-- БД
-- ============================================================

local function EnsureDB()
    if not EynschGuideRusDB then EynschGuideRusDB = {} end
    if not EynschGuideRusDB.guide then EynschGuideRusDB.guide = 1 end
    if not EynschGuideRusDB.step  then EynschGuideRusDB.step  = 1 end
    if EynschGuideRusDB.locked == nil then EynschGuideRusDB.locked = false end
    if EynschGuideRusDB.scale  == nil then EynschGuideRusDB.scale  = 1.0  end
    if EynschGuideRusDB.alpha  == nil then EynschGuideRusDB.alpha  = 1.0  end
    if EynschGuideRusDB.winW   == nil then EynschGuideRusDB.winW   = 340  end
    if EynschGuideRusDB.winH   == nil then EynschGuideRusDB.winH   = 460  end
end

local function SaveProgress()
    EnsureDB()
    EynschGuideRusDB.guide = currentGuide
    EynschGuideRusDB.step  = currentStep
end

local function GetFaction()
    EnsureDB()
    return EynschGuideRusDB.faction
end

local function SetFaction(f)
    EnsureDB()
    EynschGuideRusDB.faction = f
end

local function SaveFramePosition(f)
    if not f or not UIParent then return end
    local left   = f:GetLeft()
    local bottom = f:GetBottom()
    if left and bottom then
        EynschGuideRusDB.posX = left
        EynschGuideRusDB.posY = bottom
    end
end

local function ApplyFramePosition(f)
    if not f or not UIParent then return end
    local x = EynschGuideRusDB.posX
    local y = EynschGuideRusDB.posY
    if x and y then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ============================================================
-- Фильтрация
-- ============================================================

local function RebuildFiltered()
    filtered = {}
    if not Guides then return end
    local f = GetFaction()
    if not f then return end

    local ids = {}
    for id, _ in pairs(Guides) do
        table.insert(ids, id)
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local g = Guides[id]
        if g and (g.faction == f or g.faction == "Neutral") then
            table.insert(filtered, id)
        end
    end
end

local function GetFilteredCount()
    return table.getn(filtered)
end

local function GetCurrentGuide()
    local realID = filtered[currentGuide]
    if not realID then return nil end
    return Guides[realID]
end

-- ============================================================
-- Прокрутка
-- ============================================================

local function UpdateScrollRange()
    if not scrollSlider or not scrollChild then return end
    local viewH  = scrollFrame:GetHeight() or 0
    local childH = scrollChild:GetHeight() or 0
    local maxVal = childH - viewH
    if maxVal < 0 then maxVal = 0 end
    scrollSlider:SetMinMaxValues(0, maxVal)
    if scrollSlider:GetValue() > maxVal then
        scrollSlider:SetValue(maxVal)
    end
    if maxVal > 0 then
        scrollSlider:Show()
    else
        scrollSlider:Hide()
        scrollFrame:SetVerticalScroll(0)
    end
end

-- ============================================================
-- Оценка высоты текста
-- ============================================================

local function EstimateTextHeight(text, textWidth)
    if not text or text == "" then return lineHeight + rowPadding * 2 end
    local charW = 6.0
    if textWidth < 10 then textWidth = 10 end
    local charsPerLine = math.floor(textWidth / charW)
    if charsPerLine < 1 then charsPerLine = 1 end
    local len = string.len(text)
    local lines = math.ceil(len / charsPerLine)
    if lines < 1 then lines = 1 end
    return lines * lineHeight + rowPadding * 2
end

-- ============================================================
-- Строки шагов
-- ============================================================

local function HideAllRows()
    for _, row in ipairs(stepRows) do
        row:Hide()
    end
end

local RefreshRows
local ScrollToActive

RefreshRows = function()
    local g = GetCurrentGuide()

    if headerFS then
        if g then
            headerFS:SetText(string.format("|cffFFD100%s|r  |cff808080(%s)|r",
                g.title, GetFaction() or "?"))
        else
            headerFS:SetText("|cffFF5555No guides for this faction.|r")
        end
    end

    HideAllRows()

    if not g then
        scrollChild:SetHeight(1)
        UpdateScrollRange()
        return
    end

    local scrollW = scrollFrame:GetWidth() or 0
    if scrollW < 100 then scrollW = contentWidth end
    scrollChild:SetWidth(scrollW)

    local n = table.getn(g.steps)
    if not n or n < 1 then
        scrollChild:SetHeight(1)
        UpdateScrollRange()
        return
    end

    local totalH = 0
    local rowW   = scrollW
    local textW  = rowW - numColWidth - rowPadding * 2
    if textW < 40 then textW = 40 end

    for i = 1, n do
        local row = stepRows[i]

        if not row then
            row = CreateFrame("Button", nil, scrollChild)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
            row:SetWidth(contentWidth)   -- жёсткая начальная ширина

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints(row)
            row.bg:SetTexture(0.1, 0.1, 0.1, 0.6)

            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints(row)
            row.hl:SetTexture(0.3, 0.3, 0.5, 0.5)

            row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.num:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -rowPadding)
            row.num:SetWidth(numColWidth)
            row.num:SetJustifyH("LEFT")
            row.num:SetJustifyV("TOP")

            -- Только TOPLEFT-анкор, без TOPRIGHT/BOTTOMRIGHT,
            -- чтобы ширина текста задавалась явно и не тянула родителя
            row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.txt:SetPoint("TOPLEFT", row, "TOPLEFT", numColWidth + 2, -rowPadding)
            row.txt:SetJustifyH("LEFT")
            row.txt:SetJustifyV("TOP")

            if row.txt.SetWordWrap then
                row.txt:SetWordWrap(true)
            end
            if row.txt.SetNonSpaceWrap then
                row.txt:SetNonSpaceWrap(false)
            end

            row:SetScript("OnClick", function()
                local idx = row.index
                if idx then
                    currentStep = idx
                    SaveProgress()
                    RefreshRows()
                    -- Принудительно восстанавливаем ширину всех плашек:
                    -- в 1.12.1 после смены цвета фона клиент иногда
                    -- пытается пересчитать размер родителя по содержимому
                    local w = scrollFrame:GetWidth()
                    if w and w > 100 then
                        for _, r in ipairs(stepRows) do
                            if r:IsShown() then
                                r:SetWidth(w)
                            end
                        end
                    end
                end
            end)

            stepRows[i] = row
        end

        local s = g.steps[i]
        local stepText = s.text or ""

        local coordText = ""
        if s.zone and s.x and s.y then
            coordText = string.format("   |cff8080FF[%s %d,%d]|r", s.zone, s.x, s.y)
        end

        local fullText = stepText .. coordText
        local h = EstimateTextHeight(fullText, textW)
        if h < minRowHeight then h = minRowHeight end

        -- ПОРЯДОК ВАЖЕН: сначала высота, потом ширина текста,
        -- только затем ширина самой плашки
        row.index = i
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalH)
        row:SetHeight(h)
        row.txt:SetWidth(textW)
        row:SetWidth(rowW)
        row:Show()

        if i == currentStep then
            row.num:SetText("|cffFFD100> " .. i .. "|r")
            row.txt:SetText("|cffFFD100" .. stepText .. "|r" .. coordText)
            row.bg:SetTexture(0.25, 0.2, 0.05, 0.9)
        else
            row.num:SetText("|cff808080" .. i .. "|r")
            row.txt:SetText("|cffD0D0D0" .. stepText .. "|r" .. coordText)
            row.bg:SetTexture(0.1, 0.1, 0.1, 0.6)
        end

        totalH = totalH + h + rowSpacing
    end

    scrollChild:SetHeight(totalH + 8)
    UpdateScrollRange()
end

ScrollToActive = function()
    if not scrollSlider then return end
    local activeRow = stepRows[currentStep]
    if not activeRow or not activeRow:IsShown() then return end

    local rowTop = 0
    for i = 1, currentStep - 1 do
        local r = stepRows[i]
        if r then
            rowTop = rowTop + (r:GetHeight() or 0) + rowSpacing
        end
    end

    local viewH = scrollFrame:GetHeight() or 0
    local rowH  = activeRow:GetHeight() or 0
    local target = rowTop - viewH / 2 + rowH / 2
    if target < 0 then target = 0 end

    local _, maxV = scrollSlider:GetMinMaxValues()
    if maxV and target > maxV then target = maxV end
    scrollSlider:SetValue(target)
end

-- ============================================================
-- Навигация
-- ============================================================

local function ChangeGuide(delta)
    local count = GetFilteredCount()
    if count < 1 then return end
    currentGuide = currentGuide + delta
    if currentGuide < 1 then currentGuide = count end
    if currentGuide > count then currentGuide = 1 end
    currentStep = 1
    SaveProgress()
    RefreshRows()
    if scrollSlider then
        scrollSlider:SetValue(0)
    end
end

local function ChangeStep(delta)
    local g = GetCurrentGuide()
    if not g then return end
    local n = table.getn(g.steps)
    if not n or n < 1 then return end
    currentStep = currentStep + delta
    if currentStep < 1 then currentStep = 1 end
    if currentStep > n then currentStep = n end
    SaveProgress()
    RefreshRows()
    local t = CreateFrame("Frame")
    t:SetScript("OnUpdate", function()
        ScrollToActive()
        this:SetScript("OnUpdate", nil)
    end)
end

-- ============================================================
-- UI helpers
-- ============================================================

local function MakeIconButton(parent, label, x, y, onClick)
    local size = 22
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(size)
    b:SetHeight(size)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetTexture(0.15, 0.15, 0.15, 0.9)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(label)

    b:SetScript("OnEnter", function() bg:SetTexture(0.35, 0.35, 0.6, 1) end)
    b:SetScript("OnLeave", function() bg:SetTexture(0.15, 0.15, 0.15, 0.9) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ============================================================
-- Смена фракции / выбор гайда
-- ============================================================

local function SwitchFaction(newFaction)
    SetFaction(newFaction)
    RebuildFiltered()
    currentGuide = 1
    currentStep  = 1
    SaveProgress()
    if mainFrame then
        RefreshRows()
        if scrollSlider then scrollSlider:SetValue(0) end
    end
end

local function SelectGuideByRealID(realID)
    if not Guides or not Guides[realID] then return end
    for idx, id in ipairs(filtered) do
        if id == realID then
            currentGuide = idx
            currentStep  = 1
            SaveProgress()
            if choiceFrame then choiceFrame:Hide() end
            if mainFrame then
                mainFrame:Show()
                RefreshRows()
                if scrollSlider then scrollSlider:SetValue(0) end
            end
            return
        end
    end
end

-- ============================================================
-- Главное окно
-- ============================================================

local function CreateMainFrame()
    EnsureDB()

    local f = CreateFrame("Frame", "EynschGuideRusFrame", UIParent)
    f:SetWidth(EynschGuideRusDB.winW)
    f:SetHeight(EynschGuideRusDB.winH)
    ApplyFramePosition(f)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    f:SetMovable(not EynschGuideRusDB.locked)
    f:EnableMouse(not EynschGuideRusDB.locked)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetScale(EynschGuideRusDB.scale)
    f:SetAlpha(EynschGuideRusDB.alpha)

    f:SetScript("OnDragStart", function()
        if not EynschGuideRusDB.locked then
            f:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function()
        if not EynschGuideRusDB.locked then
            f:StopMovingOrSizing()
            SaveFramePosition(f)
        end
    end)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cffFFD100EynschGuideRus|r")

    local close = CreateFrame("Button", nil, f)
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeFS = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeFS:SetPoint("CENTER", close, "CENTER", 0, 1)
    closeFS:SetText("|cffFF5555X|r")
    close:SetScript("OnClick", function()
        SaveFramePosition(f)
        f:Hide()
    end)

    local lock = CreateFrame("Button", nil, f)
    lock:SetWidth(20)
    lock:SetHeight(20)
    lock:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -6)

    local lockFS = lock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockFS:SetPoint("CENTER", lock, "CENTER", 0, 1)

    local function UpdateLockVisual()
        if EynschGuideRusDB.locked then
            lockFS:SetText("|cffFFD100L|r")
        else
            lockFS:SetText("|cff8080FFU|r")
        end
    end

    lock:SetScript("OnClick", function()
        EynschGuideRusDB.locked = not EynschGuideRusDB.locked
        if EynschGuideRusDB.locked then
            f:SetMovable(false)
            f:EnableMouse(false)
            SaveFramePosition(f)
        else
            f:SetMovable(true)
            f:EnableMouse(true)
        end
        UpdateLockVisual()
    end)

    UpdateLockVisual()

    local setBtn = CreateFrame("Button", nil, f)
    setBtn:SetWidth(20)
    setBtn:SetHeight(20)
    setBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -6)

    local setBg = setBtn:CreateTexture(nil, "BACKGROUND")
    setBg:SetAllPoints(setBtn)
    setBg:SetTexture(0.15, 0.15, 0.15, 0.9)

    local setFS = setBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setFS:SetPoint("CENTER", setBtn, "CENTER", 0, 1)
    setFS:SetText("|cffFFFF55S|r")

    setBtn:SetScript("OnEnter", function() setBg:SetTexture(0.35, 0.35, 0.6, 1) end)
    setBtn:SetScript("OnLeave", function() setBg:SetTexture(0.15, 0.15, 0.15, 0.9) end)
    setBtn:SetScript("OnClick", function()
        if settingsFrame then settingsFrame:Show() end
    end)

    headerFS = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerFS:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
    headerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
    headerFS:SetJustifyH("LEFT")
    headerFS:SetText("")

    scrollFrame = CreateFrame("ScrollFrame", "EynschGuideRusScroll", f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 38)
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame", "EynschGuideRusScrollChild", scrollFrame)
    scrollChild:SetWidth(10)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollSlider = CreateFrame("Slider", "EynschGuideRusSlider", f)
    scrollSlider:SetOrientation("VERTICAL")
    scrollSlider:SetWidth(10)
    scrollSlider:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    -2, 0)
    scrollSlider:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2, 0)
    scrollSlider:SetValueStep(1)
    scrollSlider:SetMinMaxValues(0, 0)

    local thumb = scrollSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    thumb:SetWidth(10)
    thumb:SetHeight(20)
    scrollSlider:SetThumbTexture(thumb)

    local sBg = scrollSlider:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints(scrollSlider)
    sBg:SetTexture(0, 0, 0, 0.5)

    scrollSlider:SetScript("OnValueChanged", function()
        scrollFrame:SetVerticalScroll(scrollSlider:GetValue())
    end)
    scrollSlider:Hide()

    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        if delta == nil then return end
        local cur = scrollSlider:GetValue() or 0
        local _, maxV = scrollSlider:GetMinMaxValues()
        if not maxV then maxV = 0 end
        if delta < 0 then
            cur = cur + 30
            if cur > maxV then cur = maxV end
        else
            cur = cur - 30
            if cur < 0 then cur = 0 end
        end
        scrollSlider:SetValue(cur)
    end)

    scrollFrame:SetScript("OnSizeChanged", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
    end)

    local btnY    = 8
    local btnX    = 94
    local btnStep = 26

    MakeIconButton(f, "<<", btnX,               btnY, function() ChangeGuide(-1) end)
    MakeIconButton(f, "<",  btnX + btnStep,     btnY, function() ChangeStep(-1)  end)
    MakeIconButton(f, ">",  btnX + btnStep * 2, btnY, function() ChangeStep(1)   end)
    MakeIconButton(f, ">>", btnX + btnStep * 3, btnY, function() ChangeGuide(1)  end)
    MakeIconButton(f, "R",  btnX + btnStep * 4, btnY, function()
        currentStep = 1
        SaveProgress()
        RefreshRows()
        if scrollSlider then scrollSlider:SetValue(0) end
    end)
    MakeIconButton(f, "F",  btnX + btnStep * 5, btnY, function()
        if choiceFrame then choiceFrame:Show() end
    end)

    f:SetScript("OnShow", function()
        RefreshRows()
        local t = CreateFrame("Frame")
        t:SetScript("OnUpdate", function()
            ScrollToActive()
            this:SetScript("OnUpdate", nil)
        end)
    end)

    return f
end

-- ============================================================
-- Окно выбора гайда
-- ============================================================

local function CreateChoiceFrame()
    local f = CreateFrame("Frame", "EynschGuideRusChoiceFrame", UIParent)
    f:SetWidth(300)
    f:SetHeight(360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    f:Hide()

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cffFFD100Select Guide|r")

    local sub = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Choose faction, then a starting zone.")
    sub:SetTextColor(0.8, 0.8, 0.8)

    local close = CreateFrame("Button", nil, f)
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeFS = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeFS:SetPoint("CENTER", close, "CENTER", 0, 1)
    closeFS:SetText("|cffFF5555X|r")
    close:SetScript("OnClick", function() f:Hide() end)

    local listContainer
    local hordeBtn, allianceBtn

    local function UpdateFactionButtons()
        local cur = GetFaction()
        if hordeBtn then
            if cur == "Horde" then
                hordeBtn.bg:SetTexture(0.5, 0.15, 0.15, 1)
            else
                hordeBtn.bg:SetTexture(0.15, 0.15, 0.15, 0.9)
            end
        end
        if allianceBtn then
            if cur == "Alliance" then
                allianceBtn.bg:SetTexture(0.15, 0.3, 0.6, 1)
            else
                allianceBtn.bg:SetTexture(0.15, 0.15, 0.15, 0.9)
            end
        end
    end

    local function MakeFactionButton(label, faction, x, color)
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(120)
        b:SetHeight(26)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -58)

        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture(0.15, 0.15, 0.15, 0.9)

        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(label)
        if color then fs:SetTextColor(color[1], color[2], color[3]) end

        b:SetScript("OnClick", function()
            SwitchFaction(faction)
            if listContainer and listContainer.Refresh then
                listContainer.Refresh()
            end
            UpdateFactionButtons()
        end)
        return b
    end

    hordeBtn    = MakeFactionButton("Horde",    "Horde",    20,  {1, 0.2, 0.2})
    allianceBtn = MakeFactionButton("Alliance", "Alliance", 160, {0.3, 0.6, 1})

    local listFrame = CreateFrame("ScrollFrame", "EynschGuideRusChoiceList", f)
    listFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -95)
    listFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    listFrame:EnableMouseWheel(true)

    local listChild = CreateFrame("Frame", "EynschGuideRusChoiceListChild", listFrame)
    listChild:SetWidth(10)
    listChild:SetHeight(1)
    listFrame:SetScrollChild(listChild)

    local listSlider = CreateFrame("Slider", "EynschGuideRusChoiceSlider", f)
    listSlider:SetOrientation("VERTICAL")
    listSlider:SetWidth(10)
    listSlider:SetPoint("TOPLEFT",    listFrame, "TOPRIGHT",    -2, 0)
    listSlider:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", -2, 0)
    listSlider:SetValueStep(1)
    listSlider:SetMinMaxValues(0, 0)

    local thumb = listSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    thumb:SetWidth(10)
    thumb:SetHeight(20)
    listSlider:SetThumbTexture(thumb)

    local sBg = listSlider:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints(listSlider)
    sBg:SetTexture(0, 0, 0, 0.5)

    listSlider:SetScript("OnValueChanged", function()
        listFrame:SetVerticalScroll(listSlider:GetValue())
    end)
    listSlider:Hide()

    listFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        if delta == nil then return end
        local cur = listSlider:GetValue() or 0
        local _, maxV = listSlider:GetMinMaxValues()
        if not maxV then maxV = 0 end
        if delta < 0 then
            cur = cur + 30
            if cur > maxV then cur = maxV end
        else
            cur = cur - 30
            if cur < 0 then cur = 0 end
        end
        listSlider:SetValue(cur)
    end)

    local guideButtons = {}

    local function RefreshGuideList()
        local cur = GetFaction()
        for _, b in ipairs(guideButtons) do
            b:Hide()
        end

        if not cur or not Guides then
            listChild:SetHeight(1)
            listSlider:SetMinMaxValues(0, 0)
            listSlider:Hide()
            return
        end

        local ids = {}
        for id, g in pairs(Guides) do
            if g and (g.faction == cur or g.faction == "Neutral") then
                table.insert(ids, id)
            end
        end
        table.sort(ids)

        local y = 0
        local rowH = 26
        local gap  = 4
        local width = listFrame:GetWidth() or 260
        if width < 100 then width = 260 end

        for i, id in ipairs(ids) do
            local b = guideButtons[i]
            if not b then
                b = CreateFrame("Button", nil, listChild)
                b.bg = b:CreateTexture(nil, "BACKGROUND")
                b.bg:SetAllPoints(b)
                b.bg:SetTexture(0.1, 0.1, 0.1, 0.7)

                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints(b)
                b.hl:SetTexture(0.3, 0.3, 0.5, 0.5)

                b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                b.txt:SetPoint("LEFT", b, "LEFT", 8, 0)
                b.txt:SetPoint("RIGHT", b, "RIGHT", -8, 0)
                b.txt:SetJustifyH("LEFT")

                b:SetScript("OnClick", function()
                    if b.realID then
                        SelectGuideByRealID(b.realID)
                    end
                end)

                guideButtons[i] = b
            end

            b.realID = id
            b:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -y)
            b:SetWidth(width)
            b:SetHeight(rowH)

            local g = Guides[id]
            local marker = ""
            local isCurrent = false
            if filtered[currentGuide] == b.realID then
                isCurrent = true
                marker = "|cffFFD100> |r"
            end
            b.txt:SetText(marker .. "|cffD0D0D0" .. (g.title or ("Guide " .. id)) .. "|r")

            if isCurrent then
                b.bg:SetTexture(0.25, 0.2, 0.05, 0.9)
            else
                b.bg:SetTexture(0.1, 0.1, 0.1, 0.7)
            end

            b:Show()
            y = y + rowH + gap
        end

        listChild:SetWidth(width)
        listChild:SetHeight(y + 8)

        local viewH = listFrame:GetHeight() or 0
        local maxV = (y + 8) - viewH
        if maxV < 0 then maxV = 0 end
        listSlider:SetMinMaxValues(0, maxV)
        if maxV > 0 then listSlider:Show() else listSlider:Hide() end
        listSlider:SetValue(0)
        listFrame:SetVerticalScroll(0)
    end

    listContainer = { Refresh = RefreshGuideList }

    listFrame:SetScript("OnSizeChanged", function()
        listChild:SetWidth(listFrame:GetWidth())
    end)

    f:SetScript("OnShow", function()
        UpdateFactionButtons()
        RefreshGuideList()
    end)

    return f
end

-- ============================================================
-- Окно настроек
-- ============================================================

local function CreateSettingsFrame()
    local f = CreateFrame("Frame", "EynschGuideRusSettingsFrame", UIParent)
    f:SetWidth(280)
    f:SetHeight(220)
    f:SetPoint("CENTER", UIParent, "CENTER", 60, -60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    f:Hide()

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cffFFD100EynschGuideRus Settings|r")

    local close = CreateFrame("Button", nil, f)
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeFS = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeFS:SetPoint("CENTER", close, "CENTER", 0, 1)
    closeFS:SetText("|cffFF5555X|r")
    close:SetScript("OnClick", function() f:Hide() end)

    local function MakeSlider(y, label, minV, maxV, step, getValue, setValue, fmt)
        local slider = CreateFrame("Slider", nil, f)
        slider:SetOrientation("HORIZONTAL")
        slider:SetWidth(160)
        slider:SetHeight(16)
        slider:SetPoint("TOP", f, "TOP", 0, y)
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(step)
        slider:SetValue(getValue())

        local bg = slider:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(slider)
        bg:SetTexture(0, 0, 0, 0.5)

        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        thumb:SetWidth(16)
        thumb:SetHeight(16)
        slider:SetThumbTexture(thumb)

        local lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("BOTTOM", slider, "TOP", 0, 0)
        lbl:SetText(label)

        local val = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        val:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        val:SetTextColor(1, 1, 0.3, 1)

        local function refreshLabel()
            val:SetText(string.format(fmt, getValue()))
        end
        refreshLabel()

        slider:SetScript("OnValueChanged", function()
            local v = slider:GetValue()
            setValue(v)
            refreshLabel()
        end)

        return slider
    end

    -- Scale
    MakeSlider(-55, "Scale", 50, 200, 5,
        function() return EynschGuideRusDB.scale * 100 end,
        function(v)
            EynschGuideRusDB.scale = v / 100
            if mainFrame then mainFrame:SetScale(EynschGuideRusDB.scale) end
        end,
        "%.0f%%"
    )

    -- Opacity
    MakeSlider(-85, "Opacity", 20, 100, 5,
        function() return EynschGuideRusDB.alpha * 100 end,
        function(v)
            EynschGuideRusDB.alpha = v / 100
            if mainFrame then mainFrame:SetAlpha(EynschGuideRusDB.alpha) end
        end,
        "%.0f%%"
    )

    -- Width
    MakeSlider(-115, "Width", 260, 600, 10,
        function() return EynschGuideRusDB.winW end,
        function(v)
            EynschGuideRusDB.winW = v
            if mainFrame then mainFrame:SetWidth(v) end
        end,
        "%.0f px"
    )

    -- Height
    MakeSlider(-145, "Height", 300, 800, 10,
        function() return EynschGuideRusDB.winH end,
        function(v)
            EynschGuideRusDB.winH = v
            if mainFrame then mainFrame:SetHeight(v) end
        end,
        "%.0f px"
    )

    -- Reset to defaults
    local reset = CreateFrame("Button", nil, f)
    reset:SetWidth(150)
    reset:SetHeight(22)
    reset:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)

    local rBg = reset:CreateTexture(nil, "BACKGROUND")
    rBg:SetAllPoints(reset)
    rBg:SetTexture(0.15, 0.15, 0.15, 0.9)

    local rFs = reset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rFs:SetPoint("CENTER", reset, "CENTER", 0, 0)
    rFs:SetText("Reset to defaults")

    reset:SetScript("OnEnter", function() rBg:SetTexture(0.3, 0.3, 0.5, 1) end)
    reset:SetScript("OnLeave", function() rBg:SetTexture(0.15, 0.15, 0.15, 0.9) end)
    reset:SetScript("OnClick", function()
        EynschGuideRusDB.scale = 1.0
        EynschGuideRusDB.alpha = 1.0
        EynschGuideRusDB.winW  = 340
        EynschGuideRusDB.winH  = 460
        if mainFrame then
            mainFrame:SetScale(EynschGuideRusDB.scale)
            mainFrame:SetAlpha(EynschGuideRusDB.alpha)
            mainFrame:SetWidth(EynschGuideRusDB.winW)
            mainFrame:SetHeight(EynschGuideRusDB.winH)
        end
        f:Hide()
        f:Show()
    end)

    return f
end

-- ============================================================
-- Слэш-команды
-- ============================================================

SLASH_EYNSCHGUIDERUS1 = "/egr"
SLASH_EYNSCHGUIDERUS2 = "/eynschguide"
SlashCmdList["EYNSCHGUIDERUS"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "select" or msg == "menu" then
        if choiceFrame then choiceFrame:Show() end
        return
    end
    if msg == "settings" or msg == "config" then
        if settingsFrame then settingsFrame:Show() end
        return
    end
    if not mainFrame then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF5555EynschGuideRus|r not ready yet.")
        return
    end
    if mainFrame:IsVisible() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

-- ============================================================
-- Инициализация
-- ============================================================

local init = CreateFrame("Frame")
init:RegisterEvent("VARIABLES_LOADED")
init:SetScript("OnEvent", function()
    EnsureDB()
    mainFrame     = CreateMainFrame()
    choiceFrame   = CreateChoiceFrame()
    settingsFrame = CreateSettingsFrame()

    if not GetFaction() then
        choiceFrame:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00FF00EynschGuideRus|r: choose your faction and starting zone.")
    else
        RebuildFiltered()
        currentGuide = EynschGuideRusDB.guide or 1
        currentStep  = EynschGuideRusDB.step  or 1
        if currentGuide > GetFilteredCount() then currentGuide = 1 end
        if currentGuide < 1 then currentGuide = 1 end
        if currentStep  < 1 then currentStep  = 1 end

        mainFrame:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00FF00EynschGuideRus|r loaded.")
    end
end)
