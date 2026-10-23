-- clean_ui.lua  (UI only)
-- Big black window with tiny rounded corners.
--   * Top right: dark-grey cluster with minimize (dash), maximize (square) and close (X).
--     Hovering a button lights up a small rounded square: light grey, or red for close.
--   * Left: a slim sidebar with the "Y1" logo text at the top. At its bottom: a gear icon (hover shows a "Settings" tooltip, click opens
--     Settings), and under it your profile picture in a smooth square.
--     Click the picture and an account panel opens next to it: profile picture, display name, username, ID.
--   * Top left: a small card showing the current tab (Main / Settings). Settings has a back arrow.
-- Settings has a "UI Toggle Keybind" (default RightShift): press it to hide / show the window with an
--   animation. Click the key button and press any key to rebind (Escape cancels).
-- Drag the top bar to move the window.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

do
	local old = playerGui:FindFirstChild("CleanBlackUI")
	if old then old:Destroy() end
end

-- ═══ THEME ══════════════════════════════════════════════════════════════════════════════════════
local BLACK        = Color3.fromRGB(10, 10, 11)    -- window
local BORDER       = Color3.fromRGB(36, 36, 39)    -- thin outline
local SIDEBAR_BG   = Color3.fromRGB(17, 17, 19)    -- sidebar
local CARD_BG      = Color3.fromRGB(28, 28, 31)    -- signed-in card + popup cards
local CARD_HOVER   = Color3.fromRGB(36, 36, 40)
local POPUP_BG     = Color3.fromRGB(20, 20, 22)
local CLUSTER_BG   = Color3.fromRGB(30, 30, 33)    -- dark grey behind the three buttons
local ICON         = Color3.fromRGB(176, 176, 182) -- light grey icons
local ICON_HOVER   = Color3.fromRGB(240, 240, 244)
local HOVER_GREY   = Color3.fromRGB(66, 66, 72)    -- highlighted square (minimize / maximize)
local HOVER_RED    = Color3.fromRGB(214, 62, 62)   -- highlighted square (close)
local TEXT_COLOR   = Color3.fromRGB(230, 230, 234)
local DIM_TEXT     = Color3.fromRGB(116, 116, 124)

local RADIUS = 4 -- tiny, smooth corners
local SQUARE_RADIUS = 10 -- "smooth square" for profile pictures

