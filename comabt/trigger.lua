-- trigger.lua  (Combat tab > Triggerbot page)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Loaded by main.lua, built by combat/aimbot.lua into its "Triggerbot" side:   Trigger.build(container, T, H, ctx)
-- The engine (createTriggerbot, your pasted code) is unchanged. Around it is a page built like misc1.lua: three panels with a title bar and a red line, every option is a section: name + switch on top,
-- and one inset box with its settings (Keybind, Mode, drop-downs, sliders with a red bar).
--
--   Triggerbot panel : Triggerbot (switch, Keybind, Mode, Fire Method, Hit Part, Crosshair), Require Tool, Delay, Random Delay
--   Checks panel     : Team Check, Forcefield Check, Health Check (Min Health), Knocked Check, Distance (Min / Max)
--   Tuning panel     : Auto Lead (Lead, Max Lead),
--                      Detection (Hitbox, Rings, Ring Rays, Los Rays, Max Candidates)
--
-- The switch of every section is OFF each time the script starts (the Triggerbot switch too). Mode:
--   Always = armed while the switch is on     Toggle = the keybind arms / disarms it     Hold = armed only while the key is held
-- KEYBINDS PANEL: while the triggerbot is armed it shows there ("Triggerbot" + its key).
-- SEARCH: every section is registered with the window's search box (ctx.Win:AddSearch).
-- ctx.SwitcherSpace = height the "Aimbot | Silent | Triggerbot" bar takes (aimbot.lua passes it; default 31).
--
-- Build signature: Trigger.build(container, T, H, ctx) -> { Api = triggerbot, Unload = fn }

local CONFIG = {
	Enabled = false,
	Key = Enum.KeyCode.T,
	Mode = "Toggle",
	HitPart = "Any",
	FireMethod = "Tool Activate",
	RequireTool = false,
	MinDist = 0,
	MaxDist = 1000,
	TeamCheck = true,
	ForceFieldCheck = true,
	HealthCheck = false,
	MinHealth = 20,
	KnockedCheck = false,
	DelayMs = 0,
	RandomDelay = false,
	RandMin = 10,
	RandMax = 60,
	ReleaseMs = 15,
	CooldownMs = 0,
	GraceMs = 50,
	HitboxPx = 6,
	LeadMs = 40,
	AutoLead = false,
	MaxLeadStuds = 10,
	Rings = 2,
	RingRays = 8,
	LosRays = 7,
	MaxCandidates = 6,
	CrosshairMode = "Auto",
}

local RANGES = {
	MinDist = { 0, 5000 }, MaxDist = { 0, 5000 }, MinHealth = { 0, 100 },
	DelayMs = { 0, 1000 }, RandMin = { 0, 1000 }, RandMax = { 0, 1000 },
	ReleaseMs = { 0, 2000 }, CooldownMs = { 0, 5000 }, GraceMs = { 0, 1000 },
	HitboxPx = { 0, 60 }, LeadMs = { 0, 500 }, MaxLeadStuds = { 0, 60 },
	Rings = { 0, 5 }, RingRays = { 4, 16 }, LosRays = { 1, 8 }, MaxCandidates = { 1, 16 },
}

local ENUMS = {
	Mode = { "Hold", "Toggle", "Always" },
	HitPart = { "Any", "Head", "Body" },
	FireMethod = { "Tool Activate", "Mouse Click" },
	CrosshairMode = { "Auto", "Cursor", "Center" },
}

local BOOLS = {
	Enabled = true, RequireTool = true, TeamCheck = true, ForceFieldCheck = true,
	HealthCheck = true, KnockedCheck = true, RandomDelay = true, AutoLead = true,
}

local function slab(o, d, h, tmin, tmax)
	if math.abs(d) < 1e-9 then
		if o < -h or o > h then
			return false, tmin, tmax
		end
		return true, tmin, tmax
	end
	local t1 = (-h - o) / d
	local t2 = (h - o) / d
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	if t1 > tmin then
		tmin = t1
	end
	if t2 < tmax then
		tmax = t2
	end
	return tmin <= tmax, tmin, tmax
end

local function rayBox(origin, dir, cf, half)
	local lo = cf:PointToObjectSpace(origin)
	local ld = cf:VectorToObjectSpace(dir)
	local ok, t0, t1 = slab(lo.X, ld.X, half.X, 0, math.huge)
	if not ok then
		return nil
	end
	ok, t0, t1 = slab(lo.Y, ld.Y, half.Y, t0, t1)
	if not ok then
		return nil
	end
	ok, t0, t1 = slab(lo.Z, ld.Z, half.Z, t0, t1)
	if not ok then
		return nil
	end
	return t0
end

