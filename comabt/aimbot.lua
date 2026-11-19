-- aimbot.lua  (the Combat tab: a small "Aimbot | Silent | Triggerbot" switcher at the bottom)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Loaded by main.lua like misc1.lua. ui.lua calls  CombatModule.build(container, T, H, ctx).
-- This file is where everything in the Combat tab is connected:
--   Aimbot     = built right here. Empty for now (an empty panel, put the aimbot features into ctx.Win.CombatAimbot).
--   Silent     = built by silent.lua   (main.lua passes it as  Combat = { SilentModule = modules.Silent, ... }  ).
--   Triggerbot = built by trigger.lua  (main.lua passes it as  Combat = { TriggerModule = modules.Trigger, ... }  ).
-- If a module is missing from the options, it is also looked for in getgenv().Y1_MODULES (Silent / Trigger).
--
-- The bar at the bottom has the same look as the "Main | Extras" bar of the Misc tab: a flat grey block under the active
-- option with the small red bar. It sits under the middle of the page, so the middle panel of the Triggerbot page
-- is shorter and the two side panels run down level with it. ctx.SwitcherSpace tells the pages how much room the bar takes.
--
-- Put your own items into a page with:  ctx.Win.CombatAimbot / ctx.Win.CombatSilent   (frames)
-- Switch pages from code with:          ctx.Win.CombatShow("Aimbot" | "Silent" | "Triggerbot")

local Combat = {}

local PAGES = { "Aimbot", "Silent", "Triggerbot" }