local WINDOW_SIZE = UDim2.fromOffset(760, 480)
local BAR_H = 40
local SIDEBAR_W_MIN = 56       -- sidebar width
local TILE = 40                -- size of the profile square / icon slot

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EXPAND = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local COLLAPSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local SIDE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ═══ HELPERS ════════════════════════════════════════════════════════════════════════════════════
local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or RADIUS)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function label(parent, text, pos, size, font, textSize, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextSize = textSize
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd -- too long -> "..."
	l.Parent = parent
	return l
end

local function inside(obj, pos)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

-- which parts of the sidebar area the cursor is currently on (set by MouseEnter / MouseLeave,
-- so it doesn't depend on screen-coordinate maths)
local hover = { sidebar = false, card = false, icon = false, popup = false }

-- page switching (defined further down, declared here so the gear icon can call it)
local currentPage = "Main"
local showPage = function(_name) end

-- ═══ WINDOW ═════════════════════════════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "CleanBlackUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local window = Instance.new("CanvasGroup") -- CanvasGroup: the whole window fades as one piece
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = WINDOW_SIZE
window.BackgroundColor3 = BLACK
window.BorderSizePixel = 0
window.Parent = gui
corner(window)

local windowScale = Instance.new("UIScale") -- used for the hide / show pop animation
windowScale.Scale = 1
windowScale.Parent = window

-- outline lives on an overlay inside the window so the canvas never clips it
local outline = Instance.new("Frame")
outline.Name = "Outline"
outline.Position = UDim2.fromOffset(1, 1)
outline.Size = UDim2.new(1, -2, 1, -2)
outline.BackgroundTransparency = 1
outline.BorderSizePixel = 0
outline.ZIndex = 20
outline.Parent = window
corner(outline, RADIUS)
stroke(outline, BORDER, 1, 0)

-- top bar (drag handle, holds the window controls)
local bar = Instance.new("Frame")
bar.Name = "TopBar"
bar.Size = UDim2.new(1, 0, 0, BAR_H)
bar.BackgroundTransparency = 1
bar.Parent = window

-- ═══ SIDEBAR ════════════════════════════════════════════════════════════════════════════════════
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Position = UDim2.fromOffset(6, 6)
sidebar.Size = UDim2.new(0, SIDEBAR_W_MIN, 1, -12)
sidebar.BackgroundColor3 = SIDEBAR_BG
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 2
sidebar.Parent = window
corner(sidebar)

-- content area (empty, put your pages here). Sits next to the COLLAPSED sidebar,
-- the sidebar expands over it when hovered.
local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(SIDEBAR_W_MIN + 12, BAR_H)
content.Size = UDim2.new(1, -(SIDEBAR_W_MIN + 18), 1, -(BAR_H + 6))
content.BackgroundTransparency = 1
content.Parent = window

-- pages (put each page's controls inside its frame)
local mainPage = Instance.new("Frame")
mainPage.Name = "MainPage"
mainPage.Size = UDim2.fromScale(1, 1)
mainPage.BackgroundTransparency = 1
mainPage.Visible = true
mainPage.Parent = content

local settingsPage = Instance.new("Frame")
settingsPage.Name = "SettingsPage"
settingsPage.Size = UDim2.fromScale(1, 1)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false
settingsPage.Parent = content

-- ═══ LOGO TEXT (top of the sidebar) ═════════════════════════════════════════════════════════════
local logo = Instance.new("Frame")
logo.Name = "Logo"
logo.Position = UDim2.fromOffset(14, 14)
logo.Size = UDim2.fromOffset(TILE, 32)
logo.BackgroundTransparency = 1
logo.ZIndex = 3
logo.Parent = window

local logoText = Instance.new("TextLabel")
logoText.Name = "Y1"
logoText.BackgroundTransparency = 1
logoText.Position = UDim2.fromOffset(0, 0)
logoText.Size = UDim2.new(1, 0, 0, 30)
logoText.Font = Enum.Font.GothamBlack
logoText.Text = "Y1"
logoText.TextSize = 24
logoText.TextColor3 = Color3.new(1, 1, 1) -- the gradient below does the colouring
logoText.TextXAlignment = Enum.TextXAlignment.Center
logoText.TextYAlignment = Enum.TextYAlignment.Center
logoText.ZIndex = 4
logoText.Parent = logo

do
	-- bright at the top, fading to soft grey at the bottom
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
	})
	g.Parent = logoText
end

-- ═══ SIDEBAR ICON (above the profile card, no functionality yet) ════════════════════════════════
local iconSlot = Instance.new("Frame")
iconSlot.Name = "SidebarIcon"
iconSlot.AnchorPoint = Vector2.new(0, 1)
iconSlot.Position = UDim2.new(0, 14, 1, -(14 + TILE + 8))
iconSlot.Size = UDim2.fromOffset(TILE, TILE)
iconSlot.BackgroundTransparency = 1
iconSlot.ZIndex = 3
iconSlot.Parent = window

do
	-- scalloped gear: two rounded squares (straight + rotated 45°) + a hollow centre
	-- everything lives in "gear" so one UIScale can grow it from the middle on hover
	local gear = Instance.new("Frame")
	gear.Name = "Gear"
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.Position = UDim2.fromScale(0.5, 0.5)
	gear.Size = UDim2.fromScale(1, 1)
	gear.BackgroundTransparency = 1
	gear.ZIndex = 3
	gear.Parent = iconSlot

	local gearScale = Instance.new("UIScale")
	gearScale.Scale = 1
	gearScale.Parent = gear

	local function shape(w, rot, r, color)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, w)
		f.Rotation = rot
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = 3
		f.Parent = gear
		corner(f, r)
		return f
	end
	local sq1 = shape(22, 0, 3, ICON)
	local sq2 = shape(22, 45, 3, ICON)
	shape(10, 0, 5, SIDEBAR_BG)    -- hollow centre

	-- invisible button over the slot, only used to detect the cursor
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 6
	hit.Parent = iconSlot

	hit.Activated:Connect(function()
		showPage("Settings")
	end)

	-- tiny "Settings" tooltip that fades in beside the gear
	local TIP_X = 14 + TILE + 10
	local tip = Instance.new("Frame")
	tip.Name = "SettingsTip"
	tip.AnchorPoint = Vector2.new(0, 0.5)
	tip.Position = UDim2.new(0, TIP_X - 4, 1, -(14 + TILE + 8 + TILE / 2))
	tip.Size = UDim2.fromOffset(66, 24)
	tip.BackgroundColor3 = CLUSTER_BG
	tip.BackgroundTransparency = 1
	tip.BorderSizePixel = 0
	tip.ZIndex = 8
	tip.Parent = window
	corner(tip, RADIUS + 1)
	local tipStroke = stroke(tip, BORDER, 1, 1)

	local tipText = Instance.new("TextLabel")
	tipText.BackgroundTransparency = 1
	tipText.Size = UDim2.fromScale(1, 1)
	tipText.Font = Enum.Font.GothamMedium
	tipText.Text = "Settings"
	tipText.TextSize = 12
	tipText.TextColor3 = TEXT_COLOR
	tipText.TextTransparency = 1
	tipText.ZIndex = 9
	tipText.Parent = tip

	local function showTip(visible)
		TweenService:Create(tip, SMOOTH, {
			Position = UDim2.new(0, visible and TIP_X or TIP_X - 4, 1, -(14 + TILE + 8 + TILE / 2)),
			BackgroundTransparency = visible and 0 or 1,
		}):Play()
		TweenService:Create(tipStroke, FAST, { Transparency = visible and 0 or 1 }):Play()
		TweenService:Create(tipText, FAST, { TextTransparency = visible and 0 or 1 }):Play()
	end

	local GROW = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	hit.MouseEnter:Connect(function()
		hover.icon = true
		showTip(true)
		TweenService:Create(gearScale, GROW, { Scale = 1.2 }):Play()
		TweenService:Create(sq1, FAST, { BackgroundColor3 = ICON_HOVER }):Play()
		TweenService:Create(sq2, FAST, { BackgroundColor3 = ICON_HOVER }):Play()
	end)
	hit.MouseLeave:Connect(function()
		hover.icon = false
		showTip(false)
		TweenService:Create(gearScale, GROW, { Scale = 1 }):Play()
		TweenService:Create(sq1, FAST, { BackgroundColor3 = ICON }):Play()
		TweenService:Create(sq2, FAST, { BackgroundColor3 = ICON }):Play()
	end)