---------------------------------------------------------------------
-- THE ENGINE
---------------------------------------------------------------------
local function createTriggerbot(userOpts)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer

	local STEP_NAME = string.format("Y1TriggerStep_%d_%d", math.floor(os.clock() * 1000), math.random(1, 1000000))

	local S = {}
	for k, v in pairs(CONFIG) do
		S[k] = v
	end

	local running = true
	local armed = false
	local firing = false
	local firingTool = nil
	local firingMethod = "Tool"
	local mouseVia = "exec"
	local mouseIgnoreUntil = 0
	local waitStart = nil
	local fireStart = 0
	local lastShot = -1000
	local lastHit = -1000
	local curDelay = 0
	local conns = {}
	local stateCbs = {}
	local lastNote = ""

	local det = { hit = false, stage = nil, rays = 0, candidates = 0 }

	local function notify()
		local key = tostring(S.Enabled) .. tostring(armed) .. tostring(firing)
		if key == lastNote then
			return
		end
		lastNote = key
		for i = 1, #stateCbs do
			pcall(stateCbs[i], S.Enabled, armed, firing)
		end
	end

	local mousePress = nil
	local mouseRelease = nil
	do
		local okP, fnP = pcall(function()
			return mouse1press
		end)
		local okR, fnR = pcall(function()
			return mouse1release
		end)
		if okP and type(fnP) == "function" then
			mousePress = fnP
		end
		if okR and type(fnR) == "function" then
			mouseRelease = fnR
		end
	end

	local vim = nil
	pcall(function()
		vim = game:GetService("VirtualInputManager")
	end)

	local function holdingTool()
		local char = player.Character
		if not char then
			return nil
		end
		return char:FindFirstChildOfClass("Tool")
	end

	local function vimButton(down)
		if vim == nil then
			return false
		end
		local m = UserInputService:GetMouseLocation()
		local ok = pcall(function()
			vim:SendMouseButtonEvent(m.X, m.Y, 0, down, game, 0)
		end)
		return ok
	end

	local function pressFire()
		if S.FireMethod == "Mouse Click" then
			if S.RequireTool and holdingTool() == nil then
				return false
			end
			firingTool = nil
			if mousePress ~= nil and mouseRelease ~= nil then
				mouseVia = "exec"
				mouseIgnoreUntil = os.clock() + 0.3
				if pcall(mousePress) then
					firingMethod = "Mouse"
					return true
				end
			end
			mouseVia = "vim"
			mouseIgnoreUntil = os.clock() + 0.3
			if vimButton(true) then
				firingMethod = "Mouse"
				return true
			end
			return false
		end

		local tool = holdingTool()
		if not tool then
			return false
		end
		firingMethod = "Tool"
		firingTool = tool
		tool:Activate()
		return true
	end

	local function releaseFire()
		if firingMethod == "Mouse" then
			mouseIgnoreUntil = os.clock() + 0.3
			if mouseVia == "exec" then
				if mouseRelease then
					pcall(mouseRelease)
				end
			else
				vimButton(false)
			end
			return
		end
		local tool = firingTool
		firingTool = nil
		if tool and tool.Parent then
			tool:Deactivate()
		end
	end

	local function stopFiring()
		if firing then
			firing = false
			releaseFire()
			notify()
		end
		waitStart = nil
	end

	local function setArmed(v)
		if not S.Enabled or not running then
			v = false
		end
		armed = v
		if not v then
			stopFiring()
		end
		notify()
	end

	local function refreshArmed()
		if S.Enabled and S.Mode == "Always" then
			setArmed(true)
		else
			setArmed(false)
		end
	end

	local clsCache = {}

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

	local function classify(plr, char, hum)
		local c = clsCache[char]
		if c ~= nil then
			return c
		end
		local result = "ok"
		if hum.Health <= 0 then
			result = "skip"
		elseif S.KnockedCheck and isKnocked(char) then
			result = "skip"
		elseif S.TeamCheck and plr.Team ~= nil and plr.Team == player.Team then
			result = "block"
		elseif S.ForceFieldCheck and char:FindFirstChildOfClass("ForceField") then
			result = "block"
		elseif S.HealthCheck then
			local maxHp = hum.MaxHealth
			if maxHp <= 0 then
				maxHp = 100
			end
			if hum.Health / maxHp * 100 < S.MinHealth then
				result = "block"
			end
		end
		clsCache[char] = result
		return result
	end

	local function isHeadPart(inst)
		if inst.Name == "Head" then
			return true
		end
		if inst:FindFirstAncestorOfClass("Accessory") then
			local weld = inst:FindFirstChildWhichIsA("Weld")
			if weld and weld.Part1 and weld.Part1.Name == "Head" then
				return true
			end
		end
		return false
	end

	local function partAllowed(inst)
		if S.HitPart == "Head" then
			return isHeadPart(inst)
		elseif S.HitPart == "Body" then
			return not isHeadPart(inst)
		end
		return true
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local exBuf = {}
	local rayCount = 0

	local function trace(origin, dir)
		table.clear(exBuf)
		local own = player.Character
		if own then
			exBuf[1] = own
		end
		for i = 1, 14 do
			rayParams.FilterDescendantsInstances = exBuf
			rayCount = rayCount + 1
			local res = workspace:Raycast(origin, dir, rayParams)
			if res == nil then
				return nil
			end
			local inst = res.Instance
			local model = inst:FindFirstAncestorOfClass("Model")
			local hum = nil
			if model then
				hum = model:FindFirstChildOfClass("Humanoid")
			end
			if hum then
				local plr = Players:GetPlayerFromCharacter(model)
				if plr ~= nil and plr ~= player and classify(plr, model, hum) == "skip" then
					exBuf[#exBuf + 1] = model
				else
					return res, model, plr, hum
				end
			elseif inst.Transparency >= 0.95 and not inst.CanCollide then
				exBuf[#exBuf + 1] = inst
			else
				return res, nil, nil, nil
			end
		end
		return nil
	end

	local function evalRay(origin, dir, myPos)
		local res, model, plr, hum = trace(origin, dir)
		if res == nil or plr == nil then
			return false
		end
		if classify(plr, model, hum) ~= "ok" then
			return false
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local p = res.Position
		if root then
			p = root.Position
		end
		local d = (p - myPos).Magnitude
		if d < S.MinDist or d > S.MaxDist then
			return false
		end
		return partAllowed(res.Instance)
	end

	local function seen(origin, point, char)
		local d = point - origin
		local m = d.Magnitude
		if m < 0.1 then
			return true
		end
		local res = trace(origin, d.Unit * (m + 1.5))
		if res == nil then
			return true
		end
		return res.Instance:IsDescendantOf(char)
	end

	local function refPoint(cam)
		local m = S.CrosshairMode
		if m == "Center" or (m == "Auto" and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter) then
			local vs = cam.ViewportSize
			return Vector2.new(vs.X / 2, vs.Y / 2)
		end
		return UserInputService:GetMouseLocation()
	end

	local function originPos(cam)
		local char = player.Character
		local rootPart = nil
		if char then
			rootPart = char:FindFirstChild("HumanoidRootPart")
		end
		if rootPart then
			return rootPart.Position
		end
		return cam.CFrame.Position
	end

	local pingMs = 0
	local pingAt = -10
	local function readPing(now)
		if now - pingAt < 0.5 then
			return
		end
		pingAt = now
		pcall(function()
			local item = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
			pingMs = item:GetValue()
		end)
	end

	local function leadSeconds()
		local ms = S.LeadMs
		if S.AutoLead then
			ms = ms + pingMs * 0.5
		end
		return ms / 1000
	end

	local function leadVector(root, lead)
		local vel = root.AssemblyLinearVelocity
		if vel.Magnitude < 1 then
			return Vector3.new(0, 0, 0)
		end
		local a = vel * lead
		if a.Magnitude > S.MaxLeadStuds then
			a = a.Unit * S.MaxLeadStuds
		end
		return a
	end

	local infoCache = {}
	local function getInfo(plr)
		local char = plr.Character
		if not char then
			return nil
		end
		local c = infoCache[plr]
		if c and c.char == char and c.hum.Parent == char and c.root.Parent == char then
			return c
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not root then
			return nil
		end
		c = { plr = plr, char = char, hum = hum, root = root }
		infoCache[plr] = c
		return c
	end
	conns[#conns + 1] = Players.PlayerRemoving:Connect(function(plr)
		infoCache[plr] = nil
	end)

	local candBuf = {}
	local function buildCandidates(cam, ref, myPos, lead)
		table.clear(candBuf)
		local vs = cam.ViewportSize
		local tanHalf = math.tan(math.rad(cam.FieldOfView) * 0.5)
		local camPos = cam.CFrame.Position
		local look = cam.CFrame.LookVector
		local tol = S.HitboxPx
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player then
				local info = getInfo(plr)
				if info and classify(plr, info.char, info.hum) == "ok" then
					local rp = info.root.Position
					local d = (rp - myPos).Magnitude
					if d >= S.MinDist and d <= S.MaxDist then
						local z = (rp - camPos):Dot(look)
						if z > 0.5 then
							local v = cam:WorldToViewportPoint(rp)
							local studsPerPx = (2 * z * tanHalf) / vs.Y
							local ahead = leadVector(info.root, lead)
							local bound = (5 + ahead.Magnitude) / studsPerPx + tol * 2 + 12
							local off = (Vector2.new(v.X, v.Y) - ref).Magnitude
							if off <= bound then
								candBuf[#candBuf + 1] = {
									info = info,
									off = off,
									pad = tol * studsPerPx,
									ahead = ahead,
								}
							end
						end
					end
				end
			end
		end
		for i = 2, #candBuf do
			local item = candBuf[i]
			local j = i - 1
			while j >= 1 and candBuf[j].off > item.off do
				candBuf[j + 1] = candBuf[j]
				j = j - 1
			end
			candBuf[j + 1] = item
		end
	end

	local function boxConfirmed(origin, dir, part, t, cand)
		local ahead = cand.ahead
		local hs = part.Size * 0.5
		local pcf = part.CFrame
		local P = origin + dir * t
		local lp = pcf:PointToObjectSpace(P - ahead)
		local q = Vector3.new(
			math.clamp(lp.X, -hs.X, hs.X),
			math.clamp(lp.Y, -hs.Y, hs.Y),
			math.clamp(lp.Z, -hs.Z, hs.Z)
		)
		local pts = {
			q,
			Vector3.new(0, 0, 0),
			Vector3.new(hs.X * 0.7, 0, 0),
			Vector3.new(-hs.X * 0.7, 0, 0),
			Vector3.new(0, hs.Y * 0.7, 0),
			Vector3.new(0, -hs.Y * 0.7, 0),
			Vector3.new(0, 0, hs.Z * 0.7),
			Vector3.new(0, 0, -hs.Z * 0.7),
		}
		local n = math.min(S.LosRays, #pts)
		for i = 1, n do
			if seen(origin, pcf:PointToWorldSpace(pts[i]), cand.info.char) then
				return true
			end
		end
		return false
	end

	local function boxStage(ray, cands, count)
		local origin = ray.Origin
		local dir = ray.Direction
		local maxT = S.MaxDist + 100
		for i = 1, count do
			local cand = cands[i]
			local char = cand.info.char
			local pad = cand.pad
			local grow = Vector3.new(pad, pad, pad)
			local kids = char:GetChildren()
			for k = 1, #kids do
				local part = kids[k]
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					local isHead = (part.Name == "Head")
					local allowed = (S.HitPart == "Any") or ((S.HitPart == "Head") == isHead)
					if allowed then
						local cf = part.CFrame + cand.ahead
						local half = part.Size * 0.5 + grow
						local t = rayBox(origin, dir, cf, half)
						if t ~= nil and t <= maxT then
							if boxConfirmed(origin, dir, part, t, cand) then
								return true
							end
						end
					end
				end
			end
		end
		return false
	end

	local function ringStage(cam, ref, myPos)
		local tol = S.HitboxPx
		if tol <= 0 or S.Rings <= 0 then
			return false
		end
		local range = S.MaxDist + 100
		local rays = S.RingRays
		for r = 1, S.Rings do
			local rad = tol * r / S.Rings
			local turn = 0
			if r % 2 == 0 then
				turn = math.pi / rays
			end
			for a = 0, rays - 1 do
				local ang = (a / rays) * 2 * math.pi + turn
				local ray = cam:ViewportPointToRay(ref.X + math.cos(ang) * rad, ref.Y + math.sin(ang) * rad)
				if evalRay(ray.Origin, ray.Direction * range, myPos) then
					return true
				end
			end
		end
		return false
	end

	local function detect(now)
		local cam = workspace.CurrentCamera
		det.hit = false
		det.stage = nil
		det.rays = 0
		det.candidates = 0
		if not cam then
			return
		end
		table.clear(clsCache)
		rayCount = 0
		readPing(now)

		local ref = refPoint(cam)
		local myPos = originPos(cam)
		local lead = leadSeconds()

		buildCandidates(cam, ref, myPos, lead)
		det.candidates = #candBuf
		if #candBuf == 0 then
			return
		end

		local ray = cam:ViewportPointToRay(ref.X, ref.Y)
		local range = S.MaxDist + 100

		if evalRay(ray.Origin, ray.Direction * range, myPos) then
			det.hit = true
			det.stage = "center"
		elseif boxStage(ray, candBuf, math.min(#candBuf, S.MaxCandidates)) then
			det.hit = true
			det.stage = "box"
		elseif ringStage(cam, ref, myPos) then
			det.hit = true
			det.stage = "ring"
		end
		det.rays = rayCount
	end

	local function rollDelay()
		if S.RandomDelay then
			local lo = math.min(S.RandMin, S.RandMax)
			local hi = math.max(S.RandMin, S.RandMax)
			return lo + math.random() * (hi - lo)
		end
		return S.DelayMs
	end

	local function tick(now)
		if not running or not armed then
			return
		end
		local hit = det.hit
		if hit then
			lastHit = now
		end
		local near = hit or (now - lastHit) * 1000 <= S.GraceMs

		if firing then
			local done = false
			local held = (now - fireStart) * 1000
			if S.ReleaseMs > 0 then
				if held >= S.ReleaseMs then
					done = true
				end
			else
				if not near then
					done = true
				end
			end
			if firingMethod == "Tool" and (firingTool == nil or firingTool.Parent ~= player.Character) then
				done = true
			end
			if done then
				stopFiring()
				if hit then
					if S.RandomDelay then
						curDelay = rollDelay()
						waitStart = now
					else
						curDelay = S.DelayMs
						waitStart = now - curDelay / 1000
					end
				end
			end
			return
		end

		if not near then
			waitStart = nil
			return
		end
		if not hit and waitStart == nil then
			return
		end

		if waitStart == nil then
			waitStart = now
			curDelay = rollDelay()
		end
		local need = S.DelayMs
		if S.RandomDelay then
			need = curDelay
		end
		if (now - waitStart) * 1000 >= need and (now - lastShot) * 1000 >= S.CooldownMs then
			if pressFire() then
				firing = true
				fireStart = now
				lastShot = now
				waitStart = nil
				notify()
			end
		end
	end

	local function renderStep()
		if not running or not armed then
			return
		end
		local now = os.clock()
		detect(now)
		tick(now)
	end

	pcall(function()
		RunService:UnbindFromRenderStep(STEP_NAME)
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, renderStep)

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		tick(os.clock())
	end)

	local function matches(input, bind)
		if bind.EnumType == Enum.KeyCode then
			return input.KeyCode == bind
		end
		return input.UserInputType == bind
	end

	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running or not S.Enabled or S.Mode == "Always" then
			return
		end
		if not matches(input, S.Key) then
			return
		end
		if S.Key == Enum.UserInputType.MouseButton1 and os.clock() < mouseIgnoreUntil then
			return
		end
		local isMouseBind = S.Key.EnumType ~= Enum.KeyCode
		if processed and not isMouseBind then
			return
		end
		if S.Mode == "Hold" then
			setArmed(true)
		else
			setArmed(not armed)
		end
	end)

	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if running and S.Mode == "Hold" and matches(input, S.Key) then
			if S.Key == Enum.UserInputType.MouseButton1 and os.clock() < mouseIgnoreUntil then
				return
			end
			setArmed(false)
		end
	end)

	local api = { Settings = S }

	function api:Set(name, value)
		if type(name) ~= "string" or CONFIG[name] == nil then
			return false
		end
		if name == "Key" then
			if typeof(value) ~= "EnumItem" then
				return false
			end
			if value.EnumType ~= Enum.KeyCode and value.EnumType ~= Enum.UserInputType then
				return false
			end
			S.Key = value
			setArmed(false)
			return true
		end
		if ENUMS[name] then
			local list = ENUMS[name]
			for i = 1, #list do
				if list[i] == value then
					S[name] = value
					if name == "Mode" then
						refreshArmed()
					end
					return true
				end
			end
			return false
		end
		if BOOLS[name] then
			if type(value) ~= "boolean" then
				return false
			end
			S[name] = value
			if name == "Enabled" then
				refreshArmed()
			end
			return true
		end
		if RANGES[name] then
			if type(value) ~= "number" then
				return false
			end
			S[name] = math.clamp(value, RANGES[name][1], RANGES[name][2])
			return true
		end
		return false
	end

	function api:Get(name)
		return S[name]
	end

	function api:SetEnabled(on)
		api:Set("Enabled", on and true or false)
	end

	function api:IsEnabled()
		return S.Enabled
	end

	function api:IsArmed()
		return armed
	end

	function api:IsFiring()
		return firing
	end

	function api:OnState(fn)
		if type(fn) == "function" then
			stateCbs[#stateCbs + 1] = fn
		end
	end

	function api:GetDebug()
		return { stage = det.stage, rays = det.rays, candidates = det.candidates, hit = det.hit }
	end

	function api:Unload()
		if not running then
			return
		end
		stopFiring()
		running = false
		armed = false
		S.Enabled = false
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_NAME)
		end)
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		stateCbs = {}
		notify()
	end

	if type(userOpts) == "table" then
		for k, v in pairs(userOpts) do
			api:Set(k, v)
		end
	end
	refreshArmed()

	return api
end

---------------------------------------------------------------------
-- THE PAGE (built like misc1.lua)
---------------------------------------------------------------------
local Trigger = {}

-- tall = the panel runs down to the bottom (level with the Aimbot | Silent | Triggerbot bar). The middle one is not tall,
-- because the bar sits under it.
local PANELS = {
	{ id = "Main",   title = "Triggerbot", tall = true,  icon = "target" },
	{ id = "Checks", title = "Checks",     tall = false, icon = "check" },
	{ id = "Tuning", title = "Tuning",     tall = true,  icon = "diamond" },
}

-- a slider reads / writes one setting of the engine (min / max come from RANGES)
local function sl(key, name, step, fmt)
	return { key = key, name = name, step = step, fmt = fmt, min = RANGES[key][1], max = RANGES[key][2] }
end

-- switch = the setting the switch controls (no switch = just a title). keybind / mode / enums / sliders fill the inset box.
local SECTIONS = {
	{ id = "trigger", panel = "Main", title = "Triggerbot", search = "Triggerbot", words = "trigger bot auto shoot fire",
		switch = "Enabled", keybind = true, mode = true,
		enums = {
			{ key = "FireMethod", name = "Fire Method" },
			{ key = "HitPart", name = "Hit Part" },
			{ key = "CrosshairMode", name = "Crosshair" },
		} },
	{ id = "tool", panel = "Main", title = "Require Tool", search = "Trigger Require Tool", words = "trigger tool gun holding",
		switch = "RequireTool" },
	{ id = "delay", panel = "Main", title = "Delay", search = "Trigger Delay", words = "trigger delay release cooldown grace ms",
		sliders = {
			sl("DelayMs", "Delay", 5, "%d ms"),
			sl("ReleaseMs", "Release", 5, "%d ms"),
			sl("CooldownMs", "Cooldown", 10, "%d ms"),
			sl("GraceMs", "Grace", 5, "%d ms"),
		} },
	{ id = "rdelay", panel = "Main", title = "Random Delay", search = "Trigger Random Delay", words = "trigger random delay humanize",
		switch = "RandomDelay",
		sliders = { sl("RandMin", "Min", 5, "%d ms"), sl("RandMax", "Max", 5, "%d ms") } },

	{ id = "team", panel = "Checks", title = "Team Check", search = "Trigger Team Check", words = "trigger team teammates",
		switch = "TeamCheck" },
	{ id = "ff", panel = "Checks", title = "Forcefield Check", search = "Trigger Forcefield Check", words = "trigger forcefield shield spawn",
		switch = "ForceFieldCheck" },
	{ id = "health", panel = "Checks", title = "Health Check", search = "Trigger Health Check", words = "trigger health low hp",
		switch = "HealthCheck", sliders = { sl("MinHealth", "Min Health", 1, "%d") } },
	{ id = "knocked", panel = "Checks", title = "Knocked Check", search = "Trigger Knocked Check", words = "trigger knocked ko down zee hood",
		switch = "KnockedCheck" },
	{ id = "dist", panel = "Checks", title = "Distance", search = "Trigger Distance", words = "trigger distance range min max studs",
		sliders = { sl("MinDist", "Min", 5, "%d"), sl("MaxDist", "Max", 5, "%d") } },

	{ id = "lead", panel = "Tuning", title = "Auto Lead", search = "Trigger Auto Lead", words = "trigger lead ping prediction",
		switch = "AutoLead",
		sliders = { sl("LeadMs", "Lead", 5, "%d ms"), sl("MaxLeadStuds", "Max Lead", 1, "%d") } },
	{ id = "detect", panel = "Tuning", title = "Detection", search = "Trigger Detection", words = "trigger detection hitbox rings rays candidates",
		sliders = {
			sl("HitboxPx", "Hitbox", 1, "%d px"),
			sl("Rings", "Rings", 1, "%d"),
			sl("RingRays", "Ring Rays", 1, "%d"),
			sl("LosRays", "Line Rays", 1, "%d"),
			sl("MaxCandidates", "Targets", 1, "%d"),
		} },
}

-- short key names for the Keybinds panel (LeftControl -> LCtrl, Zero -> 0 ...)
local KEY_SHORT = {
	LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
	LeftAlt = "LAlt", RightAlt = "RAlt", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Return = "Enter", Backquote = "`",
}

function Trigger.build(container, T, H, ctx)
	if type(ctx) ~= "table" then
		ctx = {}
	end
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH

	local GAP = 14
	local HEAD = 38
	local SPACE = tonumber(ctx.SwitcherSpace) or 31   -- height of the Aimbot | Silent | Triggerbot bar + its gap
	local EXTRAS_SPACE = 14

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

	local running = true
	local conns = {}

	-- the engine: a second copy from an older run is stopped first
	local okEnv, env = pcall(getgenv)
	if not okEnv or type(env) ~= "table" then
		env = nil
	end
	if env and env.Y1_TRIGGERBOT then
		pcall(function()
			env.Y1_TRIGGERBOT:Unload()
		end)
	end
	local api = createTriggerbot(CONFIG)
	if env then
		env.Y1_TRIGGERBOT = api
	end

	local root = new("Frame", {
		Name = "TriggerRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, GAP),
	}, root)

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

		if kind == "target" then
			-- ring with a dot in the middle
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
			local d = bit(4, 4, 0, 0)
			corner(d, 100)
		elseif kind == "check" then
			bit(5, 2, -3, 1.5, 45)
			bit(10, 2, 2, 0, -45)
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
	local count = #PANELS

	for i = 1, count do
		local def = PANELS[i]

		local extraH = -EXTRAS_SPACE
		if def.tall then
			extraH = SPACE
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
		label(panel, def.title, UDim2.fromOffset(40, 0), UDim2.new(1, -108, 0, HEAD),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR).ZIndex = 3

		-- badge: how many sections are in this panel
		local n = 0
		for k = 1, #SECTIONS do
			if SECTIONS[k].panel == def.id then
				n = n + 1
			end
		end
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
		label(badge, tostring(n), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
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
	end

	---------------------------------------------------------------------
	-- keybinds panel row (shown while the triggerbot is armed)
	---------------------------------------------------------------------
	local function keyLabel()
		local k = api:Get("Key")
		if k == nil or k == Enum.KeyCode.Unknown then
			return "None"
		end
		if k.EnumType == Enum.KeyCode then
			return k.Name
		end
		if k == Enum.UserInputType.MouseButton2 then
			return "Mouse 2"
		elseif k == Enum.UserInputType.MouseButton3 then
			return "Mouse 3"
		elseif k == Enum.UserInputType.MouseButton1 then
			return "Mouse 1"
		end
		return k.Name
	end

	local function shortKeyLabel()
		local k = api:Get("Key")
		if k ~= nil and k.EnumType == Enum.KeyCode and KEY_SHORT[k.Name] then
			return KEY_SHORT[k.Name]
		end
		return keyLabel()
	end

	local function syncHint()
		local win = ctx.Win
		if type(win) ~= "table" or type(win.SetHint) ~= "function" then
			return
		end
		if running and api:IsArmed() then
			local key = shortKeyLabel()
			if api:Get("Mode") == "Always" then
				key = "Always"
			end
			win:SetHint("Triggerbot", { title = "Triggerbot", key = key, active = true })
		else
			win:SetHint("Triggerbot", nil)
		end
	end
	api:OnState(function()
		if running then
			syncHint()
		end
	end)

	---------------------------------------------------------------------
	-- controls (switch, drop-down, slider, key box)
	---------------------------------------------------------------------
	local dragSlider = nil
	local listening = nil   -- the key box that waits for a key: { btn = TextButton }

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
	local function makeSlider(parent, order, spec)
		local S = {}
		S.row = new("Frame", {
			Name = spec.name .. "Slider",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, SLIDER_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent)
		label(S.row, spec.name, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 0, 18),
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
			local v = api:Get(spec.key)
			local fr = (v - spec.min) / (spec.max - spec.min)
			fill.Size = UDim2.new(fr, 0, 1, 0)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			valLbl.Text = string.format(spec.fmt, v)
		end

		function S.setFromX(px)
			local w = track.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local fr = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
			local v = spec.min + math.floor(fr * (spec.max - spec.min) / spec.step + 0.5) * spec.step
			api:Set(spec.key, math.clamp(v, spec.min, spec.max))
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
	-- ONE SECTION = name + switch on top, the settings in one inset box under it
	---------------------------------------------------------------------
	local sections = {}   -- [id] = { outer, box, body }

	local function buildSection(body, def, order)
		local outer = new("Frame", {
			Name = def.id .. "Section",
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
		label(head, def.title, UDim2.fromOffset(2, 0), UDim2.new(1, -56, 1, 0),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		if def.switch then
			makeSwitch(head, api:Get(def.switch) and true or false, function(on)
				api:Set(def.switch, on)
				syncHint()
			end)
		end

		local hasBox = def.keybind or def.mode or def.enums or def.sliders
		local box = nil
		if hasBox then
			box = new("Frame", {
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

			-- keybind row: click it, then press a key (Escape / Backspace clears it, Mouse 2 / 3 also work)
			if def.keybind then
				local kr = new("Frame", {
					Name = "KeybindRow",
					LayoutOrder = boxOrder(),
					Size = UDim2.new(1, 0, 0, ROW_H),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}, box)
				label(kr, "Keybind", UDim2.fromOffset(0, 0), UDim2.new(1, -(DD_W + 8), 1, 0),
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
					Text = keyLabel(),
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
					if listening == keyBtn then
						listening = nil
						keyBtn.Text = keyLabel()
						return
					end
					if listening then
						listening.Text = keyLabel()
					end
					listening = keyBtn
					keyBtn.Text = "Press a key..."
				end)
			end

			-- mode drop-down (Always / Toggle / Hold)
			if def.mode then
				makeDropdown(box, boxOrder(), "Mode", ENUMS.Mode,
					function()
						return api:Get("Mode")
					end,
					function(v)
						api:Set("Mode", v)
						syncHint()
					end)
			end

			-- other drop-downs (fire method, hit part, crosshair)
			if def.enums then
				for i = 1, #def.enums do
					local e = def.enums[i]
					makeDropdown(box, boxOrder(), e.name, ENUMS[e.key],
						function()
							return api:Get(e.key)
						end,
						function(v)
							api:Set(e.key, v)
						end)
				end
			end

			-- sliders
			if def.sliders then
				for i = 1, #def.sliders do
					makeSlider(box, boxOrder(), def.sliders[i])
				end
			end

		end

		sections[def.id] = { outer = outer, box = box, body = body }

		-- findable from the search box: Find switches to the Combat tab (done by the window), opens Triggerbot, scrolls
		-- to the section and flashes its box in red (or the title row when it has no box)
		local win = ctx.Win
		if type(win) == "table" and type(win.AddSearch) == "function" then
			win:AddSearch({
				owner = "Triggerbot",
				title = def.search,
				tab = "Combat",
				keywords = def.words or "",
				go = function()
					if type(win.CombatShow) == "function" then
						win.CombatShow("Triggerbot")
					end
					local sc = 1
					if win.Window then
						local us = win.Window:FindFirstChildOfClass("UIScale")
						if us and us.Scale > 0 then
							sc = us.Scale
						end
					end
					local y = (outer.AbsolutePosition.Y - body.AbsolutePosition.Y) / sc + body.CanvasPosition.Y - 10
					local maxY = math.max(0, (body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y) / sc)
					TweenService:Create(body, SMOOTH, { CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY)) }):Play()
					local st = nil
					if box then
						st = box:FindFirstChildOfClass("UIStroke")
					end
					if st then
						st.Color = T.ACCENT
						st.Thickness = 2
						TweenService:Create(st, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ Color = T.BORDER, Thickness = 1 }):Play()
					else
						local flash = new("Frame", {
							Size = UDim2.new(1, 0, 0, HEADER_H),
							BackgroundColor3 = T.ACCENT,
							BackgroundTransparency = 0.7,
							BorderSizePixel = 0,
							ZIndex = 5,
						}, outer)
						corner(flash, 6)
						local tw = TweenService:Create(flash, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ BackgroundTransparency = 1 })
						tw:Play()
						task.delay(1.3, function()
							flash:Destroy()
						end)
					end
				end,
			})
		end
	end

	-- build every section into its panel, a thin RED divider between two of them
	do
		local orders = {}
		local first = {}
		for i = 1, #SECTIONS do
			local def = SECTIONS[i]
			local pbody = bodies[def.panel]
			orders[def.panel] = orders[def.panel] or 0
			if first[def.panel] then
				orders[def.panel] = orders[def.panel] + 1
				new("Frame", {
					Name = "Divider",
					LayoutOrder = orders[def.panel],
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = T.ACCENT,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
				}, pbody)
			end
			first[def.panel] = true
			orders[def.panel] = orders[def.panel] + 1
			buildSection(pbody, def, orders[def.panel])
		end
	end

	---------------------------------------------------------------------
	-- KEYBIND LISTENING: the next key (or Mouse 2 / 3) becomes the triggerbot key
	---------------------------------------------------------------------
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
		if not running or not listening then
			return
		end
		local btn = listening
		local t = input.UserInputType
		local value = nil
		if t == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				value = Enum.KeyCode.Unknown   -- no key
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				value = input.KeyCode
			else
				return
			end
		elseif t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
			value = t
		else
			return
		end
		listening = nil
		api:Set("Key", value)
		btn.Text = keyLabel()
		syncHint()
	end)

	syncHint()

	---------------------------------------------------------------------
	-- UNLOAD
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		pcall(function()
			api:Unload()
		end)
		pcall(function()
			if type(ctx.Win) == "table" and type(ctx.Win.SetHint) == "function" then
				ctx.Win:SetHint("Triggerbot", nil)
			end
			if type(ctx.Win) == "table" and type(ctx.Win.RemoveSearch) == "function" then
				ctx.Win:RemoveSearch("Triggerbot")
			end
		end)
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		if env and env.Y1_TRIGGERBOT == api then
			env.Y1_TRIGGERBOT = nil
		end
		if root and root.Parent then
			root:Destroy()
		end
	end

	return { Api = api, Panels = bodies, Unload = unload }
end

return Trigger