function Combat.build(container, T, H, ctx)
	if type(ctx) ~= "table" then
		ctx = {}
	end
	local TweenService = game:GetService("TweenService")

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH

	local SW_W = 228      -- switcher width (3 equal parts; narrower than the middle panel of the Triggerbot page)
	local SW_H = 28       -- switcher height
	local SW_GAP = 3      -- space between the pages and the switcher
	local PART = 1 / #PAGES

	local root = new("Frame", {
		Name = "CombatRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	-- the area above the switcher; every page lives in here
	local view = new("Frame", {
		Name = "View",
		Size = UDim2.new(1, 0, 1, -(SW_H + SW_GAP)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, root)

	-- plain frames on purpose (not CanvasGroups): the window and the tab page are already CanvasGroups
	local holders = {}
	for i = 1, #PAGES do
		local name = PAGES[i]
		holders[name] = new("Frame", {
			Name = name .. "Page",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = (i == 1),
		}, view)
	end

	local handles = {}

	---------------------------------------------------------------------
	-- AIBOT PAGE: an empty panel (nothing in it yet)
	---------------------------------------------------------------------
	local aimBody = nil
	do
		local panel = new("Frame", {
			Name = "AimbotRoot",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, holders.Aimbot)
		corner(panel, 6)
		stroke(panel, T.BORDER, 1, 0)

		-- crosshair icon: a ring and four short ticks, all calm red
		local ico = new("Frame", {
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)
		local r = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, ico)
		corner(r, 100)
		stroke(r, T.ACCENT, 2, 0)
		local function tick(x, y, w, h)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, y),
				Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = T.ACCENT,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, ico)
			corner(f, 1)
		end
		tick(0, -7, 2, 4)
		tick(0, 7, 2, 4)
		tick(-7, 0, 4, 2)
		tick(7, 0, 4, 2)

		label(panel, "Aimbot", UDim2.fromOffset(36, 0), UDim2.new(1, -48, 0, 34),
			Enum.Font.GothamBold, 13, T.TEXT_COLOR).ZIndex = 3
		new("Frame", {
			Name = "HeadLine",
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.ACCENT,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)

		aimBody = new("ScrollingFrame", {
			Name = "Body",
			Position = UDim2.fromOffset(0, 35),
			Size = UDim2.new(1, 0, 1, -35),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = T.BORDER,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 2,
		}, panel)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}, aimBody)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
		}, aimBody)

		-- shown until the first feature is added
		local hint = label(panel, "Aimbot features will go here", UDim2.new(0, 0, 0.5, -8), UDim2.new(1, 0, 0, 16),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Center)
		hint.ZIndex = 2
		aimBody.ChildAdded:Connect(function(c)
			if c:IsA("GuiObject") and hint.Visible then
				hint.Visible = false
			end
		end)
	end

	---------------------------------------------------------------------
	-- SILENT + TRIGGERBOT: built by their own modules into their pages
	---------------------------------------------------------------------
	local function findModule(optName, genvName)
		local m = ctx[optName]
		if m == nil then
			local ok, g = pcall(function()
				return getgenv()
			end)
			if ok and type(g) == "table" and type(g.Y1_MODULES) == "table" then
				m = g.Y1_MODULES[genvName]
			end
		end
		return m
	end

	local function buildInto(pageName, mod, notLoadedText)
		local holder = holders[pageName]
		if type(mod) == "table" and type(mod.build) == "function" then
			-- the pages get a copy of ctx plus how much room the bottom bar takes
			local c = {}
			for k, v in pairs(ctx) do
				c[k] = v
			end
			c.SwitcherSpace = SW_H + SW_GAP
			local ok, res = pcall(mod.build, holder, T, H, c)
			if ok then
				if type(res) == "table" then
					handles[#handles + 1] = res
				end
			else
				warn("[Y1] the " .. pageName .. " page failed: " .. tostring(res))
				local msg = tostring(res)
				if #msg > 200 then
					msg = string.sub(msg, 1, 197) .. "..."
				end
				local t1 = label(holder, pageName .. " failed to build", UDim2.new(0, 0, 0.5, -24), UDim2.new(1, 0, 0, 22),
					Enum.Font.GothamBold, 16, T.TEXT_COLOR, Enum.TextXAlignment.Center)
				local t2 = label(holder, msg, UDim2.new(0, 20, 0.5, 2), UDim2.new(1, -40, 0, 50),
					Enum.Font.GothamMedium, 12, T.WARN, Enum.TextXAlignment.Center)
				t2.TextWrapped = true
				t2.TextTruncate = Enum.TextTruncate.None
				t2.TextYAlignment = Enum.TextYAlignment.Top
				t1.ZIndex = 2
			end
		else
			label(holder, notLoadedText, UDim2.new(0, 0, 0.5, -10), UDim2.new(1, 0, 0, 20),
				Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Center)
		end
	end

	-- the window object is needed by the pages (search, keybinds panel, toasts)
	if ctx.Win then
		ctx.Win.CombatAimbot = aimBody
	end

	buildInto("Silent", findModule("SilentModule", "Silent"), "silent.lua is not loaded")
	buildInto("Triggerbot", findModule("TriggerModule", "Trigger"), "trigger.lua is not loaded")

	---------------------------------------------------------------------
	-- SWITCHER: "Aimbot | Silent | Triggerbot" bar at the bottom middle
	---------------------------------------------------------------------
	local switcher = new("Frame", {
		Name = "Switcher",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(SW_W, SW_H),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, root)
	corner(switcher, 5)
	stroke(switcher, T.BORDER, 1, 0)

	-- flat grey block under the active option, with the same small red bar the bottom tab bar uses
	local indicator = new("Frame", {
		Name = "Indicator",
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(PART, -6, 1, -6),
		BackgroundColor3 = T.HOVER_GREY,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, switcher)
	corner(indicator, 3)
	local bar = new("Frame", {
		Name = "RedBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(20, 2),
		BackgroundColor3 = T.ACCENT,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, indicator)
	corner(bar, 1)

	local current = "Aimbot"
	local btns = {}

	local function paintButtons()
		for name, b in pairs(btns) do
			local c = T.DIM_TEXT
			if name == current then
				c = T.TEXT_COLOR
			end
			TweenService:Create(b, FAST, { TextColor3 = c }):Play()
		end
	end

	local function show(name)
		if name == current or not holders[name] then
			return
		end
		local idx = 1
		for i = 1, #PAGES do
			if PAGES[i] == name then
				idx = i
			end
		end
		holders[current].Visible = false
		holders[name].Visible = true
		current = name
		TweenService:Create(indicator, SMOOTH, { Position = UDim2.new((idx - 1) * PART, 3, 0, 3) }):Play()
		paintButtons()
	end

	for i = 1, #PAGES do
		local name = PAGES[i]
		local b = new("TextButton", {
			Name = name .. "Btn",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new((i - 1) * PART, 0, 0, 0),
			Size = UDim2.new(PART, 0, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = name,
			TextSize = 12,
			TextColor3 = T.DIM_TEXT,
			ZIndex = 8,
		}, switcher)
		b.MouseEnter:Connect(function()
			if name ~= current then
				TweenService:Create(b, FAST, { TextColor3 = T.ICON_HOVER }):Play()
			end
		end)
		b.MouseLeave:Connect(function()
			paintButtons()
		end)
		b.Activated:Connect(function()
			show(name)
		end)
		btns[name] = b
	end
	paintButtons()

	-- let other code switch pages
	if ctx.Win then
		ctx.Win.CombatShow = function(name)
			show(name)
		end
	end

	return {
		Show = show,
		Unload = function()
			for i = 1, #handles do
				local h = handles[i]
				if type(h) == "table" and type(h.Unload) == "function" then
					pcall(h.Unload)
				end
			end
			handles = {}
			if root and root.Parent then
				root:Destroy()
			end
		end,
	}
end

return Combat