end

-- ═══ PROFILE CARD (bottom of the sidebar) ═══════════════════════════════════════════════════════
local CARD_POS = UDim2.new(0, 14, 1, -14)                 -- in window space, so the popup can grow out of it
local CARD_SIZE = UDim2.fromOffset(TILE, TILE)            -- just the picture

local card = Instance.new("TextButton")
card.Name = "ProfileCard"
card.AutoButtonColor = false
card.Text = ""
card.AnchorPoint = Vector2.new(0, 1)
card.Position = CARD_POS
card.Size = CARD_SIZE
card.BackgroundColor3 = CARD_BG
card.BorderSizePixel = 0
card.ZIndex = 3
card.Parent = window
corner(card, SQUARE_RADIUS)

-- profile picture (smooth square)
local cardAvatar = Instance.new("ImageLabel")
cardAvatar.Name = "Avatar"
cardAvatar.Position = UDim2.fromOffset(0, 0)
cardAvatar.Size = UDim2.fromOffset(TILE, TILE)
cardAvatar.BackgroundColor3 = CARD_BG
cardAvatar.BorderSizePixel = 0
cardAvatar.Image = ""
cardAvatar.ZIndex = 4
cardAvatar.Parent = card
corner(cardAvatar, SQUARE_RADIUS)

card.MouseEnter:Connect(function()
	hover.card = true
	TweenService:Create(card, FAST, { BackgroundColor3 = CARD_HOVER }):Play()
end)
card.MouseLeave:Connect(function()
	hover.card = false
	TweenService:Create(card, FAST, { BackgroundColor3 = CARD_BG }):Play()
end)

