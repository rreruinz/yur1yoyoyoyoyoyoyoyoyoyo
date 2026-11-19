-- settingstab.lua  (Y1 Settings tab, lives in tabs/ next to hometab.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- ui.lua calls  SettingsModule.build(container, T, H, ctx)  (main.lua loads it as modules.SettingsTab).
--   ctx.Win = the window. ctx.HideKey = the key the window starts with (default RightShift).
-- One panel, three sections with a red divider between them:
--   Toggle UI : a keybind (click it, press a key; Backspace = no key) that hides / shows the window
--   Watermark : Show Watermark switch
--   Script    : Unload Script button (click twice to confirm)
-- main.lua gives ui.lua an unused HideKey on purpose, so this tab is the only thing that hides the window.

local SettingsTab = {}

function SettingsTab.build(container, T, H, ctx)
	local TweenService = game:GetService("TweenService")
	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST, SMOOTH = T.FAST, T.SMOOTH

	local GAP, HEAD = 14, 38
	local BODY_PAD_X, BODY_PAD_TOP, BODY_PAD_BOTTOM = 14, 16, 18
	local SECTION_GAP, HEADER_H = 18, 28
	local BOX_PAD, BOX_GAP, ROW_H = 10, 9, 28
	local MAX_W = 460          -- the sections stay this wide in the middle of the big panel
	local DD_W = 116

	local UserInputService = game:GetService("UserInputService")
	local win = nil
	local hideKey = Enum.KeyCode.RightShift
	if type(ctx) == "table" then
		win = ctx.Win
		if typeof(ctx.HideKey) == "EnumItem" then
			hideKey = ctx.HideKey
		end
	end

	local root = new("Frame", {
		Name = "SettingsRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	-- a panel with a title bar and a scrolling body; returns the body
	local function makePanel(order, title, badgeText)
		local panel = new("Frame", {
			Name = title .. "Panel",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 1, -14),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, root)
		corner(panel, 6)
		stroke(panel, T.BORDER, 1, 0)
		label(panel, title, UDim2.fromOffset(14, 0), UDim2.new(1, -60, 0, HEAD),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR).ZIndex = 3
		local badge = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0, HEAD / 2),
			Size = UDim2.fromOffset(26, 20),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)
		corner(badge, 4)
		stroke(badge, T.BORDER, 1, 0)
		label(badge, badgeText, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
			Enum.Font.GothamMedium, 12, T.ICON, Enum.TextXAlignment.Center).ZIndex = 4
		new("Frame", {
			Position = UDim2.fromOffset(0, HEAD),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.ACCENT,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)
		local body = new("ScrollingFrame", {
			Name = "Body",
			Position = UDim2.fromOffset(0, HEAD + 1),
			Size = UDim2.new(1, 0, 1, -(HEAD + 1)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = T.BORDER,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			ZIndex = 2,
		}, panel)
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, SECTION_GAP),
		}, body)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, BODY_PAD_X),
			PaddingRight = UDim.new(0, BODY_PAD_X),
			PaddingTop = UDim.new(0, BODY_PAD_TOP),
			PaddingBottom = UDim.new(0, BODY_PAD_BOTTOM),
		}, body)
		return body
	end

	-- one section: name (+ optional switch) on top, one inset box under it. Returns { box, head, n }
	local function makeSection(body, order, title)
		local S = { n = 0 }
		local sec = new("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, body)
		new("UISizeConstraint", { MaxSize = Vector2.new(MAX_W, 100000) }, sec)
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}, sec)
		S.head = new("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, sec)
		label(S.head, title, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 1, 0), Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		S.box = new("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.WELL,
			BorderSizePixel = 0,
		}, sec)
		corner(S.box, 6)
		stroke(S.box, T.BORDER, 1, 0)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, BOX_PAD), PaddingRight = UDim.new(0, BOX_PAD),
			PaddingTop = UDim.new(0, BOX_PAD), PaddingBottom = UDim.new(0, BOX_PAD),
		}, S.box)
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, BOX_GAP),
		}, S.box)
		function S.order()
			S.n = S.n + 1
			return S.n
		end
		return S
	end

	local function makeSwitch(row, startOn, onChange)
		local on = startOn
		local track = new("TextButton", {
			AutoButtonColor = false, Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(38, 20),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, row)
		corner(track, 100)
		stroke(track, T.BORDER, 1, 0)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = T.DIM_TEXT,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)
		local function paint(animate)
			local pos, tc, kc = UDim2.new(0, 3, 0.5, 0), T.CLUSTER_BG, T.DIM_TEXT
			if on then
				pos, tc, kc = UDim2.new(0, 21, 0.5, 0), T.JOIN_BG, T.BLACK
			end
			if animate then
				TweenService:Create(knob, SMOOTH, { Position = pos }):Play()
			else
				knob.Position = pos
			end
			TweenService:Create(knob, FAST, { BackgroundColor3 = kc }):Play()
			TweenService:Create(track, FAST, { BackgroundColor3 = tc }):Play()
		end
		paint(false)
		track.Activated:Connect(function()
			on = not on
			paint(true)
			onChange(on)
		end)
	end

	local function toggleRow(S, title, startOn, onChange)
		local row = new("Frame", {
			LayoutOrder = S.order(),
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, S.box)
		label(row, title, UDim2.fromOffset(0, 0), UDim2.new(1, -50, 1, 0), Enum.Font.GothamMedium, 12, T.ICON)
		makeSwitch(row, startOn, onChange)
	end

	-- name on the left, a value on the right
	local function infoRow(S, title, value)
		local row = new("Frame", {
			LayoutOrder = S.order(),
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, S.box)
		label(row, title, UDim2.fromOffset(0, 0), UDim2.new(0.5, 0, 1, 0), Enum.Font.GothamMedium, 12, T.ICON)
		return label(row, value, UDim2.new(0.5, 0, 0, 0), UDim2.new(0.5, 0, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER, Enum.TextXAlignment.Right)
	end

	local function buttonRow(S, text, onClick)
		local b = new("TextButton", {
			LayoutOrder = S.order(),
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = text,
		}, S.box)
		corner(b, 5)
		stroke(b, T.BORDER, 1, 0)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		b.Activated:Connect(function()
			onClick(b)
		end)
		return b
	end

	---------------------------------------------------------------------
	-- THE PANEL
	---------------------------------------------------------------------
	local body = makePanel(1, "Settings", "3")

	local function divider(order)
		local d = new("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.ACCENT,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
		}, body)
		new("UISizeConstraint", { MaxSize = Vector2.new(MAX_W, 1) }, d)
	end

	local conns = {}

	-- TOGGLE UI: keybind
	local keySec = makeSection(body, 1, "Toggle UI")
	local keyRow = new("Frame", {
		LayoutOrder = keySec.order(),
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, keySec.box)
	label(keyRow, "Keybind", UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 1, 0),
		Enum.Font.GothamMedium, 12, T.ICON)
	local keyBtn = new("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(DD_W, ROW_H),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.ICON_HOVER,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, keyRow)
	corner(keyBtn, 5)
	local keyStroke = stroke(keyBtn, T.BORDER, 1, 0)
	keyBtn.MouseEnter:Connect(function()
		TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
	end)
	keyBtn.MouseLeave:Connect(function()
		TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
	end)
	local listening = false
	local function showKey()
		if hideKey then
			keyBtn.Text = hideKey.Name
		else
			keyBtn.Text = "None"
		end
		TweenService:Create(keyStroke, FAST, { Color = T.BORDER }):Play()
	end
	showKey()
	keyBtn.Activated:Connect(function()
		listening = not listening
		if listening then
			keyBtn.Text = "Press a key..."
			TweenService:Create(keyStroke, FAST, { Color = T.ACCENT }):Play()
		else
			showKey()
		end
	end)
	local hint = label(keySec.box, "Click the box, then press a key. Backspace clears it.", UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, 0), Enum.Font.Gotham, 11, T.DIM_TEXT)
	hint.LayoutOrder = keySec.order()
	hint.TextWrapped = true
	hint.AutomaticSize = Enum.AutomaticSize.Y

	-- the window counts as hidden when it is not on screen (works with the hide animation too)
	local function isHidden()
		local w = win and win.Window
		if not w then
			return false
		end
		return (not w.Visible) or w.GroupTransparency > 0.5
	end

	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if listening then
			listening = false
			if input.KeyCode == Enum.KeyCode.Backspace then
				hideKey = nil
			elseif input.KeyCode ~= Enum.KeyCode.Escape then
				hideKey = input.KeyCode
			end
			showKey()
			return
		end
		if processed or not hideKey then
			return
		end
		if input.KeyCode == hideKey and win and type(win.SetHidden) == "function" then
			win:SetHidden(not isHidden())
		end
	end)

	divider(2)

	-- WATERMARK
	local wmSec = makeSection(body, 3, "Watermark")
	local function findWatermark()
		if win and win.Gui then
			return win.Gui:FindFirstChild("Watermark", true)
		end
		return nil
	end
	local wmStart = findWatermark() ~= nil
	toggleRow(wmSec, "Show Watermark", wmStart, function(on)
		local wm = findWatermark()
		if wm then
			wm.Visible = on
		end
	end)
	if not wmStart then
		local n = label(wmSec.box, "The watermark is switched off in main.lua.", UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, 0), Enum.Font.Gotham, 11, T.DIM_TEXT)
		n.LayoutOrder = wmSec.order()
		n.TextWrapped = true
		n.AutomaticSize = Enum.AutomaticSize.Y
	end

	divider(4)

	-- SCRIPT: unload
	local scriptSec = makeSection(body, 5, "Script")
	local armed = false
	buttonRow(scriptSec, "Unload Script", function(b)
		if not armed then
			armed = true
			b.Text = "Click again to unload"
			b.TextColor3 = T.WARN
			task.delay(3, function()
				if armed and b.Parent then
					armed = false
					b.Text = "Unload Script"
					b.TextColor3 = T.ICON_HOVER
				end
			end)
			return
		end
		if win and type(win.Unload) == "function" then
			win:Unload()
		end
	end)

	local function unload()
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			root:Destroy()
		end)
	end

	return { Root = root, Unload = unload }
end

return SettingsTab
