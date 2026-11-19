-- misc1.lua  (the Misc tab: a small "Main | Extras" switcher at the bottom)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Loaded by main.lua like hometab.lua. ui.lua calls  MiscModule.build(container, T, H, ctx).
--   Main   = three panels, every movement feature is listed inside them (no pop-ups, no three dots):
--              Movement  : Walk Speed, Jump Power, Inf Jump, Fly, Gravity
--              Extras    : Tickrate, Bunny Hop, No Clip, Spider Man, Float
--              Zhd extras: No Slowdown, No Jump Cooldown   (Zee Hood only)
--            A panel scrolls when it is full. A thin RED divider sits between two features.
--   Extras = built by misc2.lua  (main.lua passes it as  Misc = { ExtrasModule = modules.Misc2 }  ).
--
-- Every feature shows, top to bottom:
--   Name ........................ [switch]
--   one inset box with its settings:
--     Keybind ......... [key box]       click it, then press a key (Escape or Backspace clears it)
--     Mode ............ [drop-down]     Always = on while the switch is on, no key needed
--                                        Toggle = the keybind turns it on / off
--                                        Hold   = on only while the keybind is held down
--     Type ............ [drop-down]     Walk Speed only (Velocity / Position / Slippery)
--     sliders (name left, value right, red bar)
-- Every switch is OFF each time the script starts. Turning a feature off (or unloading) puts back what it changed.
--
-- KEYBINDS PANEL (left of the window): a feature only shows there while it is RUNNING.
--   Always = shown while the switch is on.   Toggle = shown only after the key turned it on.
--   Hold   = shown only while the key is held down.   Switched on but not running = not shown.
--
-- SEARCH: every feature is registered with the window's search box (ctx.Win:AddSearch). Typing "walk" in the
--   top bar lists Walk Speed; Find switches to the Misc tab, scrolls to it and flashes its box.
--
-- Features:
--   Walk Speed   Velocity  = pushes your horizontal velocity to the speed (does not touch WalkSpeed)
--                Position  = moves your position a little every frame
--                Slippery  = velocity with momentum, like on ice (Slide slider: more = more sliding)
--   Fly          Fly where the camera looks (W A S D, Space = up, Left Ctrl or Q = down)
--   Jump Power   Sets your jump power AND adds the jump speed itself on every jump
--   Gravity      A force on your character instead of Workspace.Gravity, so the game cannot set it back
--   Tickrate     Roblox flag DFIntS2PhysicsSenderRate (needs setfflag). Turning it off puts the old value back.
--   Bunny Hop    Hold Space: you jump the moment you land and gain speed on every hop up to Max Speed
--   No Clip      Walk through walls
--   Inf Jump     Press Space in the air: a REAL jump
--   Spider Man   Walk into a wall and you climb it
--   Float        Changes your hip height so you hover above the ground
--   No Slowdown  ZEE HOOD ONLY. Clears the slow effects in BodyEffects.Movement and gives your walk speed back.
--   No Jump Cooldown  ZEE HOOD ONLY. Clears BodyEffects.Movement.NoJumping and keeps your jump power up.
--
-- Put your own items into a panel with:   ctx.Win.MiscPanels.Movement   ("Movement", "Extras", "ZhdExtras")
-- Switch pages from code with:            ctx.Win.MiscShow("Main")  or  ctx.Win.MiscShow("Extras")

local Misc1 = {}

-- tall = the panel runs down to the bottom of the page (level with the Main | Extras bar).
-- The middle panel is not tall, because the Main | Extras bar sits under it.
local PANELS = {
	{ id = "Movement",  title = "Movement",   tall = true,  icon = "chevrons",
		ids = { "walkspeed", "jumppower", "infjump", "fly", "gravity" } },
	{ id = "Extras",    title = "Extras",     tall = false, icon = "plus",
		ids = { "tickrate", "bhop", "noclip", "spider", "float" } },
	{ id = "ZhdExtras", title = "Zhd extras", tall = true,  icon = "diamond",
		ids = { "noslow", "nojumpcd" } },
}

-- extra words the search box also matches for each feature (the feature name is always matched)
local SEARCH_WORDS = {
	walkspeed = "speed run move velocity slippery",
	fly = "flight air",
	jumppower = "jump height",
	gravity = "grav",
	tickrate = "tick rate physics",
	bhop = "bunny hop jump speed",
	noclip = "no clip wall collide",
	infjump = "infinite jump air",
	spider = "spiderman climb wall",
	float = "hover hip height",
	noslow = "slowdown zee hood zhd",
	nojumpcd = "cooldown jump zee hood zhd",
}