-- ═══ ACCOUNT POPUP (grows out of the card) ══════════════════════════════════════════════════════
local POP_POS = UDim2.new(0, SIDEBAR_W_MIN + 12, 1, -14)
local POP_SIZE = UDim2.fromOffset(264, 148)

local popup = Instance.new("CanvasGroup") -- CanvasGroup: everything inside fades together
popup.Name = "AccountPopup"
popup.AnchorPoint = Vector2.new(0, 1)
popup.Position = CARD_POS
popup.Size = CARD_SIZE
popup.BackgroundColor3 = POPUP_BG
popup.BorderSizePixel = 0
popup.GroupTransparency = 1
popup.Visible = false
popup.ZIndex = 5
popup.Parent = window
corner(popup)
stroke(popup, BORDER, 1, 0)

-- profile picture (smooth square)
local avatar = Instance.new("ImageLabel")
avatar.Position = UDim2.fromOffset(16, 16)
avatar.Size = UDim2.fromOffset(56, 56)
avatar.BackgroundColor3 = CARD_BG
avatar.BorderSizePixel = 0
avatar.Image = ""
avatar.Parent = popup
corner(avatar, 14)

task.spawn(function()
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and url then
		if avatar.Parent then avatar.Image = url end
		if cardAvatar.Parent then cardAvatar.Image = url end
	end
end)

-- display name + username
label(popup, player.DisplayName, UDim2.fromOffset(84, 22), UDim2.fromOffset(164, 20),
	Enum.Font.GothamMedium, 14, TEXT_COLOR)
label(popup, "@" .. player.Name, UDim2.fromOffset(84, 44), UDim2.fromOffset(164, 16),
	Enum.Font.Gotham, 12, DIM_TEXT)

-- ID
local idCard = Instance.new("Frame")
idCard.Position = UDim2.fromOffset(16, 88)
idCard.Size = UDim2.fromOffset(232, 44)
idCard.BackgroundColor3 = CARD_BG
idCard.BorderSizePixel = 0
idCard.Parent = popup
corner(idCard)

label(idCard, "User ID", UDim2.fromOffset(12, 6), UDim2.fromOffset(120, 12),
	Enum.Font.Gotham, 11, DIM_TEXT)
label(idCard, tostring(player.UserId), UDim2.fromOffset(12, 21), UDim2.fromOffset(208, 18),
	Enum.Font.GothamMedium, 13, TEXT_COLOR)

local popupOpen, popupToken = false, 0

local function openPopup()
	popupOpen = true
	popupToken += 1
	popup.Position = CARD_POS
	popup.Size = CARD_SIZE
	popup.GroupTransparency = 1
	popup.Visible = true
	TweenService:Create(popup, EXPAND, {
		Position = POP_POS,
		Size = POP_SIZE,
		GroupTransparency = 0,
	}):Play()
end

local function closePopup()
	if not popupOpen then return end
	popupOpen = false
	popupToken += 1
	local token = popupToken
	TweenService:Create(popup, COLLAPSE, {
		Position = CARD_POS,
		Size = CARD_SIZE,
		GroupTransparency = 1,
	}):Play()
	task.delay(0.24, function()
		if token == popupToken then popup.Visible = false end
	end)
end

card.Activated:Connect(function()
	if popupOpen then closePopup() else openPopup() end
end)

-- clicking anywhere else closes it
popup.MouseEnter:Connect(function() hover.popup = true end)
popup.MouseLeave:Connect(function() hover.popup = false end)

UserInputService.InputBegan:Connect(function(input)
	if not popupOpen then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if hover.popup or hover.card then return end
	closePopup()
end)

-- ═══ WINDOW STATE ═══════════════════════════════════════════════════════════════════════════════
local minimized, maximized = false, false

-- ═══ CONTROL CLUSTER (top right) ════════════════════════════════════════════════════════════════
local BTN_W, BTN_H, GAP, PAD = 30, 24, 2, 3

