-- misc2.lua  (Y1 Misc tab > Extras page: everything that used to be extra.lua, animation.lua and extra1.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Built by misc1.lua into the "Extras" side of its "Main | Extras" switcher:
--     Extra2.build(container, T, H, ctx)       -> { Root = ..., Unload = fn }
--   T = theme, H = { new, corner, stroke, label }, ctx.Win = the Y1 window
--
-- Same look as the Main page: three panels with a title bar, a red line under it and a count badge, the features
-- listed one under the other with a red divider between them. No three dots and no pop-ups: every setting is
-- shown right in the panel (switch on top, one inset box with the settings under it). Drop-downs and the colour
-- picker open INSIDE the panel and push the rows below them down.
-- Every switch is OFF each time the script starts. Switching a feature off (or unloading) puts back what it changed.
--
--   Zee Hood Extras : Bullet Tracer, Hit Sounds, Hit Markers, Auto Buy (Armor / Stim / Food)
--   Extra Needs     : Orbit, Spin Bot, Hitbox Expander, Hitbox Spoofer   (spoofers/spoofer1.lua)
--   Quality Of Life : Animations, Anti AFK, Ping Spoofer                  (spoofers/spoofer2.lua)
--
-- The two spoofers are separate files. main.lua gives them to this page:
--     Misc = { ExtrasModule = modules.Extra2, Spoofer1Module = modules.Spoofer1, Spoofer2Module = modules.Spoofer2 }
-- (the page also looks in getgenv().Y1_MODULES.Spoofer1 / .Spoofer2). Each one is Spoofer.build(parent, T, H, ctx)
-- and returns { Root, Box, Unload }. If one is missing the panel shows a small "not loaded" line.
--
-- KEYBINDS PANEL: Orbit shows up there while you are orbiting somebody (ctx.Win:SetHint).
-- SEARCH: every feature is registered with the window's search box (ctx.Win:AddSearch) when the window has it.
--
-- BULLET TRACER   Leaves a fading tracer for YOUR shots (the gun script makes a "BULLET_RAYS" part per shot).
-- HIT SOUNDS      Plays a sound for YOUR shots: Play On = On Shot (every shot) or On Hit (only when you hit a player).
--                 Wraps GunHandler.Shoot; falls back to watching BULLET_RAYS. Mute Gun Sounds silences your own gun.
-- HIT MARKERS     Red damage numbers next to the player you hit. Fade Speed = how fast they disappear.
-- AUTO BUY        Left-clicks the Head of every shop model in workspace.Ignored.Shop that is in Range
--                 ("[Full Armor]" = armor, "[Stim]" = stim, everything else = food). Needs fireclickdetector.
-- ORBIT           Set a keybind, press it to orbit the player closest to your mouse, press it again to stop.
-- SPIN BOT        Turns only YOUR character: Normal = spins around, Upside = front flips, Side = cartwheels,
--                 Backwards = faces away from where you aim. The camera is untouched.
-- HITBOX EXPANDER Makes every other player's HumanoidRootPart bigger on YOUR client (restored when switched off).
-- ANIMATIONS      Swaps your Idle / Walk / Run / Jump / Fall / Swim / Climb animations for an R15 package.
-- ANTI AFK        Blocks the idle kick with a fake click when Roblox says you went idle.

local Extra2 = {}

-- where the spoofer files live (used only when main.lua did not pass them in)
local SPOOFER_BASE = "https://raw.githubusercontent.com/boiiiiiurcool/yur1r132131213232312131231232/main/"

-- extra words the search box also matches for each feature (the feature name is always matched)
local SEARCH_WORDS = {
	tracer = "bullet tracer beam shot color rainbow zhd zee hood",
	sounds = "hit sound audio volume mute gun zhd zee hood",
	markers = "hit marker damage number zhd zee hood",
	autobuy = "auto buy armor stim food shop purchase zhd zee hood",
	orbit = "orbit circle target player keybind",
	spin = "spin bot spinbot rotate upside backwards",
	hitbox = "hitbox expander size head root team knocked dynamic visualize",
	hitboxspoofer = "hitbox spoofer blood armor",
	anim = "animation animations pack idle walk run jump fall swim climb",
	afk = "anti afk idle kick",
	ping = "ping spoofer jitter fake latency ms",
}

-- short key names for the Keybinds panel (LeftControl -> LCtrl, Zero -> 0 ...)
local KEY_SHORT = {
	LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
	LeftAlt = "LAlt", RightAlt = "RAlt", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Return = "Enter", Backquote = "`",
}

-- icon = the little red symbol in front of the panel title
local PANELS = {
	{ id = "ZeeHood", title = "Zee Hood Extras", icon = "ring", count = 4, tall = true },
	{ id = "Needs",   title = "Extra Needs",     icon = "diamond", count = 4 },
	{ id = "Quality", title = "Quality Of Life", icon = "plus", count = 3, tall = true },
}

function Extra2.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local Debris = game:GetService("Debris")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")
	local ContentProvider = game:GetService("ContentProvider")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH

	-- layout (same numbers as the Main page of misc1.lua)
	local GAP = 14
	local HEAD = 38
	local SW_H = 28                     -- height of the Main | Extras bar (misc1.lua)
	local SW_GAP = 3                    -- gap between the pages and that bar (misc1.lua)
	local EXTRAS_SPACE = 14             -- space left under the middle panel, above the bar
	local BODY_PAD_X = 14
	local BODY_PAD_TOP = 16
	local BODY_PAD_BOTTOM = 18
	local SECTION_GAP = 18
	local HEADER_H = 28
	local BOX_PAD = 10
	local BOX_GAP = 9
	local ROW_H = 28
	local SLIDER_H = 38
	local OPT_H = 26
	local DD_W = 116
	local MAX_LIST = 6 * OPT_H + 6      -- a drop-down list scrolls when it has more than 6 choices
	local PICK_H = 188                  -- height of the opened colour picker

	local running = true
	local conns = {}
	local unloaders = {}
	local dragObj = nil                 -- the slider / picker handle that is being dragged

	---------------------------------------------------------------------
	-- small helpers
	---------------------------------------------------------------------
	local function shortKey(kc)
		if not kc then
			return "None"
		end
		return KEY_SHORT[kc.Name] or kc.Name
	end

	-- mouse / touch position in the same space as AbsolutePosition (the top bar inset is taken into account)
	local function pointerPos(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end
		return UserInputService:GetMouseLocation()
	end

	-- a spoofer module handed over by main.lua (ctx.Spoofer1Module) or found in getgenv().Y1_MODULES.Spoofer1
	local function findModule(ctxKey, genvKey, fileName)
		local m = nil
		if type(ctx) == "table" then
			m = ctx[ctxKey]
			if not m and type(ctx.Modules) == "table" then
				m = ctx.Modules[genvKey]
			end
		end
		if not m then
			local okG, g = pcall(function()
				return getgenv()
			end)
			if okG and type(g) == "table" and type(g.Y1_MODULES) == "table" then
				m = g.Y1_MODULES[genvKey]
			end
		end
		if type(m) == "table" and type(m.build) == "function" then
			return m
		end
		-- main.lua did not hand it over (an older main.lua, say): download it from the repo here
		local url = SPOOFER_BASE .. fileName
		local okF, res = pcall(function()
			local src = game:HttpGet(url .. "?v=" .. tostring(os.time()))
			local fn, err = loadstring(src, "=" .. fileName)
			if not fn then
				error("could not compile " .. fileName .. ": " .. tostring(err))
			end
			return fn()
		end)
		if okF and type(res) == "table" and type(res.build) == "function" then
			return res
		end
		return nil, tostring(res)
	end

	---------------------------------------------------------------------
	-- root + the three panels
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "Extra2Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, GAP),
	}, root)

	-- small calm-red icon drawn with frames (16x16), sits left of a panel title
	local function headerIcon(panel, kind)
		local holder = new("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(14, (HEAD - 16) / 2),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)

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

		if kind == "plus" then
			bit(12, 2, 0, 0)
			bit(2, 12, 0, 0)
		elseif kind == "ring" then
			local r = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, holder)
			corner(r, 100)
			stroke(r, T.ACCENT, 2, 0)
			local dot = bit(4, 4, 0, 0)
			corner(dot, 100)
		else
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
	local panelState = {}
	local count = #PANELS

	for i = 1, count do
		local def = PANELS[i]

		-- the two side panels reach down level with the switcher bar; the middle one stops a little above it
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
		}, root)
		corner(panel, 6)
		stroke(panel, T.BORDER, 1, 0)

		headerIcon(panel, def.icon)
		label(panel, def.title, UDim2.fromOffset(40, 0), UDim2.new(1, -84, 0, HEAD),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR).ZIndex = 3

		-- badge on the right of the title: how many features are in this panel
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
		label(badge, tostring(def.count), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
			Enum.Font.GothamMedium, 12, T.ICON, Enum.TextXAlignment.Center).ZIndex = 4

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
		panelState[def.id] = { n = 0, o = 0 }
	end

	-- the next free place in a panel. From the second feature on, a thin red divider is added first.
	local function slot(pid)
		local st = panelState[pid]
		if st.n > 0 then
			st.o = st.o + 1
			new("Frame", {
				Name = "Divider",
				LayoutOrder = st.o,
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = T.ACCENT,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}, bodies[pid])
		end
		st.n = st.n + 1
		st.o = st.o + 1
		return st.o
	end

	---------------------------------------------------------------------
	-- THE CONTROLS (switch, drop-down, slider, colour picker, text box, note, button)
	---------------------------------------------------------------------
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

		local api = {}
		function api.set(v)
			on = v and true or false
			paint(true)
		end
		return api
	end

	-- a row with a name on the left and a small switch on the right
	local function makeToggleRow(parent2, order, title, startOn, onChange)
		local row = new("Frame", {
			Name = title .. "Toggle",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent2)
		label(row, title, UDim2.fromOffset(0, 0), UDim2.new(1, -50, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON)
		local sw = makeSwitch(row, startOn, onChange)
		return { row = row, set = sw.set }
	end

	-- the little chevron inside a drop-down / colour button (turns upside down while open, lights up on hover)
	local function makeChevron(btn)
		local C = { over = false, open = false, arms = {} }
		C.arrow = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -15, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, btn)
		local function addArm(x, rot)
			local a = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, 0),
				Size = UDim2.fromOffset(7, 2),
				Rotation = rot,
				BackgroundColor3 = T.DIM_TEXT,
				BorderSizePixel = 0,
			}, C.arrow)
			corner(a, 1)
			C.arms[#C.arms + 1] = a
		end
		addArm(-2.5, 45)
		addArm(2.5, -45)

		function C.paint()
			local c = T.DIM_TEXT
			if C.over or C.open then
				c = T.ICON_HOVER
			end
			for i = 1, #C.arms do
				TweenService:Create(C.arms[i], FAST, { BackgroundColor3 = c }):Play()
			end
			local rot = 0
			if C.open then
				rot = 180
			end
			TweenService:Create(C.arrow, SMOOTH, { Rotation = rot }):Play()
		end
		btn.MouseEnter:Connect(function()
			C.over = true
			C.paint()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			C.over = false
			C.paint()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		return C
	end

	-- a row with a title on the left and a drop-down on the right. The list opens INSIDE the panel (it pushes the
	-- rows below it down) and scrolls when it has more than 6 choices.
	local function makeDropdown(parent2, order, title, options, getValue, setValue)
		local R = { open = false }
		local fullH = #options * OPT_H + 6
		local listH = math.min(fullH, MAX_LIST)

		R.item = new("Frame", {
			Name = title .. "Row",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, parent2)
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
		local chev = makeChevron(btn)

		local list = new("Frame", {
			Position = UDim2.fromOffset(0, ROW_H + 4),
			Size = UDim2.new(1, 0, 0, listH),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.item)
		corner(list, 5)
		stroke(list, T.BORDER, 1, 0)
		local sc = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = T.BORDER,
			CanvasSize = UDim2.fromOffset(0, fullH),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
		}, list)

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
			chev.open = o
			local h = ROW_H
			if o then
				h = ROW_H + 4 + listH
			end
			TweenService:Create(R.item, FAST, { Size = UDim2.new(1, 0, 0, h) }):Play()
			chev.paint()
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
			}, sc)
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
			if not R.open then
				sc.CanvasPosition = Vector2.new(0, 0)
			end
			R.setOpen(not R.open)
		end)

		R.refresh()
		return R
	end

	-- a slider: the name on the left, the value on the right, a red bar with a white handle under them
	-- def = { name, min, max, step, fmt, get = function() return value end, set = function(value) end }
	local function makeSlider(parent2, order, def)
		local S = { def = def }
		S.row = new("Frame", {
			Name = def.name .. "Slider",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, SLIDER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent2)
		label(S.row, def.name, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 0, 18),
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
			local v = def.get()
			local fr = math.clamp((v - def.min) / (def.max - def.min), 0, 1)
			fill.Size = UDim2.new(fr, 0, 1, 0)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			valLbl.Text = string.format(def.fmt, v)
		end

		-- a dimmed slider (its feature is off) has a grey bar instead of the red one
		function S.dim(on)
			local c = T.DIM_TEXT
			if on then
				c = T.ACCENT
			end
			TweenService:Create(fill, FAST, { BackgroundColor3 = c }):Play()
		end

		function S.setFromX(px)
			local w = track.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local fr = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
			local v = def.min + math.floor(fr * (def.max - def.min) / def.step + 0.5) * def.step
			def.set(math.clamp(v, def.min, def.max))
			S.refresh()
		end

		function S.drag(input)
			S.setFromX(input.Position.X)
		end

		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragObj = S
				S.setFromX(input.Position.X)
			end
		end)

		S.refresh()
		return S
	end

	-- one drag handler for every slider and the colour picker
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if not dragObj then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragObj.drag(input)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragObj = nil
		end
	end)

	-- a row with a name on the left and a small text box on the right. onCommit(text) when the box loses focus.
	local function makeTextRow(parent2, order, title, startText, onCommit)
		local R = {}
		R.row = new("Frame", {
			Name = title .. "Row",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent2)
		label(R.row, title, UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON)
		local frame = new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(DD_W, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.row)
		corner(frame, 5)
		local st = stroke(frame, T.BORDER, 1, 0)
		R.box = new("TextBox", {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = startText,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
		}, frame)
		R.box.Focused:Connect(function()
			TweenService:Create(st, FAST, { Color = T.ACCENT }):Play()
		end)
		R.box.FocusLost:Connect(function()
			TweenService:Create(st, FAST, { Color = T.BORDER }):Play()
			onCommit(R.box.Text)
		end)
		return R
	end

	-- a wrapped line of small text (grey, or warning colour). Returns the label.
	local function makeNote(parent2, order, text, color)
		local n = label(parent2, text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0),
			Enum.Font.Gotham, 11, color or T.DIM_TEXT)
		n.LayoutOrder = order
		n.TextWrapped = true
		n.TextTruncate = Enum.TextTruncate.None
		n.TextYAlignment = Enum.TextYAlignment.Top
		n.AutomaticSize = Enum.AutomaticSize.Y
		return n
	end

	-- a full width button
	local function makeButtonRow(parent2, order, text, onClick)
		local b = new("TextButton", {
			Name = text .. "Button",
			LayoutOrder = order,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = text,
		}, parent2)
		corner(b, 5)
		stroke(b, T.BORDER, 1, 0)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		b.Activated:Connect(onClick)
		return b
	end

	-- a thin line between two groups of rows inside a settings box
	local function makeLine(parent2, order)
		return new("Frame", {
			Name = "Line",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, parent2)
	end

	-- COLOUR PICKER, inline: a row with the colour + hex on a button; the button opens a panel (inside the page)
	-- with the saturation / brightness square, a hue bar, an opacity bar and a hex + opacity text box.
	-- onChange(color, alpha) is called on every change.
	local WHITE = Color3.new(1, 1, 1)

	local function makeColorRow(parent2, order, title, getColor, getAlpha, onChange)
		local R = { open = false }
		R.item = new("Frame", {
			Name = title .. "Color",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, parent2)
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
		local mini = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = getColor(),
			BorderSizePixel = 0,
		}, btn)
		corner(mini, 3)
		stroke(mini, T.BORDER, 1, 0)
		local hexLbl = label(btn, "", UDim2.fromOffset(30, 0), UDim2.new(1, -48, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)
		local chev = makeChevron(btn)

		-- the opened panel
		local pk = new("Frame", {
			Position = UDim2.fromOffset(0, ROW_H + 4),
			Size = UDim2.new(1, 0, 0, PICK_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.item)
		corner(pk, 5)
		stroke(pk, T.BORDER, 1, 0)

		local h, s, v = getColor():ToHSV()
		local a = getAlpha()

		-- saturation (left to right) / brightness (top to bottom)
		local svBox = new("Frame", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 100),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			BorderSizePixel = 0,
		}, pk)
		corner(svBox, 4)
		local whiteOv = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, svBox)
		corner(whiteOv, 4)
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, whiteOv)
		local blackOv = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, svBox)
		corner(blackOv, 4)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}, blackOv)
		local svKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, svBox)
		corner(svKnob, 100)
		stroke(svKnob, WHITE, 2, 0)
		local svHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, svBox)

		-- hue bar
		local hueBar = new("Frame", {
			Position = UDim2.fromOffset(8, 116),
			Size = UDim2.new(1, -16, 0, 10),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, pk)
		corner(hueBar, 3)
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
		}, hueBar)
		local hueKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(6, 16),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, hueBar)
		corner(hueKnob, 2)
		stroke(hueKnob, T.BLACK, 1, 0.4)
		local hueHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(-4, -5),
			Size = UDim2.new(1, 8, 1, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, hueBar)

		-- opacity bar
		local alphaBar = new("Frame", {
			Position = UDim2.fromOffset(8, 136),
			Size = UDim2.new(1, -16, 0, 10),
			BackgroundColor3 = Color3.fromRGB(58, 58, 62),
			BorderSizePixel = 0,
		}, pk)
		corner(alphaBar, 3)
		local alphaOv = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, alphaBar)
		corner(alphaOv, 3)
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}, alphaOv)
		local alphaKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(6, 16),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, alphaBar)
		corner(alphaKnob, 2)
		stroke(alphaKnob, T.BLACK, 1, 0.4)
		local alphaHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(-4, -5),
			Size = UDim2.new(1, 8, 1, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, alphaBar)

		-- hex + opacity text boxes (same look as the key box / text rows)
		local function makeBox(pos, size, anchor, text, align)
			local f = new("Frame", {
				AnchorPoint = anchor,
				Position = pos,
				Size = size,
				BackgroundColor3 = T.WELL,
				BorderSizePixel = 0,
			}, pk)
			corner(f, 4)
			local st = stroke(f, T.BORDER, 1, 0)
			local tb = new("TextBox", {
				Size = UDim2.new(1, -12, 1, 0),
				Position = UDim2.fromOffset(6, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Text = text,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = T.TEXT_COLOR,
				TextXAlignment = align,
			}, f)
			tb.Focused:Connect(function()
				TweenService:Create(st, FAST, { Color = T.ACCENT }):Play()
			end)
			tb.FocusLost:Connect(function()
				TweenService:Create(st, FAST, { Color = T.BORDER }):Play()
			end)
			return tb
		end
		local hexBox = makeBox(UDim2.fromOffset(8, 156), UDim2.new(1, -86, 0, 24), Vector2.new(0, 0), "#FFFFFF",
			Enum.TextXAlignment.Left)
		local alphaBox = makeBox(UDim2.new(1, -8, 0, 156), UDim2.fromOffset(62, 24), Vector2.new(1, 0), "100%",
			Enum.TextXAlignment.Center)

		local function refresh(fire)
			local c = Color3.fromHSV(h, s, v)
			svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svKnob.Position = UDim2.new(s, 0, 1 - v, 0)
			svKnob.BackgroundColor3 = c
			hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
			alphaOv.BackgroundColor3 = c
			alphaKnob.Position = UDim2.new(a, 0, 0.5, 0)
			mini.BackgroundColor3 = c
			local hex = string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
			hexLbl.Text = hex
			if not hexBox:IsFocused() then
				hexBox.Text = hex
			end
			if not alphaBox:IsFocused() then
				alphaBox.Text = tostring(math.floor(a * 100 + 0.5)) .. "%"
			end
			if fire then
				onChange(c, a)
			end
		end

		local function fromPointer(kind, p)
			if kind == "sv" then
				local pos = svBox.AbsolutePosition
				local sz = svBox.AbsoluteSize
				if sz.X > 0 and sz.Y > 0 then
					s = math.clamp((p.X - pos.X) / sz.X, 0, 1)
					v = 1 - math.clamp((p.Y - pos.Y) / sz.Y, 0, 1)
				end
			elseif kind == "hue" then
				local pos = hueBar.AbsolutePosition
				local sz = hueBar.AbsoluteSize
				if sz.X > 0 then
					h = math.clamp((p.X - pos.X) / sz.X, 0, 1)
				end
			else
				local pos = alphaBar.AbsolutePosition
				local sz = alphaBar.AbsoluteSize
				if sz.X > 0 then
					a = math.clamp((p.X - pos.X) / sz.X, 0, 1)
				end
			end
			refresh(true)
		end

		local function bindDrag(hitBtn, kind)
			hitBtn.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					dragObj = {
						drag = function(inp)
							fromPointer(kind, pointerPos(inp))
						end,
					}
					fromPointer(kind, pointerPos(input))
				end
			end)
		end
		bindDrag(svHit, "sv")
		bindDrag(hueHit, "hue")
		bindDrag(alphaHit, "alpha")

		hexBox.FocusLost:Connect(function()
			local hex = string.match(hexBox.Text, "^%s*#?(%x+)%s*$")
			if hex and #hex == 3 then
				hex = string.gsub(hex, ".", function(ch)
					return ch .. ch
				end)
			end
			if hex and #hex >= 6 then
				local r = tonumber(string.sub(hex, 1, 2), 16)
				local g = tonumber(string.sub(hex, 3, 4), 16)
				local b = tonumber(string.sub(hex, 5, 6), 16)
				if r and g and b then
					h, s, v = Color3.fromRGB(r, g, b):ToHSV()
				end
			end
			refresh(true)
		end)
		alphaBox.FocusLost:Connect(function()
			local n = tonumber(string.match(alphaBox.Text, "[%d%.]+"))
			if n then
				a = math.clamp(n / 100, 0, 1)
			end
			refresh(true)
		end)

		function R.setOpen(o)
			R.open = o
			chev.open = o
			local hh = ROW_H
			if o then
				hh = ROW_H + 4 + PICK_H
			end
			TweenService:Create(R.item, FAST, { Size = UDim2.new(1, 0, 0, hh) }):Play()
			chev.paint()
		end
		btn.Activated:Connect(function()
			R.setOpen(not R.open)
		end)

		refresh(false)
		return R
	end

	---------------------------------------------------------------------
	-- ONE FEATURE = ONE SECTION INSIDE A PANEL: name + switch on top, the settings in one inset box under it
	---------------------------------------------------------------------
	local function newSection(pid, title, withSwitch, onSwitch)
		local S = { body = bodies[pid] }
		local order = slot(pid)
		S.outer = new("Frame", {
			Name = "Section",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, bodies[pid])
		local sec = new("Frame", {
			Name = "Content",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, S.outer)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}, sec)

		local head = new("Frame", {
			Name = "Header",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, sec)
		label(head, title, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 1, 0),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		if withSwitch then
			S.switch = makeSwitch(head, false, onSwitch)
		end

		S.box = new("Frame", {
			Name = "Settings",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = T.WELL,
			BorderSizePixel = 0,
		}, sec)
		corner(S.box, 6)
		stroke(S.box, T.BORDER, 1, 0)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, BOX_PAD),
			PaddingRight = UDim.new(0, BOX_PAD),
			PaddingTop = UDim.new(0, BOX_PAD),
			PaddingBottom = UDim.new(0, BOX_PAD),
		}, S.box)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, BOX_GAP),
		}, S.box)

		local bn = 0
		function S.order()
			bn = bn + 1
			return bn
		end
		return S
	end

	-- findable from the search box: Find switches to the Extras page, scrolls the panel to the feature and
	-- flashes its settings box in red. S = { outer, box, body }
	local function register(id, title, S)
		if type(ctx) ~= "table" or not ctx.Win or type(ctx.Win.AddSearch) ~= "function" then
			return
		end
		ctx.Win:AddSearch({
			owner = "Misc",
			title = title,
			tab = "Misc",
			keywords = SEARCH_WORDS[id] or "",
			go = function()
				if type(ctx.Win.MiscShow) == "function" then
					ctx.Win.MiscShow("Extras")
				end
				task.spawn(function()
					-- the page was hidden a moment ago: let it lay itself out first
					task.wait(0.06)
					if not running or not S.outer or not S.outer.Parent then
						return
					end
					local body = S.body
					local sc = 1
					if ctx.Win.Window then
						local us = ctx.Win.Window:FindFirstChildOfClass("UIScale")
						if us and us.Scale > 0 then
							sc = us.Scale
						end
					end
					local y = (S.outer.AbsolutePosition.Y - body.AbsolutePosition.Y) / sc + body.CanvasPosition.Y - 10
					local maxY = math.max(0, (body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y) / sc)
					TweenService:Create(body, SMOOTH, { CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY)) }):Play()
					local st = nil
					if S.box then
						st = S.box:FindFirstChildOfClass("UIStroke")
					end
					if st then
						st.Color = T.ACCENT
						st.Thickness = 2
						TweenService:Create(st, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ Color = T.BORDER, Thickness = 1 }):Play()
					end
				end)
			end,
		})
	end

	-- builds one of the spoofer files (spoofers/spoofer1.lua, spoofers/spoofer2.lua) into a panel.
	-- Returns its handle ({ Root, Box, Unload }) or nil.
	local function buildSpoofer(pid, id, title, ctxKey, genvKey, fileName)
		local order = slot(pid)
		local holder = new("Frame", {
			Name = id .. "Holder",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, bodies[pid])

		local handle = nil
		local mod, whyNot = findModule(ctxKey, genvKey, fileName)
		if not mod and whyNot then
			warn("[misc2] " .. fileName .. ": " .. whyNot)
		end
		if mod then
			local ok, res = pcall(mod.build, holder, T, H, ctx)
			if ok and type(res) == "table" then
				handle = res
			else
				warn("[misc2] " .. fileName .. " failed: " .. tostring(res))
			end
		end

		if not handle then
			-- the panel stays complete: a name and a hint on why there is nothing to switch
			holder.AutomaticSize = Enum.AutomaticSize.None
			holder.Size = UDim2.new(1, 0, 0, 52)
			label(holder, title, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 0, HEADER_H),
				Enum.Font.GothamBold, 14, T.TEXT_COLOR)
			label(holder, fileName .. " is not loaded", UDim2.fromOffset(2, 32), UDim2.new(1, 0, 0, 16),
				Enum.Font.Gotham, 11, T.WARN)
		end

		local box = holder
		if handle and typeof(handle.Box) == "Instance" then
			box = handle.Box
		end
		register(id, title, { outer = holder, box = box, body = bodies[pid] })
		return handle
	end

	---------------------------------------------------------------------
	-- shared by the Hitbox Expander and the Orbit: Zee Hood knocked-out check
	-- (the K.O bool lives at <character>.BodyEffects["K.O"]; characters are in workspace.Players)
	---------------------------------------------------------------------
	local function isKnocked(char)
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
		if be then
			local ko = be:FindFirstChild("K.O")
			if ko and ko:IsA("BoolValue") then
				return ko.Value
			end
		end
		return false
	end

	---------------------------------------------------------------------
	-- ZEE HOOD EXTRAS: BULLET TRACER / HIT SOUNDS / HIT MARKERS
	---------------------------------------------------------------------
	do
		local tracers = {}
	-- tracer settings
	local S = {
		enabled = false,
		color = Color3.fromRGB(255, 220, 120),
		alpha = 0.8,            -- opacity of the tracer when it appears (1 = bright)
		width = 0.08,
		fade = 2.5,             -- seconds
		material = "Neon",
		easing = "Linear",
		rainbow = false,
		rainbowSpeed = 5,
	}

	-- hit sound settings
	local SOUNDS = {
		{ "Minecraft Bow", "135478009117226" },
		{ "Undertale", "140721035016341" },
		{ "Critical", "137392628136734" },
		{ "Punch", "138208560796742" },
		{ "Rock", "82708037443413" },
		{ "DANG", "135602581462761" },
		{ "Retro", "109681634329245" },
		{ "Spear", "135278368445325" },
		{ "Doom", "137176923000279" },
	}
	local SOUND_NAMES = {}
	for i = 1, #SOUNDS do
		SOUND_NAMES[i] = SOUNDS[i][1]
	end
	local HIT_MODES = { "On Shot", "On Hit" }

	local HS = {
		enabled = false,
		soundIndex = 1,
		mode = "On Hit",
		volume = 1,
		muteGun = false,   -- mute the game's own gun sound for YOUR gun while Hit Sounds is on
	}

	-- hit marker settings (speed 1 = text stays about 3s, 10 = about 0.3s)
	local HM = {
		enabled = false,
		speed = 3,
	}

	local OWN_RANGE = 15        -- a bullet has to start this close to your character to count as yours
	local MAX_TRACERS = 100
	local MATERIALS = { "Neon", "Glass", "SmoothPlastic", "ForceField" }
	local EASINGS = { "Linear", "Quad", "Sine", "Exponential" }
	local lastPlay = 0

	local function playHitSound(preview)
		local now = os.clock()
		if not preview and now - lastPlay < 0.05 then
			return
		end
		lastPlay = now
		local entry = SOUNDS[HS.soundIndex]
		if not entry then
			return
		end
		local snd = Instance.new("Sound")
		snd.Name = "ExtraHitSound"
		snd.SoundId = "rbxassetid://" .. entry[2]
		snd.Volume = HS.volume
		snd.Parent = SoundService
		snd.Ended:Connect(function()
			snd:Destroy()
		end)
		snd:Play()
		Debris:AddItem(snd, 15)
	end

	local function preloadCurrent()
		local entry = SOUNDS[HS.soundIndex]
		if not entry then
			return
		end
		task.spawn(function()
			local snd = Instance.new("Sound")
			snd.SoundId = "rbxassetid://" .. entry[2]
			pcall(function()
				ContentProvider:PreloadAsync({ snd })
			end)
			snd:Destroy()
		end)
	end
	local hooked = false
	local trackHit = nil   -- filled in below (the hit marker code); called by both hit detectors
	local gspTable = nil
	local gspOriginal = nil
	local gspFn = nil
	local hookGH = nil
	local hookOriginal = nil
	local hookFn = nil

	-- the Humanoid of the living character inst belongs to (not you), or nil
	local function enemyHumanoid(inst)
		if typeof(inst) ~= "Instance" then
			return nil
		end
		local myChar = player.Character
		if myChar and inst:IsDescendantOf(myChar) then
			return nil
		end
		local m = inst
		while m and m ~= workspace and m ~= game do
			if m:IsA("Model") then
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum then
					if hum.Health > 0 then
						return hum
					end
					return nil
				end
			end
			m = m.Parent
		end
		return nil
	end

	-- the params table passed to GunHandler.Shoot (it has a Shooter field)
	local function findParams(...)
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "table" and v.Shooter ~= nil then
				return v
			end
		end
		return nil
	end

	-- true when this Shoot call is a real shot fired by YOUR character
	local function isMyShot(params)
		local myChar = player.Character
		if not myChar then
			return false
		end
		if params.Shooter ~= myChar then
			return false
		end
		if params.Replay == true or params.IsReflecting then
			return false
		end
		return true
	end

	-- wrap GunHandler.Shoot (the gun script you sent). Done in the background so the page appears at once.
	task.spawn(function()
		local ok, gh = pcall(function()
			local mods = ReplicatedStorage:WaitForChild("Modules", 10)
			local m = mods:WaitForChild("GunHandler", 10)
			return require(m)
		end)
		if not running then
			return
		end
		if not ok or type(gh) ~= "table" or type(gh.Shoot) ~= "function" then
			return -- the BULLET_RAYS fallback below will be used instead
		end

		local original = gh.Shoot
		local function hook(...)
			local params = findParams(...)
			local mine = false
			if running and (HS.enabled or HM.enabled) and params ~= nil then
				mine = isMyShot(params)
			end

			-- On Shot: play right away, before the gun script does its (slow) effects work
			if mine and HS.enabled and HS.mode == "On Shot" then
				pcall(playHitSound, false)
			end

			-- Shoot returns: hit position, the instance that was hit, hit normal
			local r1, r2, r3 = original(...)

			-- only when MY shot hit another character: hit sound (On Hit) and hit marker
			if mine then
				local hum = enemyHumanoid(r2)
				if hum then
					if HS.enabled and HS.mode == "On Hit" then
						pcall(playHitSound, false)
					end
					if HM.enabled and trackHit then
						pcall(trackHit, hum, r2)
					end
				end
			end

			return r1, r2, r3
		end

		hookGH = gh
		hookOriginal = original
		hookFn = hook
		gh.Shoot = hook
		hooked = true
	end)

	-- wrap GunSoundPlay.SoundPlay (the gun script calls it for every shot). While Mute Gun Sounds is on,
	-- shots from YOUR gun make no normal sound, so only your hit sound plays. Other players' guns are untouched.
	task.spawn(function()
		local ok, gsp = pcall(function()
			return require(ReplicatedStorage:WaitForChild("GunSoundPlay", 10))
		end)
		if not running then
			return
		end
		if not ok or type(gsp) ~= "table" or type(gsp.SoundPlay) ~= "function" then
			return
		end
		local origSound = gsp.SoundPlay
		local function muted(handle, ...)
			if running and HS.enabled and HS.muteGun and typeof(handle) == "Instance" then
				local myChar = player.Character
				if myChar and handle:IsDescendantOf(myChar) then
					return
				end
			end
			return origSound(handle, ...)
		end
		gspTable = gsp
		gspOriginal = origSound
		gspFn = muted
		gsp.SoundPlay = muted
	end)

	-- fallback when GunHandler could not be wrapped: watch BULLET_RAYS parts and re-check the path
	local function onBulletForSound(bulletPart)
		task.wait()
		if not running or not (HS.enabled or HM.enabled) or hooked or not bulletPart.Parent then
			return
		end
		local char = player.Character
		if not char then
			return
		end

		local mine = false
		local owner = bulletPart:GetAttribute("OwnerCharacter")
		if owner ~= nil then
			mine = (owner == char.Name)
		else
			local rp = char:FindFirstChild("HumanoidRootPart")
			if rp and (rp.Position - bulletPart.Position).Magnitude <= OWN_RANGE then
				mine = true
			end
		end
		if not mine then
			return
		end

		if HS.enabled and HS.mode == "On Shot" then
			playHitSound(false)
		end
		local wantHit = HM.enabled or (HS.enabled and HS.mode == "On Hit")
		if not wantHit then
			return
		end

		-- On Hit: how long is the bullet, then raycast along it
		local distance = 0
		local kids = bulletPart:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("Attachment") then
				distance = math.max(distance, math.abs(kids[i].Position.Z))
			end
		end
		if distance < 1 then
			return
		end
		local rayParams = RaycastParams.new()
		local exclude = { char }
		local ign = workspace:FindFirstChild("Ignored")
		if ign then
			exclude[#exclude + 1] = ign
		end
		rayParams.FilterDescendantsInstances = exclude
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.IgnoreWater = true
		local res = workspace:Raycast(bulletPart.Position, bulletPart.CFrame.LookVector * (distance + 1), rayParams)
		local hum = nil
		if res then
			hum = enemyHumanoid(res.Instance)
		end
		if hum then
			if HS.enabled and HS.mode == "On Hit" then
				playHitSound(false)
			end
			if HM.enabled and trackHit then
				pcall(trackHit, hum, res.Instance)
			end
		end
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and (HS.enabled or HM.enabled) and not hooked and d.Name == "BULLET_RAYS" and d:IsA("BasePart") then
			task.spawn(onBulletForSound, d)
		end
	end)
	local function effectsParent()
		local ignored = workspace:FindFirstChild("Ignored")
		if not ignored then
			return workspace
		end
		local fx = ignored:FindFirstChild("BulletEffects")
		if not fx then
			fx = Instance.new("Folder")
			fx.Name = "BulletEffects"
			fx.Parent = ignored
		end
		return fx
	end

	-- HIT MARKERS: red damage text next to the player you hit.
	-- The text lives in a BillboardGui whose size is in studs, so it shrinks with distance and grows
	-- when the target is close.
	local pendingHits = setmetatable({}, { __mode = "k" })

	local function showMarker(target, dmg)
		local cam = workspace.CurrentCamera
		local right = Vector3.new(1, 0, 0)
		if cam then
			right = cam.CFrame.RightVector
		end
		local side = 2.6 + (math.random() - 0.5) * 0.8
		local up = 1.4 + math.random() * 0.7
		local startPos = target.Position + right * side + Vector3.new(0, up, 0)
		local dur = 3 / math.max(1, HM.speed)

		local anchor = Instance.new("Part")
		anchor.Name = "HitMarker"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = startPos
		anchor.Parent = effectsParent()

		local gui = Instance.new("BillboardGui")
		gui.Name = "HitMarkerGui"
		gui.Adornee = anchor
		gui.Size = UDim2.fromScale(5, 2.2)   -- scale = studs, that is what makes it size with distance
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = anchor

		local txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.Size = UDim2.fromScale(1, 1)
		txt.Font = Enum.Font.GothamBlack
		txt.TextScaled = true
		txt.Text = "-" .. tostring(math.floor(dmg + 0.5))
		txt.TextColor3 = Color3.fromRGB(255, 50, 50)
		txt.TextStrokeColor3 = Color3.fromRGB(20, 0, 0)
		txt.TextStrokeTransparency = 0.25
		txt.Parent = gui

		TweenService:Create(txt, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			Position = startPos + Vector3.new(0, 1.5, 0),
		}):Play()
		Debris:AddItem(anchor, dur + 0.2)
	end

	-- called when one of YOUR shots hits a character: watch its health for a moment and show every
	-- drop as a number (shotgun pellets that land one after another each get their own number)
	trackHit = function(hum, part)
		if not HM.enabled then
			return
		end
		local target = part
		local model = hum.Parent
		if model then
			local hrp2 = model:FindFirstChild("HumanoidRootPart")
			if hrp2 and hrp2:IsA("BasePart") then
				target = hrp2
			end
		end
		if not target or not target:IsA("BasePart") then
			return
		end

		local now = os.clock()
		local rec = pendingHits[hum]
		if rec then
			rec.expire = now + 0.8
			rec.target = target
			return
		end

		rec = { last = hum.Health, expire = now + 0.8, target = target }
		pendingHits[hum] = rec
		local c = hum.HealthChanged:Connect(function(newHealth)
			local d = rec.last - newHealth
			rec.last = newHealth
			if running and HM.enabled and d >= 1 and os.clock() <= rec.expire then
				pcall(showMarker, rec.target, d)
			end
		end)
		task.spawn(function()
			while running and hum.Parent and os.clock() < rec.expire do
				task.wait(0.05)
			end
			c:Disconnect()
			pendingHits[hum] = nil
		end)
	end

	-- cf = the middle of the tracer (already moved halfway along the shot)
	local function spawnTracer(cf, length)
		local mat = Enum.Material.Neon
		pcall(function()
			mat = Enum.Material[S.material]
		end)
		local style = Enum.EasingStyle.Linear
		pcall(function()
			style = Enum.EasingStyle[S.easing]
		end)

		local color = S.color
		if S.rainbow then
			color = Color3.fromHSV((os.clock() * S.rainbowSpeed * 0.1) % 1, 1, 1)
		end

		local t = Instance.new("Part")
		t.Name = "BulletTracer"
		t.Anchored = true
		t.CanCollide = false
		t.CanTouch = false
		t.CanQuery = false
		t.CastShadow = false
		t.Material = mat
		t.Color = color
		t.Transparency = 1 - S.alpha
		t.Size = Vector3.new(S.width, S.width, length)
		t.CFrame = cf
		t.Parent = effectsParent()

		tracers[#tracers + 1] = t
		while #tracers > MAX_TRACERS do
			local old = table.remove(tracers, 1)
			if old and old.Parent then
				old:Destroy()
			end
		end

		TweenService:Create(t, TweenInfo.new(S.fade, style, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
		Debris:AddItem(t, S.fade + 0.1)
	end

	local function onBullet(bulletPart)
		-- wait a frame so the gun script finishes adding its attachments
		task.wait()
		if not running or not S.enabled or not bulletPart.Parent then
			return
		end

		-- only your own shots: the bullet has to start next to your character
		local char = player.Character
		local rp = nil
		if char then
			rp = char:FindFirstChild("HumanoidRootPart")
		end
		if not rp or (rp.Position - bulletPart.Position).Magnitude > OWN_RANGE then
			return
		end

		-- the end attachment sits at Z = -distance from the muzzle
		local distance = 0
		local kids = bulletPart:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("Attachment") then
				distance = math.max(distance, math.abs(kids[i].Position.Z))
			end
		end
		if distance < 1 then
			return
		end

		spawnTracer(bulletPart.CFrame * CFrame.new(0, 0, -distance / 2), distance)
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and S.enabled and d.Name == "BULLET_RAYS" and d:IsA("BasePart") then
			task.spawn(onBullet, d)
		end
	end)

		-- BULLET TRACER
		do
			local sec = newSection("ZeeHood", "Bullet Tracer", true, function(on)
				S.enabled = on
			end)
			local b = sec.box
			local o = sec.order
			makeColorRow(b, o(), "Color", function()
				return S.color
			end, function()
				return S.alpha
			end, function(c, al)
				S.color = c
				S.alpha = al
			end)
			makeDropdown(b, o(), "Material", MATERIALS, function()
				return S.material
			end, function(val)
				S.material = val
			end)
			makeDropdown(b, o(), "Fade Style", EASINGS, function()
				return S.easing
			end, function(val)
				S.easing = val
			end)
			makeSlider(b, o(), { name = "Thickness", min = 0.01, max = 1, step = 0.01, fmt = "%.2f",
				get = function() return S.width end, set = function(val) S.width = val end })
			makeSlider(b, o(), { name = "Duration", min = 0.1, max = 10, step = 0.1, fmt = "%.1fs",
				get = function() return S.fade end, set = function(val) S.fade = val end })
			local rainbowSpeed = nil
			makeToggleRow(b, o(), "Rainbow", S.rainbow, function(on)
				S.rainbow = on
				rainbowSpeed.dim(on)
			end)
			rainbowSpeed = makeSlider(b, o(), { name = "Rainbow Speed", min = 1, max = 20, step = 1, fmt = "%d",
				get = function() return S.rainbowSpeed end, set = function(val) S.rainbowSpeed = val end })
			rainbowSpeed.dim(S.rainbow)
			register("tracer", "Bullet Tracer", sec)
		end

		-- HIT SOUNDS
		do
			local sec = newSection("ZeeHood", "Hit Sounds", true, function(on)
				HS.enabled = on
				if on then
					preloadCurrent()
				end
			end)
			local b = sec.box
			local o = sec.order
			makeDropdown(b, o(), "Sound", SOUND_NAMES, function()
				return SOUND_NAMES[HS.soundIndex]
			end, function(val)
				for i = 1, #SOUND_NAMES do
					if SOUND_NAMES[i] == val then
						HS.soundIndex = i
					end
				end
				preloadCurrent()
				playHitSound(true)   -- preview the sound you just picked
			end)
			makeDropdown(b, o(), "Play On", HIT_MODES, function()
				return HS.mode
			end, function(val)
				HS.mode = val
			end)
			makeSlider(b, o(), { name = "Volume", min = 0.1, max = 3, step = 0.1, fmt = "%.1f",
				get = function() return HS.volume end, set = function(val) HS.volume = val end })
			makeToggleRow(b, o(), "Mute Gun Sounds", HS.muteGun, function(on)
				HS.muteGun = on
			end)
			register("sounds", "Hit Sounds", sec)
		end

		-- HIT MARKERS
		do
			local sec = newSection("ZeeHood", "Hit Markers", true, function(on)
				HM.enabled = on
			end)
			local b = sec.box
			local o = sec.order
			makeSlider(b, o(), { name = "Fade Speed", min = 1, max = 10, step = 1, fmt = "%d",
				get = function() return HM.speed end, set = function(val) HM.speed = val end })
			register("markers", "Hit Markers", sec)
		end

		unloaders[#unloaders + 1] = function()
			S.enabled = false
			HS.enabled = false
			HM.enabled = false
			-- put GunHandler.Shoot back the way it was (only if nobody wrapped it after us)
			if hookGH and hookFn and hookGH.Shoot == hookFn then
				pcall(function()
					hookGH.Shoot = hookOriginal
				end)
			end
			-- put GunSoundPlay.SoundPlay back the way it was
			if gspTable and gspFn and gspTable.SoundPlay == gspFn then
				pcall(function()
					gspTable.SoundPlay = gspOriginal
				end)
			end
			for i = 1, #tracers do
				local t = tracers[i]
				if t and t.Parent then
					pcall(function()
						t:Destroy()
					end)
				end
			end
			tracers = {}
		end
	end

	---------------------------------------------------------------------
	-- ZEE HOOD EXTRAS: AUTO BUY (Armor / Stim / Food)
	---------------------------------------------------------------------
	do
	local ARMOR_TAG = "[Full Armor]"
	local STIM_TAG = "[Stim]"
	local COOLDOWN = 0       -- 0 = click every frame (fastest). Raise it (like 0.1) if purchases get ignored.
	local ARMOR_LIMIT = 150  -- Auto Buy Armor stops while your armor is at or above this
		local AB = {
			armor = { enabled = false, range = 12 },
			stim = { enabled = false, range = 12 },
			food = { enabled = false, range = 12 },
		}
		local lastBuy = setmetatable({}, { __mode = "k" })
	local hasClick = false
	pcall(function()
		hasClick = (type(fireclickdetector) == "function")
	end)
	local function kindOf(name)
		if string.sub(name, 1, #ARMOR_TAG) == ARMOR_TAG then
			return "armor"
		end
		if string.sub(name, 1, #STIM_TAG) == STIM_TAG then
			return "stim"
		end
		return "food"
	end

	-- left click on the model's Head
	local function clickHead(model, head)
		local cd = head:FindFirstChildOfClass("ClickDetector")
		if not cd then
			cd = model:FindFirstChildWhichIsA("ClickDetector", true)
		end
		if not cd then
			return
		end
		pcall(function()
			fireclickdetector(cd)
		end)
	end

	-- your armor: workspace.Players.<your name>.BodyEffects.Armor (falls back to your character)
	local function armorValue()
		local me = nil
		local folder = workspace:FindFirstChild("Players")
		if folder then
			me = folder:FindFirstChild(player.Name)
		end
		if not me then
			me = player.Character
		end
		local be = nil
		if me then
			be = me:FindFirstChild("BodyEffects")
		end
		local armor = nil
		if be then
			armor = be:FindFirstChild("Armor")
		end
		if armor and type(armor.Value) == "number" then
			return armor.Value
		end
		return 0
	end

	local function step()
		if not (AB.armor.enabled or AB.stim.enabled or AB.food.enabled) then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			return
		end

		local ignored = workspace:FindFirstChild("Ignored")
		local shop = nil
		if ignored then
			shop = ignored:FindFirstChild("Shop")
		end
		if not shop then
			return
		end

		-- armor buying pauses while your armor is at or above the limit (starts again when it drops)
		local armorFull = false
		if AB.armor.enabled and armorValue() >= ARMOR_LIMIT then
			armorFull = true
		end

		local now = os.clock()
		local kids = shop:GetChildren()
		for i = 1, #kids do
			local model = kids[i]
			if model:IsA("Model") then
				local kind = kindOf(model.Name)
				local st = AB[kind]
				if st.enabled and not (kind == "armor" and armorFull) then
					local head = model:FindFirstChild("Head")
					if head and head:IsA("BasePart") then
						local last = lastBuy[model]
						if (not last or now - last >= COOLDOWN)
							and (head.Position - hrp.Position).Magnitude <= st.range then
							lastBuy[model] = now
							clickHead(model, head)
						end
					end
				end
			end
		end
	end

	-- checked every frame so it reacts the moment you are in range
	conns[#conns + 1] = game:GetService("RunService").Heartbeat:Connect(function()
		if running then
			pcall(step)
		end
	end)

		local sec = newSection("ZeeHood", "Auto Buy", false, nil)
		local b = sec.box
		local o = sec.order
		local OPTS = {
			{ key = "armor", title = "Auto Buy Armor" },
			{ key = "stim", title = "Auto Buy Stim" },
			{ key = "food", title = "Auto Buy Food" },
		}
		for i = 1, #OPTS do
			local opt = OPTS[i]
			if i > 1 then
				makeLine(b, o())
			end
			makeToggleRow(b, o(), opt.title, false, function(on)
				AB[opt.key].enabled = on
			end)
			makeSlider(b, o(), { name = "Range", min = 3, max = 15, step = 1, fmt = "%d",
				get = function() return AB[opt.key].range end,
				set = function(val) AB[opt.key].range = val end })
		end
		if not hasClick then
			makeNote(b, o(), "Your executor has no fireclickdetector, so buying will not work.", T.WARN)
		end
		register("autobuy", "Auto Buy", sec)

		unloaders[#unloaders + 1] = function()
			AB.armor.enabled = false
			AB.stim.enabled = false
			AB.food.enabled = false
		end
	end

	---------------------------------------------------------------------
	-- EXTRA NEEDS: ORBIT
	---------------------------------------------------------------------
	do
	local OB = {
		enabled = false,
		key = nil,
		visualize = false,
		speed = 6,
		dist = 12,
		target = nil,
		angle = 0,
		listening = false,
		teamCheck = false,
		knockedCheck = false,
	}
	local obRadius = -1
	local obRing = nil
	local obDashes = {}
		local keyBtn = nil

		-- the Keybinds panel on the left of the window shows Orbit while you are orbiting somebody
		local function syncOrbitHint()
			local win = nil
			if type(ctx) == "table" then
				win = ctx.Win
			end
			if not win or type(win.SetHint) ~= "function" then
				return
			end
			if OB.target then
				win:SetHint("Orbit", { title = "Orbit", key = shortKey(OB.key), active = true })
			else
				win:SetHint("Orbit", nil)
			end
		end

		local function refreshObStatus()
			syncOrbitHint()
		end

	local function hideRing()
		if obRing then
			pcall(function()
				obRing:Destroy()
			end)
		end
		obRing = nil
		obDashes = {}
		obRadius = -1
	end

	local function stopOrbit()
		OB.target = nil
		refreshObStatus()
	end

		local sec = newSection("Needs", "Orbit", true, function(on)
			OB.enabled = on
			if not on then
				stopOrbit()
			end
			refreshObStatus()
		end)
		local b = sec.box
		local o = sec.order

		-- keybind: click it, then press a key (Escape = none). Pressing the key starts / stops orbiting.
		local kr = new("Frame", {
			Name = "KeybindRow",
			LayoutOrder = o(),
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, b)
		label(kr, "Keybind", UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON)
		keyBtn = new("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(DD_W, ROW_H),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = "None",
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, kr)
		corner(keyBtn, 5)
		stroke(keyBtn, T.BORDER, 1, 0)
		keyBtn.MouseEnter:Connect(function()
			TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		keyBtn.MouseLeave:Connect(function()
			TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		keyBtn.Activated:Connect(function()
			if OB.listening then
				OB.listening = false
				if OB.key then
					keyBtn.Text = OB.key.Name
				else
					keyBtn.Text = "None"
				end
				return
			end
			OB.listening = true
			keyBtn.Text = "Press a key..."
		end)

		makeToggleRow(b, o(), "Visualize", OB.visualize, function(on)
			OB.visualize = on
			if not on then
				hideRing()
			end
		end)
		makeToggleRow(b, o(), "Team Check", OB.teamCheck, function(on)
			OB.teamCheck = on
		end)
		makeToggleRow(b, o(), "Knocked Check", OB.knockedCheck, function(on)
			OB.knockedCheck = on
		end)
		makeSlider(b, o(), { name = "Speed", min = 1, max = 100, step = 1, fmt = "%d",
			get = function() return OB.speed end, set = function(val) OB.speed = val end })
		makeSlider(b, o(), { name = "Distance", min = 3, max = 200, step = 1, fmt = "%d",
			get = function() return OB.dist end, set = function(val) OB.dist = val end })
		register("orbit", "Orbit", sec)

	-- true when this player must not be orbited (Team Check / Knocked Check)
	local function obSkip(p)
		if OB.teamCheck and p.Team ~= nil and player.Team ~= nil and p.Team == player.Team then
			return true
		end
		if OB.knockedCheck and p.Character and isKnocked(p.Character) then
			return true
		end
		return false
	end

	-- the player closest to the mouse (on screen), else the nearest one in the world
	local function pickTarget()
		local char = player.Character
		local mroot = nil
		if char then
			mroot = char:FindFirstChild("HumanoidRootPart")
		end
		if not mroot then
			return nil
		end
		local cam = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local bestScreen = nil
		local bestScreenD = math.huge
		local bestWorld = nil
		local bestWorldD = math.huge
		local list = Players:GetPlayers()
		for i = 1, #list do
			local p = list[i]
			if p ~= player and p.Character and not obSkip(p) then
				local hrp = p.Character:FindFirstChild("HumanoidRootPart")
				local hum = p.Character:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local wd = (hrp.Position - mroot.Position).Magnitude
					if wd < bestWorldD then
						bestWorldD = wd
						bestWorld = p
					end
					if cam then
						local v, on = cam:WorldToViewportPoint(hrp.Position)
						if on then
							local sd = (Vector2.new(v.X, v.Y) - mouse).Magnitude
							if sd < bestScreenD then
								bestScreenD = sd
								bestScreen = p
							end
						end
					end
				end
			end
		end
		return bestScreen or bestWorld
	end

	local function startOrbit()
		local p = pickTarget()
		if not p then
			return
		end
		local char = player.Character
		local mroot = nil
		if char then
			mroot = char:FindFirstChild("HumanoidRootPart")
		end
		local thrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not mroot or not thrp then
			return
		end
		OB.target = p
		local d = mroot.Position - thrp.Position
		OB.angle = math.atan2(d.Z, d.X)
		refreshObStatus()
	end

	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if OB.listening then
			OB.listening = false
			if input.KeyCode == Enum.KeyCode.Escape then
				OB.key = nil
				keyBtn.Text = "None"
			else
				OB.key = input.KeyCode
				keyBtn.Text = input.KeyCode.Name
			end
			return
		end
		if processed or not OB.enabled or not OB.key then
			return
		end
		if input.KeyCode == OB.key then
			if OB.target then
				stopOrbit()
			else
				startOrbit()
			end
		end
	end)

	-- dashed circle made of real thin neon parts lying flat at hip height
	-- (real parts always render, unlike adornments, and are moved every frame to follow the target)
	local function updateRing(center)
		if not OB.visualize or not center then
			hideRing()
			return
		end
		local r = OB.dist
		local count = math.clamp(math.floor(r * 1.6), 20, 140)
		if not obRing or not obRing.Parent or obRadius ~= r then
			hideRing()
			obRadius = r
			obRing = Instance.new("Folder")
			obRing.Name = "OrbitRing"
			obRing.Parent = workspace
			local arc = (math.pi * 2 * r) / count
			for i = 1, count do
				local d = Instance.new("Part")
				d.Name = "Dash"
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromRGB(165, 220, 255)
				d.Transparency = 0.15
				d.Size = Vector3.new(0.3, 0.3, math.max(arc * 0.55, 0.6))
				d.Parent = obRing
				obDashes[i] = d
			end
		end
		local step = (math.pi * 2) / count
		for i = 1, #obDashes do
			local a = (i - 1) * step
			local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			obDashes[i].CFrame = CFrame.lookAt(pos, pos + tangent)
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		local char = player.Character
		local mroot = nil
		local mhum = nil
		if char then
			mroot = char:FindFirstChild("HumanoidRootPart")
			mhum = char:FindFirstChildOfClass("Humanoid")
		end

		local center = nil
		if OB.target then
			local tchar = OB.target.Character
			local thrp = nil
			local thum = nil
			if tchar then
				thrp = tchar:FindFirstChild("HumanoidRootPart")
				thum = tchar:FindFirstChildOfClass("Humanoid")
			end
			if not OB.enabled or not mroot or not mhum or mhum.Health <= 0
				or not thrp or not thum or thum.Health <= 0 or obSkip(OB.target) then
				stopOrbit()
			else
				OB.angle = OB.angle + OB.speed * 0.5 * dt
				local tp = thrp.Position
				local pos = Vector3.new(tp.X + math.cos(OB.angle) * OB.dist, tp.Y, tp.Z + math.sin(OB.angle) * OB.dist)
				mroot.CFrame = CFrame.lookAt(pos, Vector3.new(tp.X, pos.Y, tp.Z))
				mroot.AssemblyLinearVelocity = Vector3.zero
				mroot.AssemblyAngularVelocity = Vector3.zero
				center = tp - Vector3.new(0, 1, 0)   -- hip height
			end
		end
		updateRing(center)
	end)

	local function orbitUnload()
		OB.enabled = false
		OB.target = nil
		hideRing()
	end

		unloaders[#unloaders + 1] = function()
			orbitUnload()
			syncOrbitHint()
		end
	end

	---------------------------------------------------------------------
	-- EXTRA NEEDS: SPIN BOT
	---------------------------------------------------------------------
	do
	local SB_MODES = { "Normal", "Upside", "Side", "Backwards" }
	local SB = {
		enabled = false,
		mode = "Normal",
		speed = 10,
		angle = 0,
		savedAuto = nil,
		savedStates = nil,
	}
	local SB_STATES = { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.PlatformStanding }
	-- stands the character back up and gives the Humanoid its rotation back
	local function sbRestore()
		local char = player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hum and SB.savedAuto ~= nil then
			hum.AutoRotate = SB.savedAuto
		end
		SB.savedAuto = nil
		if hum and SB.savedStates then
			for i = 1, #SB_STATES do
				local was = SB.savedStates[i]
				if was ~= nil then
					pcall(function()
						hum:SetStateEnabled(SB_STATES[i], was)
					end)
				end
			end
		end
		SB.savedStates = nil
		if hrp then
			local look = hrp.CFrame.LookVector
			local yaw = math.atan2(-look.X, -look.Z)
			hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0)
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end

		local sec = newSection("Needs", "Spin Bot", true, function(on)
			if on then
				SB.enabled = true
			else
				SB.enabled = false
				sbRestore()
			end
		end)
		local b = sec.box
		local o = sec.order
		makeDropdown(b, o(), "Mode", SB_MODES, function()
			return SB.mode
		end, function(val)
			SB.mode = val
		end)
		makeSlider(b, o(), { name = "Speed", min = 1, max = 100, step = 1, fmt = "%d",
			get = function() return SB.speed end, set = function(val) SB.speed = val end })
		register("spin", "Spin Bot", sec)

	-- sets the rotation of the root part only; its position (and your movement) is left alone
	local function sbStep(dt)
		if not running or not SB.enabled then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			return
		end
		if SB.savedAuto == nil then
			SB.savedAuto = hum.AutoRotate
		end
		if hum.AutoRotate then
			hum.AutoRotate = false
		end
		-- Upside / Side tip the body over: the Humanoid would "fall down" and stand itself up again, so those
		-- states are switched off while Spin Bot is on (put back when it is switched off)
		if not SB.savedStates then
			SB.savedStates = {}
			for i = 1, #SB_STATES do
				pcall(function()
					SB.savedStates[i] = hum:GetStateEnabled(SB_STATES[i])
					hum:SetStateEnabled(SB_STATES[i], false)
				end)
			end
		end

		-- the way the camera looks (flat), so the non-spinning modes face where you aim
		local yaw = 0
		local cam = workspace.CurrentCamera
		if cam then
			local look = cam.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end

		local rot = nil
		-- the angle keeps growing for every mode that spins
		SB.angle = (SB.angle + SB.speed * 36 * math.rad(1) * dt) % (math.pi * 2)
		if SB.mode == "Normal" then
			rot = CFrame.Angles(0, SB.angle, 0)
		elseif SB.mode == "Upside" then
			-- front flips: you roll over forwards through upside down, facing where you aim
			rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-SB.angle, 0, 0)
		elseif SB.mode == "Side" then
			-- cartwheels: you roll over sideways, facing where you aim
			rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, SB.angle)
		else
			rot = CFrame.Angles(0, yaw + math.pi, 0)
		end
		hrp.CFrame = CFrame.new(hrp.Position) * rot
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(sbStep)
	-- Stepped runs right before the physics, so the tipped body is not stood up again by the Humanoid
	conns[#conns + 1] = RunService.Stepped:Connect(function(_, dt)
		sbStep(dt)
	end)
	conns[#conns + 1] = RunService.RenderStepped:Connect(sbStep)

	-- after a respawn the saved AutoRotate belongs to the old character
	conns[#conns + 1] = player.CharacterAdded:Connect(function()
		SB.savedAuto = nil
		SB.savedStates = nil
	end)

	local function spinUnload()
		if SB.enabled then
			SB.enabled = false
			sbRestore()
		end
	end

		unloaders[#unloaders + 1] = spinUnload
	end

	---------------------------------------------------------------------
	-- EXTRA NEEDS: HITBOX EXPANDER
	---------------------------------------------------------------------
	do
	local HB = {
		enabled = false,
		visualize = false,
		teamCheck = false,
		knockedCheck = false,
		dynamic = false,
		dynMin = 2,
		dynFar = 60,
		size = 8,
	}
	local DYN_NEAR = 4
	local FILL_COLOR = Color3.fromRGB(120, 200, 255)
	local FILL_ALPHA = 0.86
	local LINE_COLOR = Color3.fromRGB(165, 220, 255)
	local DASHES = 8
	local DASH_FILL = 0.55

	local records = {}   -- [player] = { part, size, transparency, canCollide, box, wire }
	local activeCount = 0

	local function teamSkip(p)
		if not HB.teamCheck then
			return false
		end
		if p.Team ~= nil and player.Team ~= nil and p.Team == player.Team then
			return true
		end
		return false
	end

	local function sizeFor(d)
		local sz = HB.size
		if not HB.dynamic then
			return sz
		end
		local lo = math.min(HB.dynMin, sz)
		local far = math.max(HB.dynFar, DYN_NEAR + 1)
		local v = sz
		if d >= far then
			v = sz
		elseif d <= DYN_NEAR then
			v = lo
		else
			v = lo + (sz - lo) * (d - DYN_NEAR) / (far - DYN_NEAR)
		end
		return math.floor(v * 10 + 0.5) / 10
	end

	local function killVisual(r)
		if r.box then
			pcall(function()
				r.box:Destroy()
			end)
			r.box = nil
		end
		if r.wire then
			pcall(function()
				r.wire:Destroy()
			end)
			r.wire = nil
		end
	end

	local function release(p)
		local r = records[p]
		if not r then
			return
		end
		records[p] = nil
		killVisual(r)
		local part = r.part
		if part and part.Parent then
			pcall(function()
				part.Size = r.size
				part.Transparency = r.transparency
				part.CanCollide = r.canCollide
			end)
		end
	end

	local function releaseAll()
		local list = {}
		for p, _ in pairs(records) do
			list[#list + 1] = p
		end
		for i = 1, #list do
			release(list[i])
		end
	end

	local function buildDashes(wire, size)
		wire:Clear()
		local h = size / 2
		local period = size / DASHES
		local dash = period * DASH_FILL
		for axis = 1, 3 do
			for sa = -1, 1, 2 do
				for sb = -1, 1, 2 do
					for i = 0, DASHES - 1 do
						local t0 = -h + i * period
						local t1 = t0 + dash
						local a = nil
						local b = nil
						if axis == 1 then
							a = Vector3.new(t0, sa * h, sb * h)
							b = Vector3.new(t1, sa * h, sb * h)
						elseif axis == 2 then
							a = Vector3.new(sa * h, t0, sb * h)
							b = Vector3.new(sa * h, t1, sb * h)
						else
							a = Vector3.new(sa * h, sb * h, t0)
							b = Vector3.new(sa * h, sb * h, t1)
						end
						wire:AddLine(a, b)
					end
				end
			end
		end
	end

	local function makeVisual(r, part, want, sz)
		local box = Instance.new("BoxHandleAdornment")
		box.Name = "HitboxFill"
		box.Adornee = part
		box.AlwaysOnTop = true
		box.ZIndex = 1
		box.Color3 = FILL_COLOR
		box.Transparency = FILL_ALPHA
		box.Size = want
		box.Parent = part
		r.box = box

		local wire = Instance.new("WireframeHandleAdornment")
		wire.Name = "HitboxDashes"
		wire.Adornee = part
		wire.AlwaysOnTop = true
		wire.ZIndex = 2
		wire.Color3 = LINE_COLOR
		wire.Transparency = 0
		wire.Parent = part
		r.wire = wire

		-- dashes are built once at size 1 and scaled (cheap); without Scale they are redrawn at real size
		local okScale = pcall(function()
			wire.Scale = Vector3.new(sz, sz, sz)
		end)
		r.scaleOK = okScale
		if okScale then
			buildDashes(wire, 1)
		else
			buildDashes(wire, sz)
			r.dashSize = sz
			r.dashTime = os.clock()
		end
	end

	local function applyHitbox(p, origin)
		local char = p.Character
		local part = nil
		local hum = nil
		if char then
			part = char:FindFirstChild("HumanoidRootPart")
			hum = char:FindFirstChildOfClass("Humanoid")
		end
		if not part or not part:IsA("BasePart") or not hum or hum.Health <= 0 or teamSkip(p)
			or (HB.knockedCheck and isKnocked(char)) then
			release(p)
			return
		end

		local r = records[p]
		if r and r.part ~= part then
			release(p)
			r = nil
		end
		if not r then
			r = {
				part = part,
				size = part.Size,
				transparency = part.Transparency,
				canCollide = part.CanCollide,
			}
			records[p] = r
		end

		local sz = sizeFor((part.Position - origin).Magnitude)
		local want = Vector3.new(sz, sz, sz)
		if (part.Size - want).Magnitude > 0.05 then
			part.Size = want
		end
		if part.CanCollide then
			part.CanCollide = false
		end

		if HB.visualize then
			if not r.box or r.box.Parent ~= part or not r.wire or r.wire.Parent ~= part then
				killVisual(r)
				makeVisual(r, part, want, sz)
			else
				if (r.box.Size - want).Magnitude > 0.05 then
					r.box.Size = want
				end
				if r.scaleOK then
					local sc = r.wire.Scale
					if math.abs(sc.X - sz) > 0.01 then
						r.wire.Scale = Vector3.new(sz, sz, sz)
					end
				elseif r.dashSize ~= sz and os.clock() - (r.dashTime or 0) > 0.1 then
					r.dashSize = sz
					r.dashTime = os.clock()
					buildDashes(r.wire, sz)
				end
			end
		else
			killVisual(r)
		end
	end

	-- the game turns CanCollide back on during physics, so it is switched off again before every step
	local function noCollide()
		for _, r in pairs(records) do
			local part = r.part
			if part and part.Parent and part.CanCollide then
				part.CanCollide = false
			end
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		if not HB.enabled then
			if next(records) ~= nil then
				releaseAll()
			end
			activeCount = 0
			return
		end
		local mine = player.Character
		local mroot = nil
		if mine then
			mroot = mine:FindFirstChild("HumanoidRootPart")
		end
		local cam = workspace.CurrentCamera
		local origin = Vector3.new(0, 0, 0)
		if mroot then
			origin = mroot.Position
		elseif cam then
			origin = cam.CFrame.Position
		end
		local list = Players:GetPlayers()
		for i = 1, #list do
			local p = list[i]
			if p ~= player then
				pcall(applyHitbox, p, origin)
			end
		end
		local n = 0
		for _, _ in pairs(records) do
			n = n + 1
		end
		activeCount = n
	end)

	conns[#conns + 1] = RunService.Stepped:Connect(function()
		if running and HB.enabled then
			noCollide()
		end
	end)

	conns[#conns + 1] = RunService.RenderStepped:Connect(function()
		if running and HB.enabled then
			noCollide()
		end
	end)

	conns[#conns + 1] = Players.PlayerRemoving:Connect(function(p)
		release(p)
	end)


		local sec = newSection("Needs", "Hitbox Expander", true, function(on)
			HB.enabled = on
		end)
		local b = sec.box
		local o = sec.order
		makeToggleRow(b, o(), "Visualize", HB.visualize, function(on)
			HB.visualize = on
		end)
		makeToggleRow(b, o(), "Team Check", HB.teamCheck, function(on)
			HB.teamCheck = on
		end)
		makeToggleRow(b, o(), "Knocked Check", HB.knockedCheck, function(on)
			HB.knockedCheck = on
		end)

		-- Size: a slider and an exact box (1 - 100) that follow each other
		local sizeRow = nil
		local sizeSlider = makeSlider(b, o(), { name = "Size", min = 2, max = 50, step = 1, fmt = "%d",
			get = function() return HB.size end,
			set = function(val)
				HB.size = val
				if sizeRow then
					sizeRow.box.Text = tostring(val)
				end
			end })
		sizeRow = makeTextRow(b, o(), "Exact Size", tostring(HB.size), function(text)
			local n = tonumber(text)
			if n then
				HB.size = math.clamp(math.floor(n + 0.5), 1, 100)
			end
			sizeRow.box.Text = tostring(HB.size)
			sizeSlider.refresh()
		end)

		makeLine(b, o())

		-- Dynamic: a smaller hitbox when they are close
		local minSlider = nil
		local farSlider = nil
		makeToggleRow(b, o(), "Dynamic", HB.dynamic, function(on)
			HB.dynamic = on
			minSlider.dim(on)
			farSlider.dim(on)
		end)
		minSlider = makeSlider(b, o(), { name = "Min Size", min = 1, max = 50, step = 1, fmt = "%d",
			get = function() return HB.dynMin end, set = function(val) HB.dynMin = val end })
		farSlider = makeSlider(b, o(), { name = "Full At", min = 10, max = 300, step = 5, fmt = "%d",
			get = function() return HB.dynFar end, set = function(val) HB.dynFar = val end })
		minSlider.dim(HB.dynamic)
		farSlider.dim(HB.dynamic)
		register("hitbox", "Hitbox Expander", sec)

		unloaders[#unloaders + 1] = function()
			HB.enabled = false
			releaseAll()
		end
	end

	-- HITBOX SPOOFER (spoofers/spoofer1.lua)
	local spoofer1 = buildSpoofer("Needs", "hitboxspoofer", "Hitbox Spoofer", "Spoofer1Module", "Spoofer1",
		"spoofers/spoofer1.lua")
	unloaders[#unloaders + 1] = function()
		if spoofer1 and type(spoofer1.Unload) == "function" then
			spoofer1.Unload()
		end
	end

	---------------------------------------------------------------------
	-- QUALITY OF LIFE: ANIMATIONS
	---------------------------------------------------------------------
	do
		local RESPAWN_ON_RESET = false
	-- asset ids from the official Roblox animation bundle table
	-- (idle1 / idle2 = the two idle animations the Animate script switches between)
	local PACKS = {
		{ name = "Rthro", idle1 = "2510197257", idle2 = "2510196951", walk = "2510202577", run = "2510198475", jump = "2510197830", fall = "2510195892", climb = "2510192778", swim = "2510199791", swimidle = "2510201162" },
		{ name = "Mage", idle1 = "707742142", idle2 = "707855907", walk = "707897309", run = "707861613", jump = "707853694", fall = "707829716", climb = "707826056", swim = "707876443", swimidle = "707894699" },
		{ name = "Zombie", idle1 = "616158929", idle2 = "616160636", walk = "616168032", run = "616163682", jump = "616161997", fall = "616157476", climb = "616156119", swim = "616165109", swimidle = "616166655" },
		{ name = "Elder", idle1 = "845397899", idle2 = "845400520", walk = "845403856", run = "845386501", jump = "845398858", fall = "845396048", climb = "845392038", swim = "845401742", swimidle = "845403127" },
		{ name = "Ninja", idle1 = "656117400", idle2 = "656118341", walk = "656121766", run = "656118852", jump = "656117878", fall = "656115606", climb = "656114359", swim = "656119721", swimidle = "656121397" },
		{ name = "Vampire", idle1 = "1083445855", idle2 = "1083450166", walk = "1083473930", run = "1083462077", jump = "1083455352", fall = "1083443587", climb = "1083439238", swim = "1083464683", swimidle = "1083467779" },
		{ name = "Werewolf", idle1 = "1083195517", idle2 = "1083214717", walk = "1083178339", run = "1083216690", jump = "1083218792", fall = "1083189019", climb = "1083182000", swim = "1083222527", swimidle = "1083225406" },
		{ name = "Levitation", idle1 = "616006778", idle2 = "616008087", walk = "616013216", run = "616010382", jump = "616008936", fall = "616005863", climb = "616003713", swim = "616011509", swimidle = "616012453" },
		{ name = "Astronaut", idle1 = "891621366", idle2 = "891633237", walk = "891636393", run = "891636393", jump = "891627522", fall = "891617961", climb = "891609353", swim = "891639666", swimidle = "891663592" },
		{ name = "Knight", idle1 = "657595757", idle2 = "657568135", walk = "657552124", run = "657564596", jump = "658409194", fall = "657600338", climb = "658360781", swim = "657560551", swimidle = "657557095" },
		{ name = "Pirate", idle1 = "750781874", idle2 = "750782770", walk = "750785693", run = "750783738", jump = "750782230", fall = "750780242", climb = "750779899", swim = "750784579", swimidle = "750785176" },
	}
	local NAMES = { "Default" }
	for i = 1, #PACKS do
		NAMES[i + 1] = PACKS[i].name
	end

	-- every package animation id (numbers only): playing tracks with these ids get stopped on a change
	local KNOWN = {}
	for p = 1, #PACKS do
		for k, v in pairs(PACKS[p]) do
			if k ~= "name" then
				KNOWN[v] = true
			end
		end
	end

	-- the drop-downs, top to bottom (key = which selection it controls)
	local ROWS = {
		{ key = "idle", title = "Idle" },
		{ key = "walk", title = "Walk" },
		{ key = "run", title = "Run" },
		{ key = "jump", title = "Jump" },
		{ key = "fall", title = "Fall" },
		{ key = "swim", title = "Swim" },
		{ key = "climb", title = "Climb" },
	}

	-- used to recognise which pack your default set is (idle is left out, it varies per game)
	local DETECT = { "walk", "run", "jump", "fall", "swim", "climb" }

	-- every value inside the Animate script that gets changed
	-- (Idle changes both idle animations, Swim also changes the swim idle)
	local TARGETS = {
		{ field = "idle1", sel = "idle", folder = "idle", anim = "Animation1", exact = true },
		{ field = "idle2", sel = "idle", folder = "idle", anim = "Animation2", exact = true },
		{ field = "walk", sel = "walk", folder = "walk", anim = "WalkAnim" },
		{ field = "run", sel = "run", folder = "run", anim = "RunAnim" },
		{ field = "jump", sel = "jump", folder = "jump", anim = "JumpAnim" },
		{ field = "fall", sel = "fall", folder = "fall", anim = "FallAnim" },
		{ field = "climb", sel = "climb", folder = "climb", anim = "ClimbAnim" },
		{ field = "swim", sel = "swim", folder = "swim", anim = "Swim" },
		{ field = "swimidle", sel = "swim", folder = "swimidle", anim = "SwimIdle" },
	}

	local enabled = false
	local sel = { idle = 1, walk = 1, run = 1, jump = 1, fall = 1, swim = 1, climb = 1 }   -- 1 = Default
	local defaults = {}
	local defaultNums = {}
	local hasDefaults = false
	local detected = "Game default"
	local applyToken = 0
	local statusLbl = nil
	local schedule = nil

	-- queue so two changes never run at the same time
	local working = false
	local again = false
	local nextForceDefault = false
	local nextForce = false

	local function num(id)
		return string.match(tostring(id or ""), "(%d+)%s*$")
	end

	local function findAnim(animate, folderName, animName, exact)
		local f = animate:FindFirstChild(folderName)
		if not f then
			return nil
		end
		local a = f:FindFirstChild(animName)
		if a and a:IsA("Animation") then
			return a
		end
		if exact then
			return nil
		end
		local kids = f:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("Animation") then
				return kids[i]
			end
		end
		return nil
	end

	local function statusText(on, extra)
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if on then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		if extra then
			state = state .. ' <font color="rgb(116,116,124)">- ' .. extra .. '</font>'
		end
		return state
	end
	local function refreshStatus()
		if not statusLbl or not statusLbl.Parent then
			return
		end
		local char = player.Character
		local hum = nil
		if char then
			hum = char:FindFirstChildOfClass("Humanoid")
		end
		if not char or not char:FindFirstChild("Animate") then
			statusLbl.Text = "No Animate script found yet"
		elseif hum and hum.RigType == Enum.HumanoidRigType.R6 then
			statusLbl.Text = "R6 rig - packages need R15"
		else
			statusLbl.Text = "Your default set: " .. detected
		end
	end

	local function capture(animate)
		defaults = {}
		defaultNums = {}
		for i = 1, #TARGETS do
			local t = TARGETS[i]
			local a = findAnim(animate, t.folder, t.anim, t.exact)
			if a then
				defaults[t.field] = a.AnimationId
				local n = num(a.AnimationId)
				if n then
					defaultNums[n] = true
				end
			end
		end
		hasDefaults = true

		detected = "Game default"
		for p = 1, #PACKS do
			local all = true
			for r = 1, #DETECT do
				local f = DETECT[r]
				if num(defaults[f]) ~= PACKS[p][f] then
					all = false
				end
			end
			if all then
				detected = PACKS[p].name
			end
		end
		refreshStatus()
	end

	-- stops every movement animation that is still playing: your default ids and every package id.
	-- This is what stops old and new animations from blending together.
	local function stopMoveTracks(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = nil
		if hum then
			animator = hum:FindFirstChildOfClass("Animator")
		end
		if not animator then
			return
		end
		local ok, tracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if not ok or not tracks then
			return
		end
		for i = 1, #tracks do
			local a = tracks[i].Animation
			local n = nil
			if a then
				n = num(a.AnimationId)
			end
			if n and (KNOWN[n] or defaultNums[n]) then
				pcall(function()
					tracks[i]:Stop(0)
				end)
			end
		end
	end

	-- one clean change: script off -> stop old animations -> write ids -> script on
	local function doApply(forceDefault, force)
		local char = player.Character
		local animate = nil
		if char then
			animate = char:FindFirstChild("Animate")
		end
		if not animate or not hasDefaults then
			return
		end

		local changes = {}
		for i = 1, #TARGETS do
			local t = TARGETS[i]
			local a = findAnim(animate, t.folder, t.anim, t.exact)
			local base = defaults[t.field]
			if a and base then
				local want = base
				if enabled and not forceDefault then
					local idx = sel[t.sel]
					if idx > 1 then
						want = "rbxassetid://" .. PACKS[idx - 1][t.field]
					end
				end
				if a.AnimationId ~= want or force then
					changes[#changes + 1] = { a, want }
				end
			end
		end
		if #changes == 0 and not force then
			return
		end

		pcall(function()
			animate.Disabled = true
		end)
		stopMoveTracks(char)
		for i = 1, #changes do
			pcall(function()
				changes[i][1].AnimationId = changes[i][2]
			end)
		end
		task.wait(0.1)
		stopMoveTracks(char)
		pcall(function()
			animate.Disabled = false
		end)
	end

	local function runApply(forceDefault, force)
		if forceDefault then
			nextForceDefault = true
		end
		if force then
			nextForce = true
		end
		if working then
			again = true
			return
		end
		working = true
		task.spawn(function()
			repeat
				again = false
				local fd = nextForceDefault
				local ff = nextForce
				nextForceDefault = false
				nextForce = false
				pcall(doApply, fd, ff)
			until not again
			working = false
		end)
	end

	-- several quick clicks become one change
	schedule = function()
		applyToken = applyToken + 1
		local tk = applyToken
		task.delay(0.15, function()
			if tk == applyToken and running then
				runApply(false, false)
			end
		end)
	end

	-- every respawn resets the Animate script, so the defaults are read again and the picks re-applied
	local function onCharacter(char)
		hasDefaults = false
		defaults = {}
		defaultNums = {}
		task.spawn(function()
			local animate = char:WaitForChild("Animate", 10)
			if not running or not animate then
				refreshStatus()
				return
			end
			task.wait(0.6)
			if not running or player.Character ~= char then
				return
			end
			capture(animate)
			if enabled then
				runApply(false, false)
			end
		end)
	end

	conns[#conns + 1] = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	refreshStatus()

		-- Reset All: every drop-down back on Default, defaults restored, animations restarted from scratch
		local dropdowns = {}
		local function resetAll()
			for i = 1, #ROWS do
				sel[ROWS[i].key] = 1
				local dd = dropdowns[i]
				if dd then
					dd.refresh()
					dd.setOpen(false)
				end
			end
			applyToken = applyToken + 1
			runApply(true, true)
			if RESPAWN_ON_RESET then
				local char = player.Character
				local hum = nil
				if char then
					hum = char:FindFirstChildOfClass("Humanoid")
				end
				if hum then
					hum.Health = 0
				end
			end
		end

		local sec = newSection("Quality", "Animations", true, function(on)
			enabled = on
			schedule()
		end)
		local b = sec.box
		local o = sec.order
		statusLbl = makeNote(b, o(), "", T.DIM_TEXT)
		refreshStatus()
		for i = 1, #ROWS do
			local row = ROWS[i]
			dropdowns[i] = makeDropdown(b, o(), row.title, NAMES, function()
				return NAMES[sel[row.key]]
			end, function(val)
				for k = 1, #NAMES do
					if NAMES[k] == val then
						sel[row.key] = k
					end
				end
				schedule()
			end)
		end
		makeButtonRow(b, o(), "Reset All", resetAll)
		register("anim", "Animations", sec)

		unloaders[#unloaders + 1] = function()
			enabled = false
			applyToken = applyToken + 1
			runApply(true, false)
		end
	end

	---------------------------------------------------------------------
	-- QUALITY OF LIFE: ANTI AFK (a switch only)
	---------------------------------------------------------------------
	do
	local afkOn = false
	-- Roblox fires Idled after about 20 minutes without input; a fake click resets that timer
	conns[#conns + 1] = player.Idled:Connect(function()
		if not running or not afkOn then
			return
		end
		pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController()
			vu:ClickButton2(Vector2.new(0, 0))
		end)
	end)

		local sec = newSection("Quality", "Anti AFK", true, function(on)
			afkOn = on
		end)
		makeNote(sec.box, sec.order(), "While it is on, the game's idle kick is blocked with a fake click when Roblox says you went idle.", T.DIM_TEXT)
		register("afk", "Anti AFK", sec)

		unloaders[#unloaders + 1] = function()
			afkOn = false
		end
	end

	-- PING SPOOFER (spoofers/spoofer2.lua)
	local spoofer2 = buildSpoofer("Quality", "ping", "Ping Spoofer", "Spoofer2Module", "Spoofer2",
		"spoofers/spoofer2.lua")
	unloaders[#unloaders + 1] = function()
		if spoofer2 and type(spoofer2.Unload) == "function" then
			spoofer2.Unload()
		end
	end

	---------------------------------------------------------------------
	-- UNLOAD: switch everything off and put the original values back
	---------------------------------------------------------------------
	local unloaded = false
	local function unload()
		if unloaded then
			return
		end
		unloaded = true
		for i = 1, #unloaders do
			pcall(unloaders[i])
		end
		running = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			if root and root.Parent then
				root:Destroy()
			end
		end)
	end

	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	if type(ctx) == "table" and ctx.Win then
		ctx.Win.ExtrasPanels = bodies
	end

	return { Root = root, Panels = bodies, Unload = unload }
end

return Extra2
