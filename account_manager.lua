--[[
    account_manager.lua  -  Account Manager (module)

    The first screen on EVERY client that runs the main script. It shows every account that is connected through the
    website in this server, plus an Attach button: whichever account presses Attach becomes the owner.
    No sidebar and no menu tabs here - the real UI (menu.lua) opens after the owner pressed Start.

    am = ctor(ctx)
    ctx (all optional)
      player            the local player
      position          UDim2: where the window opens
      onAttach()        Attach was pressed
      onStart()         owner pressed Start (after picking who joins)
      onBack()          owner pressed Back (undo Attach for everybody)
      onToggle(userId)  owner clicked an account: switch it between Alt / Leave out
      onUnload()        the user pressed X and confirmed "Are you sure you want to unload the script?" (Yes)

    am API
      am.setAccounts(rows, opts)  rows = {{UserId, Name, DisplayName, Role}}   Role: "Owner" | "Alt" | "Skip" | nil
                                  opts = {mode = "select" | "follower" | "setup", choices = {[userId] = "Alt"|"Skip"},
                                          starting = bool}
                                  returns true when somebody else already is the owner
      am.resetAccounts()          forget the row animations (after a reset)
      am.setMessage(text|nil)     big centered message instead of the list ("Connecting...", errors)
      am.hide() / am.show()       fade the window out / in
      am.getPosition()            window position (so menu.lua can open in the same spot)
      am.destroy()                remove the UI and every connection
      am.gui, am.window
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	ctx = ctx or {}
	local player = ctx.player or Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	do
		local old = playerGui:FindFirstChild("AccountManagerUI")
		if old then old:Destroy() end
	end

	local ui = {}
	local conns = {}
	local function connectInput(signal, fn)
		table.insert(conns, signal:Connect(fn))
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

	local WINDOW_SIZE = UDim2.fromOffset(640, 470)
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

	-- ═══ WINDOW ═════════════════════════════════════════════════════════════════════════════════════
	local gui = Instance.new("ScreenGui")
	gui.Name = "AccountManagerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local window = Instance.new("CanvasGroup") -- CanvasGroup: the whole window fades as one piece
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = ctx.position or UDim2.fromScale(0.5, 0.5)
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

	-- ═══ CONTENT ════════════════════════════════════════════════════════════════════════════════════
	local content = Instance.new("Frame")
	content.Name = "AccountManagerPage"
	content.Position = UDim2.fromOffset(12, BAR_H)
	content.Size = UDim2.new(1, -24, 1, -(BAR_H + 12))
	content.BackgroundTransparency = 1
	content.Parent = window
	local accountsPage = content

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


	-- ═══ WINDOW BEHAVIOUR ═══════════════════════════════════════════════════════════════════════════
	local normalSize, normalPos = WINDOW_SIZE, window.Position

	local function restore()
		minimized, maximized = false, false
		content.Visible = true
		TweenService:Create(window, SMOOTH, { Size = normalSize, Position = normalPos }):Play()
	end

	minimizeBtn.Activated:Connect(function()
		if minimized then
			restore()
			return
		end
		if not maximized then
			normalSize, normalPos = window.Size, window.Position
		end
		minimized, maximized = true, false
		content.Visible = false
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

	-- hide / show animation: the window shrinks a little and fades out, and pops back in
	local HIDE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local SHOW_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local FADE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local uiHidden, animToken = false, 0

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
			TweenService:Create(windowScale, HIDE_INFO, { Scale = 0.9 }):Play()
			TweenService:Create(window, HIDE_INFO, { GroupTransparency = 1 }):Play()
			task.delay(HIDE_INFO.Time + 0.02, function()
				if token == animToken then window.Visible = false end
			end)
		end
	end

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
			if ctx.onUnload then
				local ok, err = pcall(ctx.onUnload)
				if not ok then
					warn("[yur1] unload failed: " .. tostring(err))
					ui.destroy()
				end
			else
				ui.destroy()
			end
		end)
	end)

	noBtn.Activated:Connect(hideConfirm)


	-- drag the top bar to move; disabled while maximized
	local dragging, dragStart, startPos = false, nil, nil

	bar.InputBegan:Connect(function(input)
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

	connectInput(UserInputService.InputChanged, function(input)
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

	-- ═══ ACCOUNT MANAGER PAGE ═══════════════════════════════════════════════════════════════════════
	do
		local GREEN = Color3.fromRGB(152, 212, 172)       -- calm light green: attached / selected
		local ROW_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local BOTTOM_H = 112
		local page = accountsPage

		label(page, "Account Manager", UDim2.fromOffset(4, 2), UDim2.new(1, -8, 0, 24),
			Enum.Font.GothamMedium, 18, TEXT_COLOR)
		label(page, "Every account running the script in this server shows up here",
			UDim2.fromOffset(4, 28), UDim2.new(1, -8, 0, 16), Enum.Font.Gotham, 12, DIM_TEXT)

		-- account list
		local list = Instance.new("ScrollingFrame")
		list.Name = "Accounts"
		list.Position = UDim2.fromOffset(0, 56)
		list.Size = UDim2.new(1, 0, 1, -(56 + BOTTOM_H + 8))
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 3
		list.ScrollBarImageColor3 = Color3.fromRGB(62, 62, 68)
		list.CanvasSize = UDim2.new()
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = page

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list

		local msg = label(page, "Connecting to the website...", UDim2.fromOffset(0, 56),
			UDim2.new(1, 0, 1, -(56 + BOTTOM_H + 8)), Enum.Font.GothamMedium, 14, DIM_TEXT, Enum.TextXAlignment.Center)
		msg.TextTruncate = Enum.TextTruncate.None

		-- bottom: count + progress bar + hint + buttons
		local bottom = Instance.new("Frame")
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.new(0, 0, 1, 0)
		bottom.Size = UDim2.new(1, 0, 0, BOTTOM_H)
		bottom.BackgroundTransparency = 1
		bottom.Parent = page

		local countLabel = label(bottom, "", UDim2.fromOffset(4, 0), UDim2.new(1, -8, 0, 14),
			Enum.Font.Gotham, 11, DIM_TEXT)

		local track = Instance.new("Frame")
		track.Position = UDim2.fromOffset(0, 20)
		track.Size = UDim2.new(1, 0, 0, 6)
		track.BackgroundColor3 = CARD_BG
		track.BorderSizePixel = 0
		track.Parent = bottom
		corner(track, 3)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = GREEN
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 3)

		local hint = label(bottom, "", UDim2.fromOffset(4, 34), UDim2.new(1, -8, 0, 30),
			Enum.Font.GothamMedium, 12, TEXT_COLOR)
		hint.TextWrapped = true
		hint.TextTruncate = Enum.TextTruncate.None
		hint.TextYAlignment = Enum.TextYAlignment.Top

		local function actionButton(text, pos, size)
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.Text = text
			b.Font = Enum.Font.GothamMedium
			b.TextSize = 13
			b.TextColor3 = ICON_HOVER
			b.Position = pos
			b.Size = size
			b.BackgroundColor3 = CLUSTER_BG
			b.BorderSizePixel = 0
			b.Parent = bottom
			corner(b, RADIUS + 1)
			b.MouseEnter:Connect(function()
				if b.Interactable then TweenService:Create(b, FAST, { BackgroundColor3 = HOVER_GREY }):Play() end
			end)
			b.MouseLeave:Connect(function()
				TweenService:Create(b, FAST, { BackgroundColor3 = CLUSTER_BG }):Play()
			end)
			b.MouseButton1Down:Connect(function()
				if b.Interactable then TweenService:Create(b, FAST, { BackgroundColor3 = Color3.fromRGB(50, 50, 55) }):Play() end
			end)
			b.MouseButton1Up:Connect(function()
				if b.Interactable then TweenService:Create(b, FAST, { BackgroundColor3 = HOVER_GREY }):Play() end
			end)
			return b
		end

		local attachBtn = actionButton("Attach", UDim2.fromOffset(0, 72), UDim2.new(1, 0, 0, 36))
		local startBtn  = actionButton("Start", UDim2.fromOffset(0, 72), UDim2.new(0.5, -4, 0, 36))
		local backBtn2  = actionButton("Back", UDim2.new(0.5, 4, 0, 72), UDim2.new(0.5, -4, 0, 36))
		startBtn.Visible, backBtn2.Visible = false, false
		attachBtn.Interactable = false -- until the website answered
		attachBtn.TextColor3 = DIM_TEXT

		attachBtn.Activated:Connect(function() if ctx.onAttach then ctx.onAttach() end end)
		startBtn.Activated:Connect(function() if ctx.onStart then ctx.onStart() end end)
		backBtn2.Activated:Connect(function() if ctx.onBack then ctx.onBack() end end)

		-- profile pictures
		local thumbCache = {}
		local function setAvatar(img, userId)
			if thumbCache[userId] then img.Image = thumbCache[userId] return end
			task.spawn(function()
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				end)
				if ok and url then
					thumbCache[userId] = url
					if img.Parent then img.Image = url end
				end
			end)
		end

		-- one account row: picture, name, @username, status. tone "green" = attached / selected.
		-- toggle = click handler (owner's Alt / Leave out switch)
		local function buildRow(acc, order, statusText, tone, anim, toggle)
			local green = (tone == "green")

			local row = Instance.new("CanvasGroup")
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -6, 0, 46)
			row.BackgroundColor3 = SIDEBAR_BG
			row.BorderSizePixel = 0
			row.GroupTransparency = (anim == "in") and 1 or 0
			row.Parent = list
			corner(row, RADIUS + 2)
			stroke(row, BORDER, 1, 0)
			if anim == "in" then
				TweenService:Create(row, ROW_FADE, { GroupTransparency = 0 }):Play()
			elseif anim == "flash" then
				row.BackgroundColor3 = Color3.fromRGB(34, 44, 38)
				TweenService:Create(row, ROW_FADE, { BackgroundColor3 = SIDEBAR_BG }):Play()
			end

			local avatar = Instance.new("ImageLabel")
			avatar.Position = UDim2.fromOffset(8, 7)
			avatar.Size = UDim2.fromOffset(32, 32)
			avatar.BackgroundColor3 = CARD_BG
			avatar.BorderSizePixel = 0
			avatar.Parent = row
			corner(avatar, 8)
			setAvatar(avatar, acc.UserId)

			local shown = (acc.DisplayName and acc.DisplayName ~= "") and acc.DisplayName or acc.Name
			label(row, shown .. (acc.UserId == player.UserId and "  (you)" or ""), UDim2.fromOffset(50, 7),
				UDim2.new(1, -190, 0, 16), Enum.Font.GothamMedium, 13, TEXT_COLOR)
			label(row, "@" .. tostring(acc.Name), UDim2.fromOffset(50, 25), UDim2.new(1, -190, 0, 14),
				Enum.Font.Gotham, 11, DIM_TEXT)

			if toggle then
				local b = Instance.new("TextButton")
				b.AutoButtonColor = false
				b.Position = UDim2.new(1, -104, 0.5, -13)
				b.Size = UDim2.fromOffset(94, 26)
				b.BackgroundColor3 = CLUSTER_BG
				b.BorderSizePixel = 0
				b.Font = Enum.Font.GothamMedium
				b.Text = statusText
				b.TextSize = 12
				b.TextColor3 = green and GREEN or DIM_TEXT
				b.Parent = row
				corner(b, RADIUS + 1)
				b.MouseEnter:Connect(function() TweenService:Create(b, FAST, { BackgroundColor3 = HOVER_GREY }):Play() end)
				b.MouseLeave:Connect(function() TweenService:Create(b, FAST, { BackgroundColor3 = CLUSTER_BG }):Play() end)
				b.Activated:Connect(toggle)
			else
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.new(1, -18, 0.5, 0)
				dot.Size = UDim2.fromOffset(8, 8)
				dot.BackgroundColor3 = green and GREEN or Color3.fromRGB(70, 70, 76)
				dot.BorderSizePixel = 0
				dot.Parent = row
				corner(dot, 4)

				local st = label(row, statusText, UDim2.new(1, -132, 0, 0), UDim2.fromOffset(104, 46),
					Enum.Font.GothamMedium, 12, green and GREEN or DIM_TEXT, Enum.TextXAlignment.Right)
				st.TextTruncate = Enum.TextTruncate.None
			end
		end

		local knownRows, lastSignature = {}, nil
		local function animFor(key, status)
			local prev = knownRows[key]
			knownRows[key] = status
			if prev == nil then return "in" end
			if prev ~= status then return "flash" end
			return nil
		end

		local connected = false

		function ui.setMessage(text)
			local on = (text ~= nil and text ~= "")
			msg.Visible = on
			list.Visible = not on
			if on then msg.Text = text end
		end

		function ui.setAccounts(rows, opts)
			opts = opts or {}
			local mode = opts.mode or "select"
			local choices = opts.choices or {}
			local starting = opts.starting == true
			local me = player.UserId
			connected = true
			ui.setMessage(nil)

			local attached, altsChosen, takenByOther, ownerName = 0, 0, false, nil
			local parts = { mode, starting and "1" or "0" }
			for _, acc in ipairs(rows) do
				if acc.Role == "Owner" or acc.Role == "Alt" then attached += 1 end
				if acc.Role == "Owner" then
					ownerName = (acc.DisplayName ~= nil and acc.DisplayName ~= "") and acc.DisplayName or acc.Name
					if acc.UserId ~= me then takenByOther = true end
				end
				local choice = ""
				if mode == "setup" and acc.UserId ~= me then
					choice = choices[acc.UserId] or "Alt"
					if choice == "Alt" then altsChosen += 1 end
				end
				table.insert(parts, tostring(acc.UserId) .. ":" .. tostring(acc.Name) .. ":" .. tostring(acc.Role) .. ":" .. choice)
			end

			-- count + progress bar
			local total, shown, countText = #rows, attached, nil
			if mode == "setup" then
				shown = 1 + altsChosen
				countText = shown .. " / " .. total .. " selected"
			else
				countText = shown .. " / " .. total .. " attached"
			end
			countLabel.Text = countText
			TweenService:Create(fill, ROW_FADE, {
				Size = UDim2.fromScale(total > 0 and math.clamp(shown / total, 0, 1) or 0, 1),
			}):Play()

			-- hint + buttons
			local setup = (mode == "setup")
			attachBtn.Visible = not setup
			startBtn.Visible, backBtn2.Visible = setup, setup
			if setup then
				hint.Text = "Pick who joins. Click an account to leave it out, then press Start."
				startBtn.Text = starting and "Starting..." or ("Start with " .. shown .. (shown == 1 and " account" or " accounts"))
			elseif mode == "follower" or takenByOther then
				hint.Text = "Waiting for " .. (ownerName or "the owner") .. " to pick the accounts"
			else
				hint.Text = "Press Attach on the account you control.\nIt becomes the owner and picks the other accounts."
			end
			attachBtn.Interactable = not takenByOther
			attachBtn.Text = takenByOther and "Owner chosen" or "Attach"
			attachBtn.TextColor3 = takenByOther and DIM_TEXT or ICON_HOVER

			local signature = table.concat(parts, "|")
			if signature == lastSignature then return takenByOther end
			lastSignature = signature

			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("CanvasGroup") then child:Destroy() end
			end
			for i, acc in ipairs(rows) do
				if setup and acc.UserId ~= me then
					local isAlt = ((choices[acc.UserId] or "Alt") == "Alt")
					buildRow(acc, i, isAlt and "Alt" or "Leave out", isAlt and "green" or "dim",
						animFor("row:" .. acc.UserId, isAlt and "Alt" or "Skip"), function()
							if ctx.onToggle then ctx.onToggle(acc.UserId) end
						end)
				else
					local status, tone = (mode == "follower") and "Waiting" or "Not attached", "dim"
					if acc.Role == "Owner" then status, tone = "Owner", "green"
					elseif acc.Role == "Alt" then status, tone = "Alt", "green"
					elseif acc.Role == "Skip" then status = "Left out" end
					buildRow(acc, i, status, tone, animFor("row:" .. acc.UserId, status))
				end
			end
			return takenByOther
		end

		function ui.resetAccounts()
			knownRows, lastSignature = {}, nil
		end
	end

	-- ═══ API ════════════════════════════════════════════════════════════════════════════════════════
	function ui.hide() setUIVisible(false) end
	function ui.show() setUIVisible(true) end
	function ui.getPosition() return window.Position end

	function ui.destroy()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		table.clear(conns)
		pcall(function() gui:Destroy() end)
	end

	ui.gui, ui.window = gui, window

	-- opening animation: the window pops in
	windowScale.Scale = 0.92
	window.GroupTransparency = 1
	TweenService:Create(windowScale, SHOW_INFO, { Scale = 1 }):Play()
	TweenService:Create(window, FADE_IN, { GroupTransparency = 0 }):Play()

	return ui
end