local cluster = Instance.new("Frame")
cluster.Name = "Controls"
cluster.AnchorPoint = Vector2.new(1, 0)
cluster.Position = UDim2.new(1, -8, 0, (BAR_H - (BTN_H + PAD * 2)) / 2)
cluster.Size = UDim2.fromOffset(BTN_W * 3 + GAP * 2 + PAD * 2, BTN_H + PAD * 2)
cluster.BackgroundColor3 = CLUSTER_BG
cluster.BorderSizePixel = 0
cluster.Parent = bar
corner(cluster, RADIUS + 1)

local function makeControl(kind, index, hoverColor)
	local btn = Instance.new("TextButton")
	btn.Name = kind
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Position = UDim2.fromOffset(PAD + (index - 1) * (BTN_W + GAP), PAD)
	btn.Size = UDim2.fromOffset(BTN_W, BTN_H)
	btn.BackgroundColor3 = hoverColor
	btn.BackgroundTransparency = 1 -- the highlighted square only shows on hover
	btn.BorderSizePixel = 0
	btn.Parent = cluster
	corner(btn, 3)

	-- icons are drawn with frames so they stay crisp
	local parts = {}
	local function line(w, h, rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = rot or 0
		f.BackgroundColor3 = ICON
		f.BorderSizePixel = 0
		f.Parent = btn
		corner(f, 1)
		table.insert(parts, { f, "BackgroundColor3" })
	end

	if kind == "minimize" then
		line(10, 2)
	elseif kind == "maximize" then
		local sq = Instance.new("Frame")
		sq.AnchorPoint = Vector2.new(0.5, 0.5)
		sq.Position = UDim2.fromScale(0.5, 0.5)
		sq.Size = UDim2.fromOffset(10, 10)
		sq.BackgroundTransparency = 1
		sq.BorderSizePixel = 0
		sq.Parent = btn
		corner(sq, 2)
		local s = stroke(sq, ICON, 1.5, 0)
		table.insert(parts, { s, "Color" })
	else -- close
		line(14, 2, 45)
		line(14, 2, -45)
	end

	local hovering = false
	local function paint(hover, pressed)
		local bgT = hover and (pressed and 0.35 or 0) or 1
		TweenService:Create(btn, FAST, { BackgroundTransparency = bgT }):Play()
		local color = hover and ICON_HOVER or ICON
		for _, p in ipairs(parts) do
			TweenService:Create(p[1], FAST, { [p[2]] = color }):Play()
		end
	end

	btn.MouseEnter:Connect(function() hovering = true; paint(true, false) end)
	btn.MouseLeave:Connect(function() hovering = false; paint(false, false) end)
	btn.MouseButton1Down:Connect(function() paint(true, true) end)
	btn.MouseButton1Up:Connect(function() paint(hovering, false) end)
	return btn
end

local minimizeBtn = makeControl("minimize", 1, HOVER_GREY)
local maximizeBtn = makeControl("maximize", 2, HOVER_GREY)
local closeBtn    = makeControl("close",    3, HOVER_RED)

-- ═══ PAGE TITLE + BACK ARROW ════════════════════════════════════════════════════════════════════
-- title card: same colour as the sidebar, same corners as the window controls, dim caption + name
local titleChip = Instance.new("Frame")
titleChip.Name = "TitleCard"
titleChip.Position = UDim2.fromOffset(SIDEBAR_W_MIN + 14, 6)
titleChip.Size = UDim2.fromOffset(116, 36)
titleChip.BackgroundColor3 = SIDEBAR_BG -- same colour as the sidebar
titleChip.BorderSizePixel = 0
titleChip.Parent = window
corner(titleChip, RADIUS + 1)   -- same corners as the window controls

label(titleChip, "Tab", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 12),
	Enum.Font.Gotham, 11, DIM_TEXT)
local titleLabel = label(titleChip, "Main", UDim2.fromOffset(12, 18), UDim2.new(1, -24, 0, 16),
	Enum.Font.GothamMedium, 13, TEXT_COLOR)