function Misc1.build(container, T, H, ctx)
	local TweenService = game:GetService("TweenService")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH

	local GAP = 14        -- space between the three panels
	local EXTRAS_SPACE = 14   -- space under the middle panel, above the Main | Extras bar
	local HEAD = 38       -- height of a panel's title bar
	local SW_W = 220      -- switcher width
	local SW_H = 28       -- switcher height
	local SW_GAP = 3      -- space between the pages and the switcher (smaller = closer to the panels)

	-- spacing inside the panels (bigger = less cramped)
	local BODY_PAD_X = 14
	local BODY_PAD_TOP = 16
	local BODY_PAD_BOTTOM = 18
	local SECTION_GAP = 18    -- space above and below a red divider
	local HEADER_H = 28       -- name + switch row
	local BOX_PAD = 10        -- padding inside the settings box
	local BOX_GAP = 9         -- space between the rows inside the settings box
	local ROW_H = 28          -- keybind / drop-down row height
	local SLIDER_H = 38

	local root = new("Frame", {
		Name = "MiscRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	-- the area above the switcher; both pages live in here
	local view = new("Frame", {
		Name = "View",
		Size = UDim2.new(1, 0, 1, -(SW_H + SW_GAP)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, root)

	-- plain frames on purpose (not CanvasGroups): the window and the tab page are already CanvasGroups,
	-- and stacking more of them is heavy and can crash weaker devices
	local function makePage(name, shown)
		return new("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = shown,
		}, view)
	end

	local mainPage = makePage("MainPage", true)
	local extrasPage = makePage("ExtrasPage", false)

	---------------------------------------------------------------------
	-- MAIN PAGE: the three panels
	---------------------------------------------------------------------
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, GAP),
	}, mainPage)

	-- small calm-red icon drawn with frames (16x16), sits left of a panel title
	local function headerIcon(parent, kind)
		local holder = new("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(14, (HEAD - 16) / 2),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, parent)

		local function bit(w, h, x, y, rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, y),
				Size = UDim2.fromOffset(w, h),
				Rotation = rot or 0,
				BackgroundColor3 = T.ACCENT,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, holder)
			corner(f, 1)
			return f
		end

		if kind == "chevrons" then
			-- two ">" one after the other (movement)
			for k = 0, 1 do
				local x = -3 + k * 5
				bit(7, 2, x, -2.5, 45)
				bit(7, 2, x, 2.5, -45)
			end
		elseif kind == "plus" then
			bit(12, 2, 0, 0)
			bit(2, 12, 0, 0)
		else
			-- diamond outline with a dot in the middle
			local d = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(9, 9),
				Rotation = 45,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, holder)
			corner(d, 2)
			stroke(d, T.ACCENT, 2, 0)
			bit(3, 3, 0, 0)
		end
		return holder
	end

	local bodies = {}
	local count = #PANELS

	for i = 1, count do
		local def = PANELS[i]

		-- the side panels get the height of the switcher bar added, so their bottoms are level with it
		local extraH = -EXTRAS_SPACE
		if def.tall then
			extraH = SW_H + SW_GAP
		end
		local panel = new("Frame", {
			Name = def.id .. "Panel",
			LayoutOrder = i,
			Size = UDim2.new(1 / count, -(GAP * (count - 1)) / count, 1, extraH),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, mainPage)
		corner(panel, 6)
		stroke(panel, T.BORDER, 1, 0)

		-- title bar
		headerIcon(panel, def.icon)
		label(panel, def.title, UDim2.fromOffset(40, 0), UDim2.new(1, -108, 0, HEAD),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR).ZIndex = 3

		-- badge on the right of the title: how many options are in this panel (for example 5)
		local badge = new("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0, HEAD / 2),
			Size = UDim2.fromOffset(26, 20),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)
		corner(badge, 4)
		stroke(badge, T.BORDER, 1, 0)
		local badgeText = label(badge, tostring(#def.ids), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
			Enum.Font.GothamMedium, 12, T.ICON, Enum.TextXAlignment.Center)
		badgeText.ZIndex = 4

		-- thin red line under the title
		new("Frame", {
			Name = "HeadLine",
			Position = UDim2.fromOffset(0, HEAD),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.ACCENT,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)

		-- body (scrolls when the features do not fit)
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
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SECTION_GAP),
		}, body)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, BODY_PAD_X),
			PaddingRight = UDim.new(0, BODY_PAD_X),
			PaddingTop = UDim.new(0, BODY_PAD_TOP),
			PaddingBottom = UDim.new(0, BODY_PAD_BOTTOM),
		}, body)

		bodies[def.id] = body
	end

	---------------------------------------------------------------------
	-- THE FEATURES (state)
	---------------------------------------------------------------------
	local running = true
	local conns = {}

	local MODES = { "Always", "Toggle", "Hold" }
	local WALK_TYPES = { "Velocity", "Position", "Slippery" }

	local function capNote()
		if type(setfflag) ~= "function" then
			return "Your executor has no setfflag, so this does nothing."
		end
		return nil
	end

	local DEFS = {
		{ id = "walkspeed", title = "Walk Speed", types = WALK_TYPES,
			sliders = {
				{ key = "speed", name = "Speed", min = 16, max = 250, step = 1, value = 50, fmt = "%d" },
				{ key = "slide", name = "Slide", min = 1, max = 10, step = 1, value = 4, fmt = "%d",
					show = function(f) return f.type == "Slippery" end },
			} },
		{ id = "fly", title = "Fly",
			sliders = { { key = "speed", name = "Speed", min = 10, max = 300, step = 5, value = 60, fmt = "%d" } } },
		{ id = "jumppower", title = "Jump Power",
			sliders = { { key = "power", name = "Power", min = 20, max = 500, step = 5, value = 100, fmt = "%d" } } },
		{ id = "gravity", title = "Gravity",
			sliders = { { key = "grav", name = "Gravity", min = 0, max = 400, step = 1, value = 60, fmt = "%d" } } },
		{ id = "tickrate", title = "Tickrate", disabled = true,
			sliders = { { key = "rate", name = "Send Rate", min = 1, max = 1000, step = 1, value = 240, fmt = "%d" } } },
		{ id = "bhop", title = "Bunny Hop",
			sliders = {
				{ key = "speed", name = "Max Speed", min = 16, max = 150, step = 1, value = 60, fmt = "%d" },
				{ key = "gain", name = "Gain", min = 0, max = 10, step = 1, value = 3, fmt = "%d" },
			} },
		{ id = "noclip", title = "No Clip" },
		{ id = "infjump", title = "Inf Jump" },
		{ id = "spider", title = "Spider Man" },
		{ id = "float", title = "Float",
			sliders = { { key = "height", name = "Height", min = 0, max = 30, step = 0.5, value = 6, fmt = "%.1f" } } },
		{ id = "noslow", title = "No Slowdown", zee = true,
			sliders = { { key = "speed", name = "Speed", min = 8, max = 60, step = 1, value = 16, fmt = "%d" } } },
		{ id = "nojumpcd", title = "No Jump Cooldown", zee = true,
			sliders = { { key = "power", name = "Power", min = 20, max = 150, step = 1, value = 50, fmt = "%d" } } },
	}

	local F = {}   -- feature state by id
	for i = 1, #DEFS do
		local d = DEFS[i]
		local vals = {}
		if d.sliders then
			for k = 1, #d.sliders do
				vals[d.sliders[k].key] = d.sliders[k].value
			end
		end
		local t = nil
		if d.types then
			t = d.types[1]
		end
		F[d.id] = {
			def = d,
			enabled = false,
			mode = "Always",
			key = nil,
			v = vals,
			type = t,
			toggled = false,
			held = false,
		}
	end

	local function isActive(f)
		if f.def.disabled or not f.enabled then
			return false
		end
		if f.mode == "Always" then
			return true
		end
		if f.mode == "Toggle" then
			return f.toggled
		end
		return f.held
	end

	local function keyName(f)
		if f.key then
			return f.key.Name
		end
		return "None"
	end

	-- short key names for the Keybinds panel (LeftControl -> LCtrl, Zero -> 0 ...)
	local KEY_SHORT = {
		LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
		LeftAlt = "LAlt", RightAlt = "RAlt", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
		Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Return = "Enter", Backquote = "`",
	}

	local function shortKey(f)
		if not f.key then
			return "None"
		end
		return KEY_SHORT[f.key.Name] or f.key.Name
	end

	-- the Keybinds panel on the left of the window: a row shows up only while the feature is RUNNING
	-- (switched on AND, for Toggle / Hold, the key turned it on / is held) and goes away when it stops.
	local function syncHint(f)
		local win = nil
		if type(ctx) == "table" then
			win = ctx.Win
		end
		if not win or type(win.SetHint) ~= "function" then
			return
		end
		if isActive(f) then
			win:SetHint(f.def.id, {
				title = f.def.title,
				key = (f.mode == "Always" and not f.key) and "Always" or shortKey(f),
				active = true,
			})
		else
			win:SetHint(f.def.id, nil)
		end
	end

	-- called whenever the switch, the mode, the key or the held / toggled state of a feature changes
	local function paintStatus(f)
		syncHint(f)
	end

	---------------------------------------------------------------------
	-- THE CONTROLS (switch, drop-down, slider, key box)
	---------------------------------------------------------------------
	local dragSlider = nil    -- the slider that is being dragged
	local listening = nil     -- the feature that waits for a key

	local function makeSwitch(row, startOn, onChange)
		local on = startOn
		local track = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
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
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = T.DIM_TEXT,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)

		local function paint(animate)
			local pos = UDim2.new(0, 3, 0.5, 0)
			local trackColor = T.CLUSTER_BG
			local knobColor = T.DIM_TEXT
			if on then
				pos = UDim2.new(0, 21, 0.5, 0)
				trackColor = T.JOIN_BG
				knobColor = T.BLACK
			end
			if animate then
				TweenService:Create(knob, SMOOTH, { Position = pos }):Play()
			else
				knob.Position = pos
			end
			TweenService:Create(knob, FAST, { BackgroundColor3 = knobColor }):Play()
			TweenService:Create(track, FAST, { BackgroundColor3 = trackColor }):Play()
		end
		paint(false)

		track.Activated:Connect(function()
			on = not on
			paint(true)
			onChange(on)
		end)
	end

	-- a row with a title on the left and a drop-down on the right. The list opens INSIDE the page
	-- (it pushes the rows below it down), so nothing is cut off by the panel.
	local OPT_H = 26
	local DD_W = 116

	local function makeDropdown(parent, order, title, options, getValue, setValue)
		local R = { open = false }
		local listH = #options * OPT_H + 6

		R.item = new("Frame", {
			Name = title .. "Row",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, parent)
		label(R.item, title, UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 0, ROW_H),
			Enum.Font.GothamMedium, 12, T.ICON)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(DD_W, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.item)
		corner(btn, 5)
		stroke(btn, T.BORDER, 1, 0)
		local valLbl = label(btn, "", UDim2.fromOffset(10, 0), UDim2.new(1, -30, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)

		-- the little chevron
		local arrow = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -15, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, btn)
		local arms = {}
		local function addArm(x, rot)
			local a = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, 0),
				Size = UDim2.fromOffset(7, 2),
				Rotation = rot,
				BackgroundColor3 = T.DIM_TEXT,
				BorderSizePixel = 0,
			}, arrow)
			corner(a, 1)
			arms[#arms + 1] = a
		end
		addArm(-2.5, 45)
		addArm(2.5, -45)

		local over = false
		local function paintArrow()
			local c = T.DIM_TEXT
			if over or R.open then
				c = T.ICON_HOVER
			end
			for i = 1, #arms do
				TweenService:Create(arms[i], FAST, { BackgroundColor3 = c }):Play()
			end
			local rot = 0
			if R.open then
				rot = 180
			end
			TweenService:Create(arrow, SMOOTH, { Rotation = rot }):Play()
		end
		btn.MouseEnter:Connect(function()
			over = true
			paintArrow()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			over = false
			paintArrow()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)

		-- the list of choices (sits under the button, hidden by the clipping while closed)
		local list = new("Frame", {
			Position = UDim2.fromOffset(0, ROW_H + 4),
			Size = UDim2.new(1, 0, 0, listH),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.item)
		corner(list, 5)
		stroke(list, T.BORDER, 1, 0)

		local optBtns = {}
		local function paintOptions()
			local now = getValue()
			for i = 1, #optBtns do
				if options[i] == now then
					optBtns[i].BackgroundTransparency = 0
				else
					optBtns[i].BackgroundTransparency = 1
				end
			end
		end

		function R.refresh()
			valLbl.Text = tostring(getValue())
			paintOptions()
		end

		function R.setOpen(o)
			R.open = o
			local h = ROW_H
			if o then
				h = ROW_H + 4 + listH
			end
			TweenService:Create(R.item, FAST, { Size = UDim2.new(1, 0, 0, h) }):Play()
			paintArrow()
		end

		for i = 1, #options do
			local ob = new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Position = UDim2.fromOffset(3, 3 + (i - 1) * OPT_H),
				Size = UDim2.new(1, -6, 0, OPT_H - 2),
				BackgroundColor3 = T.HOVER_GREY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, list)
			corner(ob, 4)
			label(ob, options[i], UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0),
				Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
			optBtns[i] = ob
			ob.MouseEnter:Connect(function()
				ob.BackgroundTransparency = 0
			end)
			ob.MouseLeave:Connect(function()
				if options[i] == getValue() then
					ob.BackgroundTransparency = 0
				else
					ob.BackgroundTransparency = 1
				end
			end)
			ob.Activated:Connect(function()
				setValue(options[i])
				R.refresh()
				R.setOpen(false)
			end)
		end

		btn.Activated:Connect(function()
			R.setOpen(not R.open)
		end)

		R.refresh()
		return R
	end

	-- a slider: the name on the left, the value on the right, a red bar with a white handle under them
	local function makeSlider(parent, order, f, sl)
		local S = { sl = sl }
		S.row = new("Frame", {
			Name = sl.name .. "Slider",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, SLIDER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent)
		label(S.row, sl.name, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 0, 18),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
		local valLbl = label(S.row, "", UDim2.new(0.6, 0, 0, 0), UDim2.new(0.4, 0, 0, 18),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Right)

		local track = new("Frame", {
			Position = UDim2.fromOffset(3, 27),
			Size = UDim2.new(1, -6, 0, 6),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, S.row)
		corner(track, 3)
		local fill = new("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = T.ACCENT,
			BorderSizePixel = 0,
		}, track)
		corner(fill, 3)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(6, 14),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, track)
		corner(knob, 2)
		local hit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, S.row)

		function S.refresh()
			local v = f.v[sl.key]
			local fr = (v - sl.min) / (sl.max - sl.min)
			fill.Size = UDim2.new(fr, 0, 1, 0)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			valLbl.Text = string.format(sl.fmt, v)
		end

		function S.setFromX(px)
			local w = track.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local fr = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
			local v = sl.min + math.floor(fr * (sl.max - sl.min) / sl.step + 0.5) * sl.step
			f.v[sl.key] = math.clamp(v, sl.min, sl.max)
			S.refresh()
		end

		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragSlider = S
				S.setFromX(input.Position.X)
			end
		end)

		S.refresh()
		return S
	end

	-- one drag handler for all sliders
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if not dragSlider then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragSlider.setFromX(input.Position.X)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragSlider = nil
		end
	end)

	---------------------------------------------------------------------
	-- ONE FEATURE = ONE SECTION INSIDE A PANEL
	--   name + switch on top, the settings in one inset box under it
	---------------------------------------------------------------------
	local function buildFeature(body, f, order)
		local d = f.def
		local outer = new("Frame", {
			Name = d.id .. "Section",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, body)
		local sec = new("Frame", {
			Name = "Content",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, outer)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}, sec)
		local n = 0
		local function nextOrder()
			n = n + 1
			return n
		end

		-- header: name, switch
		local head = new("Frame", {
			Name = "Header",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, sec)
		label(head, d.title, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 1, 0),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		makeSwitch(head, false, function(on)
			f.enabled = on
			f.toggled = false
			f.held = false
			paintStatus(f)
		end)

		-- warning (for example: your executor has no setfflag)
		if d.note then
			local msg = d.note()
			if msg then
				local w = label(sec, msg, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0),
					Enum.Font.Gotham, 11, T.WARN)
				w.LayoutOrder = nextOrder()
				w.TextWrapped = true
				w.TextTruncate = Enum.TextTruncate.None
				w.TextYAlignment = Enum.TextYAlignment.Top
				w.AutomaticSize = Enum.AutomaticSize.Y
			end
		end

		-- the inset box that holds this feature's settings
		local box = new("Frame", {
			Name = "Settings",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.WELL,
			BorderSizePixel = 0,
		}, sec)
		corner(box, 6)
		stroke(box, T.BORDER, 1, 0)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, BOX_PAD),
			PaddingRight = UDim.new(0, BOX_PAD),
			PaddingTop = UDim.new(0, BOX_PAD),
			PaddingBottom = UDim.new(0, BOX_PAD),
		}, box)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, BOX_GAP),
		}, box)
		local bn = 0
		local function boxOrder()
			bn = bn + 1
			return bn
		end

		-- keybind row
		local kr = new("Frame", {
			Name = "KeybindRow",
			LayoutOrder = boxOrder(),
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, box)
		label(kr, "Keybind", UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON)
		f.keyBtn = new("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(DD_W, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = keyName(f),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, kr)
		corner(f.keyBtn, 5)
		stroke(f.keyBtn, T.BORDER, 1, 0)
		f.keyBtn.MouseEnter:Connect(function()
			TweenService:Create(f.keyBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		f.keyBtn.MouseLeave:Connect(function()
			TweenService:Create(f.keyBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		f.keyBtn.Activated:Connect(function()
			if listening then
				listening.keyBtn.Text = keyName(listening)
			end
			if listening == f then
				listening = nil
				return
			end
			listening = f
			f.keyBtn.Text = "Press a key..."
		end)

		-- mode drop-down
		makeDropdown(box, boxOrder(), "Mode", MODES,
			function()
				return f.mode
			end,
			function(v)
				f.mode = v
				f.toggled = false
				f.held = false
				paintStatus(f)
			end)

		-- type drop-down (Walk Speed only)
		local sliderRows = {}
		local function applyShow()
			for i = 1, #sliderRows do
				local sr = sliderRows[i]
				if sr.sl.show then
					sr.row.Visible = sr.sl.show(f) and true or false
				end
			end
		end
		if d.types then
			makeDropdown(box, boxOrder(), "Type", d.types,
				function()
					return f.type
				end,
				function(v)
					f.type = v
					f.slipReset = true
					applyShow()
				end)
		end

		-- sliders
		if d.sliders then
			for i = 1, #d.sliders do
				sliderRows[#sliderRows + 1] = makeSlider(box, boxOrder(), f, d.sliders[i])
			end
		end
		applyShow()

		-- findable from the search box: Find switches to the Misc tab (done by the window), then this scrolls the
		-- panel to the feature and flashes its settings box in red
		if type(ctx) == "table" and ctx.Win and type(ctx.Win.AddSearch) == "function" then
			ctx.Win:AddSearch({
				owner = "Misc",
				title = d.title,
				tab = "Misc",
				keywords = SEARCH_WORDS[d.id] or "",
				go = function()
					if type(ctx.Win.MiscShow) == "function" then
						ctx.Win.MiscShow("Main")
					end
					-- the window may be scaled: positions on screen are scaled, the canvas is not
					local sc = 1
					if ctx.Win.Window then
						local us = ctx.Win.Window:FindFirstChildOfClass("UIScale")
						if us and us.Scale > 0 then
							sc = us.Scale
						end
					end
					local y = (outer.AbsolutePosition.Y - body.AbsolutePosition.Y) / sc + body.CanvasPosition.Y - 10
					local maxY = math.max(0, (body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y) / sc)
					TweenService:Create(body, SMOOTH, { CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY)) }):Play()
					-- a red outline that fades back to normal
					local st = box:FindFirstChildOfClass("UIStroke")
					if st then
						st.Color = T.ACCENT
						st.Thickness = 2
						TweenService:Create(st, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ Color = T.BORDER, Thickness = 1 }):Play()
					end
				end,
			})
		end

		-- DISABLED: a washed-out cover over the whole feature. It takes every click, so the switch, the key box,
		-- the drop-downs and the sliders under it cannot be used.
		if d.disabled then
			local cover = new("Frame", {
				Name = "DisabledCover",
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = T.SIDEBAR_BG,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				Active = true,
				ZIndex = 20,
			}, outer)
			corner(cover, 6)
			local tag = label(cover, "Disabled", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
				Enum.Font.GothamBold, 15, T.TEXT_COLOR, Enum.TextXAlignment.Center)
			tag.ZIndex = 21
			local function fit()
				local a = sec.AbsoluteSize
				cover.Size = UDim2.fromOffset(a.X, a.Y)
			end
			sec:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end

		paintStatus(f)
	end

	for pi = 1, #PANELS do
		local pdef = PANELS[pi]
		local pbody = bodies[pdef.id]
		local order = 0
		for k = 1, #pdef.ids do
			if k > 1 then
				-- thin RED divider between two features
				order = order + 1
				new("Frame", {
					Name = "Divider",
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = T.ACCENT,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
				}, pbody)
			end
			order = order + 1
			buildFeature(pbody, F[pdef.ids[k]], order)
		end
	end

	---------------------------------------------------------------------
	-- KEYBINDS
	---------------------------------------------------------------------
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		-- waiting for a key to bind
		if listening then
			local f = listening
			listening = nil
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				f.key = nil
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				f.key = input.KeyCode
			end
			f.toggled = false
			f.held = false
			f.keyBtn.Text = keyName(f)
			paintStatus(f)
			return
		end

		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			if f.key and f.key == input.KeyCode then
				if f.mode == "Toggle" then
					f.toggled = not f.toggled
					paintStatus(f)
				elseif f.mode == "Hold" then
					f.held = true
					paintStatus(f)
				end
			end
		end
	end)

	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			if f.key and f.key == input.KeyCode and f.mode == "Hold" and f.held then
				f.held = false
				paintStatus(f)
			end
		end
	end)

	---------------------------------------------------------------------
	-- THE MOVEMENT CODE
	---------------------------------------------------------------------
	local act = {}            -- which features are active this frame
	local lastChar = nil
	local boundHum = nil
	local humConns = {}
	local origJump = nil
	local origHip = nil
	local gravAtt = nil
	local gravVF = nil
	local flyBV = nil
	local flyBG = nil
	local flyPS = nil
	local ncParts = {}
	local slipVel = nil
	local bhopSpeed = nil
	local bhopAir = false
	local pendingJump = false
	local lastAirJump = 0
	local origCap = nil
	local lastCap = nil
	local hookOn = false
	local hookFloor = 50
	local hookInstalled = false
	local hookOld = nil
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local function getChar()
		local char = player.Character
		if not char then
			return nil, nil, nil
		end
		return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
	end

	-- the jump speed to use: the Jump Power slider, or what the humanoid has
	local function jumpVelocity(hum)
		if act.jumppower then
			return F.jumppower.v.power
		end
		if hum.UseJumpPower then
			if hum.JumpPower >= 1 then
				return hum.JumpPower
			end
		elseif hum.JumpHeight > 0 then
			return math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
		end
		return 50
	end

	-- the lowest jump power No Jump Cooldown allows
	local function jumpFloor()
		local fl = F.nojumpcd.v.power
		if act.jumppower then
			fl = math.min(fl, F.jumppower.v.power)
		end
		return fl
	end

	-- the BodyEffects folder of this character (Zee Hood: also looked up in workspace.Players)
	local function getEffects(char)
		local be = char:FindFirstChild("BodyEffects")
		if be == nil then
			local folder = workspace:FindFirstChild("Players")
			local model = nil
			if folder then
				model = folder:FindFirstChild(char.Name)
			end
			if model then
				be = model:FindFirstChild("BodyEffects")
			end
		end
		return be
	end

	-- No Slowdown: clear the slow effects and give the walk speed back
	local function clearSlow(char, hum)
		local be = getEffects(char)
		if be then
			local mv = be:FindFirstChild("Movement")
			if mv then
				local kids = mv:GetChildren()
				for i = 1, #kids do
					if kids[i].Name ~= "NoJumping" then
						pcall(function()
							kids[i]:Destroy()
						end)
					end
				end
			end
			-- knocked out players stay slow
			local ko = be:FindFirstChild("K.O")
			if ko and ko:IsA("BoolValue") and ko.Value then
				return
			end
		end
		if hum.WalkSpeed < F.noslow.v.speed then
			hum.WalkSpeed = F.noslow.v.speed
		end
	end

	-- No Jump Cooldown: clear the block and put the jump power back
	local function fixJump(char, hum)
		local be = getEffects(char)
		if be then
			local mv = be:FindFirstChild("Movement")
			if mv then
				local nj = mv:FindFirstChild("NoJumping")
				if nj then
					pcall(function()
						nj:Destroy()
					end)
				end
			end
		end
		if not hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		local fl = jumpFloor()
		if hum.UseJumpPower then
			if hum.JumpPower < fl then
				hum.JumpPower = fl
			end
		else
			local need = (fl * fl) / (2 * workspace.Gravity)
			if hum.JumpHeight < need then
				hum.JumpHeight = need
			end
		end
	end

	-- blocks the game's own writes of a lower JumpPower (only when the executor can hook metamethods)
	local function installHook()
		if hookInstalled then
			return
		end
		hookInstalled = true
		pcall(function()
			if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
				hookOld = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
					if hookOn and key == "JumpPower" and type(value) == "number" and typeof(self) == "Instance" then
						local ours = false
						if type(checkcaller) == "function" then
							ours = checkcaller()
						end
						if not ours and value < hookFloor and self:IsA("Humanoid") then
							value = hookFloor
						end
					end
					return hookOld(self, key, value)
				end))
			end
		end)
	end

	-- Tickrate = how often the client sends your physics (position) to the server.
	-- It is the dynamic flag DFIntS2PhysicsSenderRate (default about 15).
	local function applyCap(v)
		if type(setfflag) == "function" then
			pcall(setfflag, "DFIntS2PhysicsSenderRate", tostring(v))
		end
	end

	local function flyStop(hum)
		if flyBV then
			pcall(function()
				flyBV:Destroy()
			end)
			flyBV = nil
		end
		if flyBG then
			pcall(function()
				flyBG:Destroy()
			end)
			flyBG = nil
		end
		if flyPS ~= nil and hum then
			pcall(function()
				hum.PlatformStand = flyPS
			end)
		end
		flyPS = nil
	end

	local function gravStop()
		if gravVF then
			pcall(function()
				gravVF:Destroy()
			end)
			gravVF = nil
		end
		if gravAtt then
			pcall(function()
				gravAtt:Destroy()
			end)
			gravAtt = nil
		end
	end

	local function ncRestore()
		for part, _ in pairs(ncParts) do
			if part and part.Parent then
				pcall(function()
					part.CanCollide = true
				end)
			end
		end
		ncParts = {}
	end

	local function resetCharState()
		origJump = nil
		origHip = nil
		flyBV = nil
		flyBG = nil
		flyPS = nil
		gravAtt = nil
		gravVF = nil
		ncParts = {}
		slipVel = nil
		bhopSpeed = nil
		bhopAir = false
		pendingJump = false
	end

	local function bindHum(hum)
		for i = 1, #humConns do
			pcall(function()
				humConns[i]:Disconnect()
			end)
		end
		humConns = {}
		humConns[#humConns + 1] = hum.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping and act.jumppower then
				pendingJump = true
			end
		end)
		humConns[#humConns + 1] = hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
			if act.nojumpcd and hum.UseJumpPower then
				local fl = jumpFloor()
				if hum.JumpPower < fl then
					hum.JumpPower = fl
				end
			end
		end)
		humConns[#humConns + 1] = hum:GetPropertyChangedSignal("JumpHeight"):Connect(function()
			if act.nojumpcd and not hum.UseJumpPower then
				local need = (jumpFloor() ^ 2) / (2 * workspace.Gravity)
				if hum.JumpHeight < need then
					hum.JumpHeight = need
				end
			end
		end)
	end

	local function computeActive()
		local a = {}
		for i = 1, #DEFS do
			local id = DEFS[i].id
			a[id] = isActive(F[id])
		end
		act = a
		return a
	end

	-- Heartbeat: switches, forces, fly, float, jump power, tickrate, no slowdown, no jump cooldown
	local function stepHB(dt)
		local a = computeActive()

		-- tickrate (the physics sender rate flag)
		if a.tickrate then
			if origCap == nil then
				origCap = 15
				if type(getfflag) == "function" then
					local ok, v = pcall(getfflag, "DFIntS2PhysicsSenderRate")
					local num = tonumber(v)
					if ok and num then
						origCap = num
					end
				end
				lastCap = nil
			end
			if lastCap ~= F.tickrate.v.rate then
				lastCap = F.tickrate.v.rate
				applyCap(lastCap)
			end
		elseif origCap ~= nil then
			applyCap(origCap)
			origCap = nil
			lastCap = nil
		end

		-- jump cooldown hook
		if a.nojumpcd then
			installHook()
		end
		hookOn = a.nojumpcd
		hookFloor = jumpFloor()

		local char, hum, hrp = getChar()
		if char ~= lastChar then
			lastChar = char
			boundHum = nil
			resetCharState()
		end
		local alive = (hum ~= nil) and (hrp ~= nil) and hum.Health > 0

		if not a.noclip then
			ncRestore()
		end

		if not alive then
			flyStop(nil)
			gravStop()
			return
		end

		if hum ~= boundHum then
			boundHum = hum
			bindHum(hum)
		end

		-- the Type drop-down of Walk Speed was changed: forget the slide speed
		if F.walkspeed.slipReset then
			F.walkspeed.slipReset = false
			slipVel = nil
		end

		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump

		-- gravity: a force on the character that cancels the world gravity and adds the wanted one
		if a.gravity then
			if gravVF == nil or gravVF.Parent ~= hrp then
				gravStop()
				gravAtt = Instance.new("Attachment")
				gravAtt.Name = "Y1GravAtt"
				gravAtt.Parent = hrp
				gravVF = Instance.new("VectorForce")
				gravVF.Name = "Y1Grav"
				gravVF.Attachment0 = gravAtt
				gravVF.RelativeTo = Enum.ActuatorRelativeTo.World
				gravVF.ApplyAtCenterOfMass = true
				gravVF.Force = Vector3.new(0, 0, 0)
				gravVF.Parent = hrp
			end
			gravVF.Force = Vector3.new(0, hrp.AssemblyMass * (workspace.Gravity - F.gravity.v.grav), 0)
		elseif gravVF or gravAtt then
			gravStop()
		end

		-- jump power (the property; the real boost happens on every jump in stepPhys)
		if a.jumppower then
			if origJump == nil then
				origJump = { use = hum.UseJumpPower, power = hum.JumpPower }
			end
			hum.UseJumpPower = true
			hum.JumpPower = F.jumppower.v.power
		elseif origJump ~= nil then
			hum.UseJumpPower = origJump.use
			hum.JumpPower = origJump.power
			origJump = nil
		end

		-- float (hip height)
		if a.float then
			if origHip == nil then
				origHip = hum.HipHeight
			end
			hum.HipHeight = F.float.v.height
		elseif origHip ~= nil then
			hum.HipHeight = origHip
			origHip = nil
		end

		-- zee hood: no slowdown / no jump cooldown
		if a.noslow then
			clearSlow(char, hum)
		end
		if a.nojumpcd then
			fixJump(char, hum)
		end

		-- fly
		if a.fly then
			if not flyBV or flyBV.Parent ~= hrp then
				flyStop(hum)
				flyBV = Instance.new("BodyVelocity")
				flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
				flyBV.Velocity = Vector3.new(0, 0, 0)
				flyBV.Parent = hrp
				flyBG = Instance.new("BodyGyro")
				flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
				flyBG.P = 90000
				flyBG.CFrame = hrp.CFrame
				flyBG.Parent = hrp
				flyPS = hum.PlatformStand
				hum.PlatformStand = true
			end
			local cam = workspace.CurrentCamera
			if cam then
				local lv = cam.CFrame:VectorToObjectSpace(hum.MoveDirection)
				local vel = cam.CFrame.LookVector * (-lv.Z) + cam.CFrame.RightVector * lv.X
				if spaceDown then
					vel = vel + Vector3.new(0, 1, 0)
				end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
					vel = vel - Vector3.new(0, 1, 0)
				end
				if vel.Magnitude > 1 then
					vel = vel.Unit
				end
				flyBV.Velocity = vel * F.fly.v.speed
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					flyBG.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
				end
			end
		elseif flyBV or flyBG then
			flyStop(hum)
		end

		-- walk speed: Velocity / Slippery are set again here (the physics step also sets them)
		if a.walkspeed and not a.fly then
			local md = hum.MoveDirection
			local t = F.walkspeed.type
			if t == "Velocity" and md.Magnitude > 0.1 then
				local vel = hrp.AssemblyLinearVelocity
				local sp = F.walkspeed.v.speed
				hrp.AssemblyLinearVelocity = Vector3.new(md.X * sp, vel.Y, md.Z * sp)
			elseif t == "Slippery" and slipVel then
				local vel = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(slipVel.X, vel.Y, slipVel.Z)
			end
		end

		-- spider man: walk into a wall and climb it
		if a.spider then
			local md = hum.MoveDirection
			if md.Magnitude > 0.1 then
				rayParams.FilterDescendantsInstances = { char }
				local res = workspace:Raycast(hrp.Position, md.Unit * 3, rayParams)
				if res and res.Instance.CanCollide then
					hrp.AssemblyLinearVelocity = Vector3.new(0, 40, 0) - res.Normal * 4
					hum:ChangeState(Enum.HumanoidStateType.Climbing)
				end
			end
		end
	end

	-- Stepped (right before physics): walk speed, bunny hop, jump boost, no clip
	local function stepPhys(dt)
		local a = act
		local char, hum, hrp = getChar()
		if not char or not hum or not hrp or hum.Health <= 0 then
			return
		end

		-- no clip: collisions are reset every physics step, so this runs here
		if a.noclip then
			local parts = char:GetDescendants()
			for i = 1, #parts do
				local p = parts[i]
				if p:IsA("BasePart") and p.CanCollide then
					ncParts[p] = true
					p.CanCollide = false
				end
			end
		end

		if a.noslow then
			clearSlow(char, hum)
		end
		if a.nojumpcd then
			fixJump(char, hum)
		end

		local md = hum.MoveDirection
		local vel = hrp.AssemblyLinearVelocity
		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump
		local grounded = hum.FloorMaterial ~= Enum.Material.Air

		-- walk speed
		if a.walkspeed and not a.fly then
			local t = F.walkspeed.type
			local speed = F.walkspeed.v.speed
			if t == "Slippery" then
				if slipVel == nil then
					slipVel = Vector3.new(vel.X, 0, vel.Z)
				end
				local actual = Vector3.new(vel.X, 0, vel.Z)
				-- hit a wall: the real speed is much lower, so do not keep pushing
				if actual.Magnitude < slipVel.Magnitude * 0.5 then
					slipVel = actual
				end
				local slide = F.walkspeed.v.slide
				local target = Vector3.new(0, 0, 0)
				local rate = 10 / slide
				if md.Magnitude > 0.1 then
					target = md * speed
					rate = 12 / slide
				end
				slipVel = slipVel:Lerp(target, 1 - math.exp(-rate * dt))
				hrp.AssemblyLinearVelocity = Vector3.new(slipVel.X, vel.Y, slipVel.Z)
				vel = hrp.AssemblyLinearVelocity
			else
				slipVel = nil
				if md.Magnitude > 0.1 then
					if t == "Position" then
						local extra = math.max(0, speed - hum.WalkSpeed)
						hrp.CFrame = hrp.CFrame + md * extra * dt
					else
						hrp.AssemblyLinearVelocity = Vector3.new(md.X * speed, vel.Y, md.Z * speed)
						vel = hrp.AssemblyLinearVelocity
					end
				end
			end
		else
			slipVel = nil
		end

		-- bunny hop
		if a.bhop and not a.fly then
			if spaceDown then
				local maxSp = F.bhop.v.speed
				if bhopSpeed == nil then
					bhopSpeed = math.max(hum.WalkSpeed, 16)
				end
				if grounded then
					if bhopAir then
						bhopAir = false
						bhopSpeed = bhopSpeed + F.bhop.v.gain
					end
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				else
					bhopAir = true
				end
				if bhopSpeed > maxSp then
					bhopSpeed = maxSp
				end
				if md.Magnitude > 0.1 then
					local cv = hrp.AssemblyLinearVelocity
					local curH = Vector3.new(cv.X, 0, cv.Z)
					local target = md.Unit * bhopSpeed
					local newH = curH:Lerp(target, 1 - math.exp(-10 * dt))
					hrp.AssemblyLinearVelocity = Vector3.new(newH.X, cv.Y, newH.Z)
				end
			else
				bhopSpeed = nil
				bhopAir = false
			end
		else
			bhopSpeed = nil
			bhopAir = false
		end

		-- jump power: add the jump speed itself right after a jump started
		if pendingJump then
			pendingJump = false
			if a.jumppower then
				local cv = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(cv.X, F.jumppower.v.power, cv.Z)
			end
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if running then
			pcall(stepHB, dt)
		end
	end)

	conns[#conns + 1] = RunService.Stepped:Connect(function(_, dt)
		if running then
			pcall(stepPhys, dt)
		end
	end)

	-- inf jump: a REAL jump in mid air (the humanoid jumps and your upward speed is set to the jump speed)
	conns[#conns + 1] = UserInputService.JumpRequest:Connect(function()
		if not running or not act.infjump then
			return
		end
		local now = os.clock()
		if now - lastAirJump < 0.12 then
			return
		end
		local _, hum, hrp = getChar()
		if not hum or not hrp or hum.Health <= 0 then
			return
		end
		if hum.FloorMaterial ~= Enum.Material.Air then
			return
		end
		lastAirJump = now
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(vel.X, jumpVelocity(hum), vel.Z)
	end)

	-- UNLOAD of the movement code: switch everything off and put the original values back
	local function moveUnload()
		if not running then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			f.enabled = false
			f.toggled = false
			f.held = false
			pcall(syncHint, f)
		end
		pcall(stepHB, 0.016)
		hookOn = false
		running = false
		for i = 1, #humConns do
			pcall(function()
				humConns[i]:Disconnect()
			end)
		end
		humConns = {}
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
	end

	---------------------------------------------------------------------
	-- EXTRAS PAGE: built by misc2.lua
	---------------------------------------------------------------------
	local extrasHandle = nil
	local extrasHolder = new("Frame", {
		Name = "ExtrasBody",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, extrasPage)

	local extrasMod = nil
	if type(ctx) == "table" then
		extrasMod = ctx.ExtrasModule
	end

	if type(extrasMod) == "table" and type(extrasMod.build) == "function" then
		local ok, res = pcall(extrasMod.build, extrasHolder, T, H, ctx)
		if ok then
			if type(res) == "table" then
				extrasHandle = res
			end
		else
			warn("[Y1] misc2.lua failed: " .. tostring(res))
			local msg = tostring(res)
			if #msg > 200 then
				msg = string.sub(msg, 1, 197) .. "..."
			end
			local t1 = label(extrasHolder, "Extras failed to build", UDim2.new(0, 0, 0.5, -24), UDim2.new(1, 0, 0, 22),
				Enum.Font.GothamBold, 16, T.TEXT_COLOR, Enum.TextXAlignment.Center)
			local t2 = label(extrasHolder, msg, UDim2.new(0, 20, 0.5, 2), UDim2.new(1, -40, 0, 50),
				Enum.Font.GothamMedium, 12, T.WARN, Enum.TextXAlignment.Center)
			t2.TextWrapped = true
			t2.TextTruncate = Enum.TextTruncate.None
			t2.TextYAlignment = Enum.TextYAlignment.Top
			t1.ZIndex = 2
		end
	else
		label(extrasHolder, "misc2.lua is not loaded", UDim2.new(0, 0, 0.5, -10), UDim2.new(1, 0, 0, 20),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Center)
	end

	---------------------------------------------------------------------
	-- SWITCHER: "Main | Extras" bar at the bottom middle
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
		Size = UDim2.new(0.5, -6, 1, -6),
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

	local current = "Main"
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
		if name == current then
			return
		end
		if name ~= "Main" and name ~= "Extras" then
			return
		end
		current = name

		local nxt = mainPage
		local prv = extrasPage
		local pos = UDim2.new(0, 3, 0, 3)
		if name == "Extras" then
			nxt = extrasPage
			prv = mainPage
			pos = UDim2.new(0.5, 3, 0, 3)
		end

		TweenService:Create(indicator, SMOOTH, { Position = pos }):Play()
		paintButtons()

		prv.Visible = false
		nxt.Visible = true
	end

	local function makeButton(name, x)
		local b = new("TextButton", {
			Name = name .. "Btn",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
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
	makeButton("Main", 0)
	makeButton("Extras", 0.5)
	paintButtons()

	-- let other code reach the panels / switch pages
	if type(ctx) == "table" and ctx.Win then
		ctx.Win.MiscPanels = bodies
		ctx.Win.MiscShow = function(name)
			show(name)
		end
	end

	return {
		Panels = bodies,
		Show = show,
		Unload = function()
			moveUnload()
			-- take this module's features out of the search box
			if type(ctx) == "table" and ctx.Win and type(ctx.Win.RemoveSearch) == "function" then
				pcall(ctx.Win.RemoveSearch, ctx.Win, "Misc")
			end
			if extrasHandle and type(extrasHandle.Unload) == "function" then
				pcall(extrasHandle.Unload)
			end
			if root and root.Parent then
				root:Destroy()
			end
		end,
	}
end

return Misc1
