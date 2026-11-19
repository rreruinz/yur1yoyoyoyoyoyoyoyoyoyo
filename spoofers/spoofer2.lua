-- spoofer2.lua  (Y1 Misc > Extras > Quality Of Life: the Ping Spoofer)
-- ASCII only, conservative syntax (no += and no continue).
--
-- This is the old pingspoofer.lua with the look of the Extras page: a name + switch on top and one inset box under it
-- with the Ping / Jitter / Speed sliders and the live readouts. No pop-up, no three dots.
--
-- ONE METHOD: value override. Every place the ping is READ or DRAWN gets your number instead of the real one:
--   1) Performance Stats overlay (Esc > Settings): every Ping number in CoreGui is rewritten (text, graph, dot).
--   2) StatsItem:GetValue / GetValueString for "Data Ping" / "Ping" and Player:GetNetworkPing() (scripts).
-- It only changes what this client reports. It does not touch your real connection.
-- Needs CoreGui access (overlay) and hookmetamethod + newcclosure + getnamecallmethod (scripts); the box says which part
-- is not active.  Jitter: +/- 0..100 ms, random ups and drops. Speed: 1 (slow) .. 10 (fast) = how often it jumps.
--
-- Build signature: Spoofer.build(parent, T, H, ctx) -> { Root = frame, Box = settings box, Unload = fn }

local Spoofer = {}