-- back arrow: small square, right under the minimize / maximize / close cluster
local backBtn = Instance.new("TextButton")
backBtn.Name = "Back"
backBtn.AutoButtonColor = false
backBtn.Text = ""
backBtn.AnchorPoint = Vector2.new(1, 0)
backBtn.Position = UDim2.new(1, -8, 0, BAR_H + 2)
backBtn.Size = UDim2.fromOffset(24, 24)
backBtn.BackgroundColor3 = CLUSTER_BG
backBtn.BorderSizePixel = 0
backBtn.Visible = false
backBtn.ZIndex = 3
backBtn.Parent = window
corner(backBtn, RADIUS + 1)

do
	-- arrow drawn with frames: a shaft plus two angled strokes forming the arrowhead
	local arrowParts = {}
	local function stroke_(w, x, y, rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, x, 0.5, y)
		f.Size = UDim2.fromOffset(w, 2)
		f.Rotation = rot
		f.BackgroundColor3 = ICON
		f.BorderSizePixel = 0
		f.ZIndex = 4
		f.Parent = backBtn
		corner(f, 1)
		table.insert(arrowParts, f)
	end
	stroke_(10, -1, 0, 0)       -- shaft
	stroke_(5, 2.3, -2, 45)     -- head, upper stroke (tip points right)
	stroke_(5, 2.3, 2, -45)     -- head, lower stroke

	backBtn.MouseEnter:Connect(function()
		TweenService:Create(backBtn, FAST, { BackgroundColor3 = HOVER_GREY }):Play()
		for _, f in ipairs(arrowParts) do
			TweenService:Create(f, FAST, { BackgroundColor3 = ICON_HOVER }):Play()
		end
	end)
	backBtn.MouseLeave:Connect(function()
		TweenService:Create(backBtn, FAST, { BackgroundColor3 = CLUSTER_BG }):Play()
		for _, f in ipairs(arrowParts) do
			TweenService:Create(f, FAST, { BackgroundColor3 = ICON }):Play()
		end
	end)
end

local titleToken = 0

showPage = function(name)
	if name == currentPage then return end
	currentPage = name
	mainPage.Visible = (name == "Main")
	settingsPage.Visible = (name == "Settings")
	backBtn.Visible = (name ~= "Main") and not minimized

	-- fade the title out, swap the text, fade it back in
	titleToken += 1
	local token = titleToken
	TweenService:Create(titleLabel, FAST, { TextTransparency = 1 }):Play()
	task.delay(0.12, function()
		if token ~= titleToken then return end
		titleLabel.Text = name
		TweenService:Create(titleLabel, FAST, { TextTransparency = 0 }):Play()
	end)
end

backBtn.Activated:Connect(function()
	showPage("Main")
end)

-- ═══ SETTINGS: UI TOGGLE KEYBIND ════════════════════════════════════════════════════════════════
local keybind = Enum.KeyCode.RightShift
local listening = false
local uiHidden = false
local animToken = 0

local settingsHeader = label(settingsPage, "KEYBINDS", UDim2.fromOffset(2, 6), UDim2.fromOffset(200, 14),
	Enum.Font.GothamMedium, 11, DIM_TEXT)

local keyRow = Instance.new("Frame")
keyRow.Name = "ToggleKeybindRow"
keyRow.Position = UDim2.fromOffset(0, 28)
keyRow.Size = UDim2.new(1, -8, 0, 54)
keyRow.BackgroundColor3 = SIDEBAR_BG
keyRow.BorderSizePixel = 0
keyRow.Parent = settingsPage
corner(keyRow, RADIUS + 2)

label(keyRow, "UI Toggle Keybind", UDim2.fromOffset(14, 10), UDim2.new(1, -150, 0, 16),
	Enum.Font.GothamMedium, 13, TEXT_COLOR)
label(keyRow, "Hide or show the whole window", UDim2.fromOffset(14, 29), UDim2.new(1, -150, 0, 14),
	Enum.Font.Gotham, 11, DIM_TEXT)

local keyBtn = Instance.new("TextButton")
keyBtn.Name = "KeybindButton"
keyBtn.AutoButtonColor = false
keyBtn.AnchorPoint = Vector2.new(1, 0.5)
keyBtn.Position = UDim2.new(1, -12, 0.5, 0)
keyBtn.Size = UDim2.fromOffset(104, 28)
keyBtn.BackgroundColor3 = CLUSTER_BG
keyBtn.BorderSizePixel = 0
keyBtn.Font = Enum.Font.GothamMedium
keyBtn.TextSize = 12
keyBtn.TextColor3 = ICON_HOVER
keyBtn.Text = keybind.Name
keyBtn.TextTruncate = Enum.TextTruncate.AtEnd
keyBtn.Parent = keyRow
corner(keyBtn, RADIUS + 1)

local function paintKeyBtn(hover)
	local bg = (listening or hover) and HOVER_GREY or CLUSTER_BG
	TweenService:Create(keyBtn, FAST, { BackgroundColor3 = bg }):Play()
end

keyBtn.MouseEnter:Connect(function() paintKeyBtn(true) end)
keyBtn.MouseLeave:Connect(function() paintKeyBtn(false) end)

keyBtn.Activated:Connect(function()
	listening = not listening
	keyBtn.Text = listening and "Press a key..." or keybind.Name
	paintKeyBtn(true)
end)

-- hide / show animation: the window shrinks a little and fades out, and pops back in
local HIDE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local SHOW_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setUIVisible(show)
	if uiHidden == (not show) then return end
	uiHidden = not show
	animToken += 1
	local token = animToken

	if show then
		window.Visible = true
		TweenService:Create(windowScale, SHOW_INFO, { Scale = 1 }):Play()
		TweenService:Create(window, FADE_IN, { GroupTransparency = 0 }):Play()
	else
		closePopup()
		TweenService:Create(windowScale, HIDE_INFO, { Scale = 0.9 }):Play()
		TweenService:Create(window, HIDE_INFO, { GroupTransparency = 1 }):Play()
		task.delay(HIDE_INFO.Time + 0.02, function()
			if token == animToken then window.Visible = false end
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if listening then
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		listening = false
		if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
			keybind = input.KeyCode -- Escape cancels and keeps the old key
		end
		keyBtn.Text = keybind.Name
		paintKeyBtn(false)
		return
	end
	if processed then return end
	if input.KeyCode == keybind then
		setUIVisible(uiHidden) -- hidden -> show, shown -> hide
	end
end)

-- ═══ WINDOW BEHAVIOUR ═══════════════════════════════════════════════════════════════════════════
local normalSize, normalPos = WINDOW_SIZE, window.Position

local function setBodyVisible(visible)
	sidebar.Visible = visible
	content.Visible = visible
	card.Visible = visible
	iconSlot.Visible = visible
	logo.Visible = visible
	backBtn.Visible = visible and currentPage ~= "Main"
end

local function restore()
	minimized, maximized = false, false
	setBodyVisible(true)
	TweenService:Create(window, SMOOTH, { Size = normalSize, Position = normalPos }):Play()
end

minimizeBtn.Activated:Connect(function()
	if minimized then
		restore()
		return
	end
	closePopup()
	if not maximized then
		normalSize, normalPos = window.Size, window.Position
	end
	minimized, maximized = true, false
	setBodyVisible(false)
	TweenService:Create(window, SMOOTH, {
		Size = UDim2.fromOffset(normalSize.X.Offset, BAR_H),
		Position = normalPos,
	}):Play()
end)

maximizeBtn.Activated:Connect(function()
	if maximized or minimized then
		restore()
		return
	end
	normalSize, normalPos = window.Size, window.Position
	maximized = true
	TweenService:Create(window, SMOOTH, {
		Size = UDim2.new(1, -48, 1, -48),
		Position = UDim2.fromScale(0.5, 0.5),
	}):Play()
end)

-- ═══ UNLOAD CONFIRMATION (pops up when you press X) ═════════════════════════════════════════════
local confirmOpen, confirmToken = false, 0

local overlay = Instance.new("CanvasGroup") -- dims the window; everything inside fades together
overlay.Name = "ConfirmOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel = 0
overlay.Active = true            -- swallows clicks so nothing underneath can be pressed
overlay.GroupTransparency = 1
overlay.Visible = false
overlay.ZIndex = 30
overlay.Parent = window
corner(overlay, RADIUS)

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromOffset(300, 128)
dialog.BackgroundColor3 = SIDEBAR_BG -- same colour as the sidebar
dialog.BorderSizePixel = 0
dialog.ZIndex = 31
dialog.Parent = overlay
corner(dialog, RADIUS + 1)
stroke(dialog, BORDER, 1, 0)