function Spoofer.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Stats = game:GetService("Stats")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local TITLE = "Ping Spoofer"

	local GREEN = Color3.fromRGB(52, 199, 120)
	local AMBER = Color3.fromRGB(232, 176, 70)

	---------------------------------------------------------------------
	-- stop an older copy
	---------------------------------------------------------------------
	local okEnv, genv = pcall(function()
		return getgenv()
	end)
	if okEnv and genv and genv.__Y1_PING_STOP then
		pcall(genv.__Y1_PING_STOP)
	end

	---------------------------------------------------------------------
	-- state
	---------------------------------------------------------------------
	local S = {
		on = false,
		ping = 150,        -- ms you want
		jitter = 25,       -- +/- ms wobble (max 100)
		jitterSpeed = 4,   -- 1 (slow) .. 10 (fast)
	}

	local running = true
	local conns = {}
	local shown = S.ping
	local jitterOff = 0

	-- shared with the hook: the hook is installed only once per game session, even if this module is rebuilt
	local shared = nil
	if okEnv and genv and type(genv.__Y1_PING_SHARED) == "table" then
		shared = genv.__Y1_PING_SHARED
	else
		shared = { on = false, shown = S.ping, reading = false, hooked = false, tried = false }
		if okEnv and genv then
			genv.__Y1_PING_SHARED = shared
		end
	end
	shared.on = false
	shared.shown = S.ping

	local canHook = (type(hookmetamethod) == "function") and (type(newcclosure) == "function")
		and (type(getnamecallmethod) == "function")

	-- the real ping in ms (read by this script, so the hook lets it through)
	local function readReal()
		shared.reading = true
		local ok, v = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		shared.reading = false
		if ok and type(v) == "number" then
			return v
		end
		return 0
	end

	---------------------------------------------------------------------
	-- part 1: scripts (namecall hook)
	---------------------------------------------------------------------
	local function installHook()
		if shared.tried then
			return shared.hooked
		end
		shared.tried = true
		if not canHook then
			return false
		end
		local hookOld = nil
		local ok = pcall(function()
			hookOld = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				if shared.on and not shared.reading then
					local method = getnamecallmethod()
					if method == "GetValue" or method == "GetValueString" or method == "GetNetworkPing" then
						local ours = false
						if type(checkcaller) == "function" then
							ours = checkcaller()
						end
						if not ours and typeof(self) == "Instance" then
							if method == "GetNetworkPing" then
								if self == player then
									return shared.shown / 1000
								end
							elseif self.ClassName == "StatsItem" then
								local n = self.Name
								if n == "Data Ping" or n == "Ping" then
									if method == "GetValue" then
										return shared.shown
									end
									return string.format("%.2f ms", shared.shown)
								end
							end
						end
					end
				end
				return hookOld(self, ...)
			end))
		end)
		shared.hooked = ok and hookOld ~= nil
		return shared.hooked
	end

	---------------------------------------------------------------------
	-- part 2: Performance Stats overlay (CoreGui text)
	---------------------------------------------------------------------
	local coreGui = nil
	pcall(function()
		coreGui = game:GetService("CoreGui")
	end)
	local coreOk = false
	if coreGui then
		coreOk = pcall(function()
			return #coreGui:GetChildren()
		end)
	end

	local labels = {}      -- [TextLabel] = { conn, busy }
	local labelCount = 0
	local dirty = true
	local lastScan = 0

	local function isTextObj(o)
		return o:IsA("TextLabel") or o:IsA("TextButton")
	end

	-- plain number text, e.g. "45", "45.12", "45 ms", "45.12ms"
	local function isNumberText(t)
		if type(t) ~= "string" then
			return false
		end
		return string.match(t, "^%s*%-?%d[%d%.,]*%s*[mM]?[sS]?%s*$") ~= nil
	end

	-- detail panel lines: "Current: 234 ms" and "Average: 236 ms" (Target is left alone)
	local function isStatLine(t)
		if type(t) ~= "string" then
			return false
		end
		local l = string.lower(t)
		return string.match(l, "^%s*current%s*:%s*%d") ~= nil or string.match(l, "^%s*average%s*:%s*%d") ~= nil
	end

	local function isCurrentLine(t)
		if type(t) ~= "string" then
			return false
		end
		return string.match(string.lower(t), "^%s*current%s*:") ~= nil
	end

	local function isPingTitle(t)
		if type(t) ~= "string" then
			return false
		end
		local l = string.lower(t)
		return string.match(l, "^%s*[%a ]*ping%s*:?%s*$") ~= nil
	end

	-- the same text with its first number replaced by ours (same decimals as the original)
	local function withValue(orig, v)
		local s, e = string.find(orig, "%d[%d%.]*")
		if not s then
			return orig
		end
		local numStr = string.sub(orig, s, e)
		local dec = 0
		local dot = string.find(numStr, ".", 1, true)
		if dot then
			dec = #numStr - dot
		end
		local out = string.format("%." .. tostring(dec) .. "f", math.max(0, v))
		return string.sub(orig, 1, s - 1) .. out .. string.sub(orig, e + 1)
	end

	local function paint(lbl)
		local rec = labels[lbl]
		if not rec or not S.on then
			return
		end
		local cur = lbl.Text
		local want = withValue(cur, shown)
		if want ~= cur then
			rec.busy = true
			lbl.Text = want
			rec.busy = false
		end
	end

	local function watch(lbl)
		if labels[lbl] then
			return
		end
		local rec = { busy = false }
		labels[lbl] = rec
		labelCount = labelCount + 1
		rec.conn = lbl:GetPropertyChangedSignal("Text"):Connect(function()
			if rec.busy then
				return
			end
			paint(lbl)
		end)
	end

	-- number labels inside a container, not counting "skip"
	local function numbersIn(container, skip)
		local out = {}
		local list = container:GetDescendants()
		for i = 1, #list do
			local d = list[i]
			if d ~= skip and isTextObj(d) and (isNumberText(d.Text) or isStatLine(d.Text)) then
				out[#out + 1] = d
			end
		end
		return out
	end

	-- graphs: PS_AnnotatedGraph > PS_BarFrame > Bar_0..Bar_N, each bar Position.Y = 1-h, Size.Y = h (h = value / axis top)
	local graphs = {}      -- [graphFrame] = { bars = {}, conns = {}, top = label, busy = false }
	local graphCount = 0
	local history = {}
	local histCol = {}   -- color each bar got when it was added (old bars keep theirs)
	local axisMax = 100
	local histAcc = 0
	local STEPS = { 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 5000 }

	-- exact colors and thresholds from Roblox's own Performance Stats code (StatsUtils.GetColorForValue):
	--   value < 0.666 * target  -> green
	--   value < 1.333 * target  -> yellow (yellow-green)
	--   otherwise               -> orange-red
	local C_GOOD = Color3.new(126 / 255, 211 / 255, 33 / 255)
	local C_MID = Color3.new(209 / 255, 211 / 255, 33 / 255)
	local C_BAD = Color3.new(211 / 255, 88 / 255, 33 / 255)
	local PING_TARGET = 50

	local function graphColor(v)
		if v < 0.666 * PING_TARGET then
			return C_GOOD
		elseif v < 1.333 * PING_TARGET then
			return C_MID
		end
		return C_BAD
	end

	-- legend dot next to "Current:" follows the graph color
	local dots = {}   -- [obj] = { prop, orig, conn, busy }
	local dotCount = 0

	local function dotProp(o)
		if o:IsA("ImageLabel") or o:IsA("ImageButton") then
			return "ImageColor3"
		end
		return "BackgroundColor3"
	end

	local function paintDot(o)
		local rec = dots[o]
		if not rec or not S.on then
			return
		end
		local want = graphColor(shown)
		if o[rec.prop] ~= want then
			rec.busy = true
			o[rec.prop] = want
			rec.busy = false
		end
	end

	local function watchDot(o)
		if dots[o] then
			return
		end
		local prop = dotProp(o)
		local rec = { prop = prop, orig = o[prop], busy = false }
		dots[o] = rec
		dotCount = dotCount + 1
		rec.conn = o:GetPropertyChangedSignal(prop):Connect(function()
			if not rec.busy then
				paintDot(o)
			end
		end)
	end

	-- find the small dot sitting on the same row as a "Current:" label
	local function findDot(lbl)
		local c = lbl.Parent
		for _ = 1, 2 do
			if not c or c == coreGui then
				break
			end
			local ly = lbl.AbsolutePosition.Y
			local lh = lbl.AbsoluteSize.Y
			local found = false
			local list = c:GetDescendants()
			for i = 1, #list do
				local o = list[i]
				if o ~= lbl and o:IsA("GuiObject") and not isTextObj(o)
					and o.AbsoluteSize.X > 0 and o.AbsoluteSize.X <= 24
					and o.AbsoluteSize.Y > 0 and o.AbsoluteSize.Y <= 24 then
					local cy = o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2
					if cy >= ly and cy <= ly + lh then
						watchDot(o)
						found = true
					end
				end
			end
			if found then
				return
			end
			c = c.Parent
		end
	end

	-- put the original colors back and stop watching
	local function clearDots()
		for o, rec in pairs(dots) do
			pcall(function()
				rec.conn:Disconnect()
			end)
			pcall(function()
				o[rec.prop] = rec.orig
			end)
			dots[o] = nil
		end
		dotCount = 0
	end

	local HIST_CAP = 240
	local maxBars = 20

	-- the axis follows only the bars you can see, so it drops back down once a spike scrolls out
	local function recalcAxis()
		local m = 0
		for i = math.max(1, #history - maxBars + 1), #history do
			if history[i] > m then
				m = history[i]
			end
		end
		local want = STEPS[#STEPS]
		for i = 1, #STEPS do
			if STEPS[i] >= m * 1.1 then
				want = STEPS[i]
				break
			end
		end
		axisMax = want
	end

	local function pushHistory()
		history[#history + 1] = shown
		histCol[#histCol + 1] = graphColor(shown)
		if #history > HIST_CAP then
			table.remove(history, 1)
			table.remove(histCol, 1)
		end
		recalcAxis()
	end

	-- fill the past with your REAL ping (small natural wobble) so the graph looks continuous
	local function prefillHistory(base)
		history = {}
		histCol = {}
		for i = 1, HIST_CAP do
			local v = math.max(1, base * (1 + (math.random() * 2 - 1) * 0.06))
			history[i] = v
			histCol[i] = graphColor(v)
		end
		recalcAxis()
	end

	local function paintGraph(g)
		local rec = graphs[g]
		if not rec or not S.on then
			return
		end
		rec.busy = true
		local bars = rec.bars
		local n = #bars
		for i = 1, n do
			local bar = bars[i]
			if bar.Parent then
				local idx = #history - (n - i)
				local v = history[idx]
				if v == nil then
					v = history[1] or shown
				end
				local col = histCol[idx]
				if col == nil then
					col = graphColor(v)
				end
				if bar.BackgroundColor3 ~= col then
					bar.BackgroundColor3 = col
				end
				local h = math.clamp(v / axisMax, 0, 1)
				if math.abs(bar.Size.Y.Scale - h) > 0.0005 then
					bar.Position = UDim2.new(bar.Position.X.Scale, bar.Position.X.Offset, 1 - h, 0)
					bar.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, h, 0)
				end
			end
		end
		if rec.top and rec.top.Parent then
			local want = string.format("%.2f", axisMax)
			if rec.top.Text ~= want then
				rec.top.Text = want
			end
		end
		rec.busy = false
	end

	local function watchGraph(g)
		if graphs[g] then
			return
		end
		local frame = g:FindFirstChild("PS_BarFrame")
		if not frame then
			return
		end
		local bars = {}
		local kids = frame:GetChildren()
		for i = 1, #kids do
			local n = string.match(kids[i].Name, "^Bar_(%d+)$")
			if n and kids[i]:IsA("GuiObject") then
				bars[#bars + 1] = { n = tonumber(n), o = kids[i] }
			end
		end
		if #bars == 0 then
			return
		end
		table.sort(bars, function(a, b)
			return a.n < b.n
		end)
		local list = {}
		for i = 1, #bars do
			list[i] = bars[i].o
		end
		if #list > maxBars then
			maxBars = #list
		end
		local rec = { bars = list, conns = {}, top = g:FindFirstChild("PS_TopAxisLabel"), busy = false }
		graphs[g] = rec
		graphCount = graphCount + 1
		for i = 1, #list do
			rec.conns[#rec.conns + 1] = list[i]:GetPropertyChangedSignal("Size"):Connect(function()
				if not rec.busy then
					paintGraph(g)
				end
			end)
		end
		if rec.top then
			rec.conns[#rec.conns + 1] = rec.top:GetPropertyChangedSignal("Text"):Connect(function()
				if not rec.busy then
					paintGraph(g)
				end
			end)
		end
	end

	-- the graph that belongs to a ping title label
	local function graphForTitle(d)
		if d.Name == "TitleLabel" then
			-- small panel: its graph is the next PS_AnnotatedGraph after the panel in the same row
			local panel = d.Parent
			local row = panel and panel.Parent
			if row then
				local kids = row:GetChildren()
				local seen = false
				for i = 1, #kids do
					if kids[i] == panel then
						seen = true
					elseif seen and kids[i].Name == "PS_AnnotatedGraph" then
						return kids[i]
					end
				end
			end
			return nil
		end
		-- detail view: the title sits in a Frame next to the big graph
		local box = d.Parent and d.Parent.Parent
		if box then
			return box:FindFirstChild("PS_AnnotatedGraph")
		end
		return nil
	end

	local function scan()
		if not coreOk then
			return
		end
		local list = coreGui:GetDescendants()
		for i = 1, #list do
			local d = list[i]
			if isTextObj(d) then
				local t = d.Text
				local picked = nil

				if isPingTitle(t) then
					local gf = graphForTitle(d)
					if gf then
						watchGraph(gf)
					end
					-- the value sits next to the title: widen the search level by level until numbers appear
					local c = d.Parent
					for _ = 1, 3 do
						if not c or c == coreGui then
							break
						end
						local nums = numbersIn(c, d)
						if #nums == 1 or #nums == 2 then
							picked = nums
							break
						elseif #nums > 2 then
							break
						end
						c = c.Parent
					end
				elseif string.match(string.lower(t), "^%s*[%a ]*ping[%a ]*%s*:?%s*%-?%d") then
					-- one label with both words and number: "Ping: 45 ms"
					picked = { d }
				end

				if picked then
					for j = 1, #picked do
						watch(picked[j])
						if isCurrentLine(picked[j].Text) then
							findDot(picked[j])
						end
					end
				end
			end
		end
	end

	local function clearGraphs()
		for g, rec in pairs(graphs) do
			for i = 1, #rec.conns do
				pcall(function()
					rec.conns[i]:Disconnect()
				end)
			end
			graphs[g] = nil
		end
		graphCount = 0
	end

	local function dropDead()
		for g, rec in pairs(graphs) do
			if not g.Parent then
				for i = 1, #rec.conns do
					pcall(function()
						rec.conns[i]:Disconnect()
					end)
				end
				graphs[g] = nil
				graphCount = graphCount - 1
			end
		end
		for lbl, rec in pairs(labels) do
			if not lbl.Parent then
				pcall(function()
					rec.conn:Disconnect()
				end)
				labels[lbl] = nil
				labelCount = labelCount - 1
			end
		end
		for o, rec in pairs(dots) do
			if not o.Parent then
				pcall(function()
					rec.conn:Disconnect()
				end)
				dots[o] = nil
				dotCount = dotCount - 1
			end
		end
	end

	local function clearLabels()
		clearGraphs()
		clearDots()
		for lbl, rec in pairs(labels) do
			pcall(function()
				rec.conn:Disconnect()
			end)
			labels[lbl] = nil
		end
		labelCount = 0
	end

	if coreOk then
		pcall(function()
			conns[#conns + 1] = coreGui.DescendantAdded:Connect(function()
				dirty = true
			end)
		end)
	end

	local function overlayStep(now)
		dropDead()
		if not S.on then
			return
		end
		if dirty or (now - lastScan) >= 1 then
			dirty = false
			lastScan = now
			pcall(scan)
		end
		for lbl, _ in pairs(labels) do
			paint(lbl)
		end
		for g, _ in pairs(graphs) do
			paintGraph(g)
		end
		for o, _ in pairs(dots) do
			paintDot(o)
		end
	end

	local function onEnabled()
		local r = readReal()
		if r > 0 then
			shown = r
		end
		shared.shown = shown
		prefillHistory(math.max(1, shown))
	end

	-- layout (same numbers as the Main page of misc1.lua / extra2.lua)
	local HEADER_H = 28
	local BOX_PAD = 10
	local BOX_GAP = 9
	local ROW_H = 28
	local SLIDER_H = 38
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH

	-- one section: name + switch on top, one inset box (the settings) under it
	local holder = new("Frame", {
		Name = "SpooferHolder",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, holder)

	local head = new("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, holder)
	label(head, TITLE, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 1, 0),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)

	local function makeSwitch(row, onChange)
		local on = false
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
		track.Activated:Connect(function()
			on = not on
			local pos = UDim2.new(0, 3, 0.5, 0)
			local tc = T.CLUSTER_BG
			local kc = T.DIM_TEXT
			if on then
				pos = UDim2.new(0, 21, 0.5, 0)
				tc = T.JOIN_BG
				kc = T.BLACK
			end
			TweenService:Create(knob, SMOOTH, { Position = pos }):Play()
			TweenService:Create(knob, FAST, { BackgroundColor3 = kc }):Play()
			TweenService:Create(track, FAST, { BackgroundColor3 = tc }):Play()
			onChange(on)
		end)
	end

	local box = new("Frame", {
		Name = "Settings",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.WELL,
		BorderSizePixel = 0,
	}, holder)
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
	local boxN = 0
	local function nextOrder()
		boxN = boxN + 1
		return boxN
	end

	-- a wrapped line of small text
	local function makeNote(text, color)
		local n = label(box, text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0),
			Enum.Font.Gotham, 11, color or T.DIM_TEXT)
		n.LayoutOrder = nextOrder()
		n.TextWrapped = true
		n.TextTruncate = Enum.TextTruncate.None
		n.TextYAlignment = Enum.TextYAlignment.Top
		n.AutomaticSize = Enum.AutomaticSize.Y
		return n
	end

	-- slider (same look as the other pages): name left, value right, red bar with a white handle
	local dragObj = nil
	local function makeSlider(name, minV, maxV, stepV, fmt, get, set)
		local row = new("Frame", {
			Name = name .. "Slider",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, SLIDER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, box)
		label(row, name, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 0, 18), Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
		local valLbl = label(row, "", UDim2.new(0.6, 0, 0, 0), UDim2.new(0.4, 0, 0, 18),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Right)
		local track = new("Frame", {
			Position = UDim2.fromOffset(3, 27),
			Size = UDim2.new(1, -6, 0, 6),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, row)
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
		}, row)
		local function refresh()
			local v = get()
			local f = math.clamp((v - minV) / (maxV - minV), 0, 1)
			fill.Size = UDim2.new(f, 0, 1, 0)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
			valLbl.Text = string.format(fmt, v)
		end
		local obj = {}
		function obj.drag(input)
			local w = track.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local f = math.clamp((input.Position.X - track.AbsolutePosition.X) / w, 0, 1)
			local v = minV + math.floor(f * (maxV - minV) / stepV + 0.5) * stepV
			set(math.clamp(v, minV, maxV))
			refresh()
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragObj = obj
				obj.drag(input)
			end
		end)
		refresh()
	end
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragObj and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragObj.drag(input)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragObj = nil
		end
	end)

	makeSwitch(head, function(on)
		S.on = on
		shared.on = on
		if on then
			onEnabled()
			installHook()
			dirty = true
		else
			clearLabels()
		end
	end)

	makeSlider("Ping", 0, 1000, 5, "%d ms", function() return S.ping end, function(v) S.ping = v end)
	makeSlider("Jitter", 0, 100, 1, "+/- %d", function() return S.jitter end, function(v) S.jitter = v end)
	makeSlider("Speed", 1, 10, 1, "%d", function() return S.jitterSpeed end, function(v) S.jitterSpeed = v end)

	local line = new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, box)

	local realLbl = makeNote("Real ping: -", T.TEXT_COLOR)
	local shownLbl = makeNote("Shown ping: -", T.TEXT_COLOR)
	-- (the old hook / overlay status lines are gone on purpose)
	local function statusLines()
	end

	local acc = 0
	local jacc = 0
	local jnext = 1
	local lastJitter = S.jitter
	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		jacc = jacc + dt
		-- speed 1 = about every 6s, speed 10 = about every 0.6s, with random variation in the gap
		if S.jitter ~= lastJitter then
			lastJitter = S.jitter
			jacc = jnext
		end
		if jacc >= jnext then
			jacc = 0
			local base = 6.6 - 0.6 * math.max(1, S.jitterSpeed)
			jnext = base * (0.4 + math.random() * 1.2)
			jitterOff = (math.random() * 2 - 1) * S.jitter
		end
		local target = math.max(0, S.ping + jitterOff)
		-- fast snap (about a tenth of a second) so changes read as ups and drops, not smooth slides
		shown = shown + (target - shown) * math.min(1, dt * 20)
		shared.shown = shown

		histAcc = histAcc + dt
		if histAcc >= 0.5 then
			histAcc = 0
			pushHistory()
		end
		overlayStep(os.clock())

		acc = acc + dt
		if acc >= 0.25 then
			acc = 0
			if holder.Parent then
				statusLines()
				realLbl.Text = string.format("Real ping: %d ms", math.floor(readReal() + 0.5))
				if S.on then
					shownLbl.Text = string.format("Shown ping: %d ms", math.floor(shown + 0.5))
				else
					shownLbl.Text = "Shown ping: real"
				end
			end
		end
	end)

	-- also paint right before each frame is drawn, so the engine's update is never visible
	pcall(function()
		conns[#conns + 1] = RunService.RenderStepped:Connect(function()
			if running and S.on then
				for lbl, _ in pairs(labels) do
					paint(lbl)
				end
				for g, _ in pairs(graphs) do
					paintGraph(g)
				end
				for o, _ in pairs(dots) do
					paintDot(o)
				end
			end
		end)
	end)

	local function unload()
		if not running then
			return
		end
		running = false
		S.on = false
		shared.on = false
		clearLabels()
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			holder:Destroy()
		end)
		if okEnv and genv and genv.__Y1_PING_STOP == unload then
			genv.__Y1_PING_STOP = nil
		end
	end

	if okEnv and genv then
		genv.__Y1_PING_STOP = unload
	end

	return { Root = holder, Box = box, Unload = unload }
end

return Spoofer