local dialogScale = Instance.new("UIScale")
dialogScale.Scale = 0.9
dialogScale.Parent = dialog

-- same text style as the profile / tab cards: dim caption over a brighter line
local dialogCaption = label(dialog, "Confirm", UDim2.fromOffset(18, 14), UDim2.fromOffset(264, 12),
	Enum.Font.Gotham, 11, DIM_TEXT)
dialogCaption.ZIndex = 32

local dialogText = label(dialog, "Are you sure you want to unload the script?",
	UDim2.fromOffset(18, 30), UDim2.fromOffset(264, 36), Enum.Font.GothamMedium, 13, TEXT_COLOR)
dialogText.TextWrapped = true
dialogText.TextTruncate = Enum.TextTruncate.None
dialogText.TextYAlignment = Enum.TextYAlignment.Top
dialogText.ZIndex = 32

-- the buttons sit in a dark tray with the same padding and corners as the window controls
local trayFrame = Instance.new("Frame")
trayFrame.Name = "ButtonTray"
trayFrame.Position = UDim2.fromOffset(18, 78)
trayFrame.Size = UDim2.fromOffset(264, 24 + PAD * 2)
trayFrame.BackgroundColor3 = CLUSTER_BG
trayFrame.BorderSizePixel = 0
trayFrame.ZIndex = 32
trayFrame.Parent = dialog
corner(trayFrame, RADIUS + 1)

local function dialogButton(text, x, hoverColor)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = ICON
	b.Position = UDim2.fromOffset(x, PAD)
	b.Size = UDim2.fromOffset(127, 24)
	b.BackgroundColor3 = hoverColor
	b.BackgroundTransparency = 1 -- the highlighted square only shows on hover, like the controls
	b.BorderSizePixel = 0
	b.ZIndex = 33
	b.Parent = trayFrame
	corner(b, 3)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = 0, TextColor3 = ICON_HOVER }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundTransparency = 1, TextColor3 = ICON }):Play()
	end)
	return b
end

local yesBtn = dialogButton("Yes", PAD, HOVER_RED)
local noBtn  = dialogButton("No", PAD + 127 + 4, HOVER_GREY)

local CONFIRM_IN  = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CONFIRM_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function showConfirm()
	if confirmOpen then return end
	confirmOpen = true
	confirmToken += 1
	closePopup()
	overlay.GroupTransparency = 1
	dialogScale.Scale = 0.9
	overlay.Visible = true
	TweenService:Create(overlay, FAST, { GroupTransparency = 0 }):Play()
	TweenService:Create(dialogScale, CONFIRM_IN, { Scale = 1 }):Play()
end

local function hideConfirm()
	if not confirmOpen then return end
	confirmOpen = false
	confirmToken += 1
	local token = confirmToken
	TweenService:Create(overlay, CONFIRM_OUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(dialogScale, CONFIRM_OUT, { Scale = 0.92 }):Play()
	task.delay(CONFIRM_OUT.Time + 0.02, function()
		if token == confirmToken then overlay.Visible = false end
	end)
end

closeBtn.Activated:Connect(function()
	if minimized then restore() end -- the dialog needs the full window to sit in
	showConfirm()
end)

yesBtn.Activated:Connect(function()
	confirmToken += 1
	TweenService:Create(window, CONFIRM_OUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(windowScale, CONFIRM_OUT, { Scale = 0.92 }):Play()
	task.delay(CONFIRM_OUT.Time + 0.02, function()
		gui:Destroy()
	end)
end)

noBtn.Activated:Connect(hideConfirm)

-- drag the top bar (or the empty sidebar) to move; disabled while maximized
local dragging, dragStart, startPos = false, nil, nil

local function bindDrag(handle)
	handle.InputBegan:Connect(function(input)
		if maximized then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not minimized then normalPos = window.Position end
				end
			end)
		end
	end)
end
bindDrag(bar)
bindDrag(sidebar)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local d = input.Position - dragStart
		window.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y
		)
		normalPos = window.Position
	end
end)
