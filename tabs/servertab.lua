local ServerTab = {}

function ServerTab.build(container, T, H, ctx)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local TeleportService = game:GetService("TeleportService")
	local TweenService = game:GetService("TweenService")
	local player = Players.LocalPlayer
	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST

	local win = nil
	if type(ctx) == "table" then
		win = ctx.Win
	end

	local GREEN = Color3.fromRGB(52, 199, 120)
	local AMBER = Color3.fromRGB(232, 176, 70)
	local ROW_H = 46
	local BAR_H = 34
	local MAX_ROWS = 150
	local SORTS = { "Most Players", "Fewest Players", "Lowest Ping" }

	local running = true
	local mode = "zhd"
	local sortIndex = 1
	local query = ""
	local dirty = true
	local kick = false
	local servers = {}
	local located = {}
	local names = {}
	local tried = {}
	local pubData = {}
	local pubLoaded = false
	local lastSig = ""

	local httpFn = nil
	if syn and syn.request then
		httpFn = syn.request
	elseif http and http.request then
		httpFn = http.request
	elseif http_request then
		httpFn = http_request
	elseif request then
		httpFn = request
	end

	local clip = setclipboard or toclipboard

	local function toast(text)
		if win and type(win.Toast) == "function" then
			win:Toast(text)
		end
	end

	local function fetchJson(method, url, body)
		if not httpFn then
			return nil, 0
		end
		local req = { Url = url, Method = method }
		if body then
			req.Headers = { ["Content-Type"] = "application/json" }
			req.Body = HttpService:JSONEncode(body)
		end
		local ok, res = pcall(httpFn, req)
		if not ok or not res then
			return nil, 0
		end
		if res.StatusCode ~= 200 then
			return nil, res.StatusCode
		end
		local okJson, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
		if okJson then
			return data, 200
		end
		return nil, 0
	end

	local function isIdle()
		local w = win and win.Window
		if not w then
			return false
		end
		return (not w.Visible) or w.GroupTransparency > 0.9
	end

	local function shortId(jid)
		return string.sub(jid, 1, 8)
	end

	local function uptime(startedAt)
		if not startedAt or startedAt <= 0 then
			return nil
		end
		local mins = math.max(0, math.floor((os.time() - startedAt) / 60))
		if mins >= 60 then
			return math.floor(mins / 60) .. "h " .. mins % 60 .. "m"
		end
		return mins .. "m"
	end

	local function pingColor(ping)
		if not ping then
			return T.DIM_TEXT
		end
		if ping < 90 then
			return GREEN
		end
		if ping < 160 then
			return AMBER
		end
		return T.ACCENT
	end

	local function pingText(ping)
		if not ping then
			return "-"
		end
		return math.floor(ping + 0.5) .. " ms"
	end

	local function applyServers(list)
		local parts = {}
		local map = {}
		for jid, s in pairs(list) do
			parts[#parts + 1] = jid .. ":" .. s.count .. ":" .. s.sum
			for i = 1, #s.players do
				map[s.players[i]] = s
			end
		end
		table.sort(parts)
		local sig = table.concat(parts, "|")
		servers = list
		located = map
		if sig ~= lastSig then
			lastSig = sig
			dirty = true
		end
	end

	local function ownServer(extra)
		local ids = {}
		local sum = 0
		local list = Players:GetPlayers()
		for i = 1, #list do
			ids[i] = list[i].UserId
			sum = (sum + ids[i]) % 1000000007
		end
		local srv = {
			jobId = game.JobId,
			name = "This server",
			own = true,
			players = ids,
			count = #ids,
			max = Players.MaxPlayers,
			sum = sum,
			region = "Your server",
		}
		local ok, p = pcall(function()
			return player:GetNetworkPing() * 2000
		end)
		if ok then
			srv.ping = p
		end
		if extra then
			extra(srv)
		end
		return srv
	end

	local function parseIds(raw)
		local seen = {}
		local ids = {}
		local sum = 0
		for piece in string.gmatch(raw, "[^,]+") do
			local n = tonumber(piece)
			if n and n > 0 and n % 1 == 0 and not seen[n] then
				seen[n] = true
				ids[#ids + 1] = n
				sum = (sum + n) % 1000000007
			end
		end
		return ids, sum
	end

	local function serverName(entry, jid)
		local nm = entry:GetAttribute("serverName") or entry:GetAttribute("name")
		if type(nm) == "string" and nm ~= "" then
			return nm
		end
		return "Server " .. shortId(jid)
	end

	local function newestEntries()
		local out = {}
		local folder = ReplicatedStorage:FindFirstChild("Servers")
		if not folder then
			return out, false
		end
		local children = folder:GetChildren()
		for i = 1, #children do
			local e = children[i]
			local jid = e:GetAttribute("serverId")
			if type(jid) == "string" and jid ~= "" and e:GetAttribute("placeId") == game.PlaceId then
				local ticker = tonumber(e:GetAttribute("Ticker")) or 0
				local old = out[jid]
				if not old or ticker >= old.ticker then
					out[jid] = { entry = e, ticker = ticker }
				end
			end
		end
		return out, true
	end

	local hasFolder = true

	local function readZhd()
		local newest, found = newestEntries()
		hasFolder = found
		local list = {}
		for jid, item in pairs(newest) do
			local e = item.entry
			if jid ~= game.JobId then
				local ids, sum = parseIds(tostring(e:GetAttribute("players") or ""))
				list[jid] = {
					jobId = jid,
					name = serverName(e, jid),
					players = ids,
					sum = sum,
					count = #ids,
					max = tonumber(e:GetAttribute("maxPlayers")) or Players.MaxPlayers,
					region = tostring(e:GetAttribute("region") or "Unknown region"),
					ping = tonumber(e:GetAttribute("ping")),
					startedAt = tonumber(e:GetAttribute("startedAt")),
				}
			end
		end
		local own = newest[game.JobId]
		list[game.JobId] = ownServer(function(srv)
			if own then
				local e = own.entry
				srv.name = serverName(e, game.JobId)
				srv.max = tonumber(e:GetAttribute("maxPlayers")) or srv.max
				srv.startedAt = tonumber(e:GetAttribute("startedAt"))
			end
		end)
		applyServers(list)
	end

	local function readPub()
		local list = {}
		for jid, d in pairs(pubData) do
			if jid ~= game.JobId then
				list[jid] = {
					jobId = jid,
					name = "Server " .. shortId(jid),
					players = {},
					sum = 0,
					count = d.playing,
					max = d.max,
					region = "Public server",
					ping = d.ping,
				}
			end
		end
		list[game.JobId] = ownServer()
		list[game.JobId].players = {}
		applyServers(list)
	end

	local function refresh()
		if mode == "zhd" then
			readZhd()
		else
			readPub()
		end
	end

	local function resolveNames()
		local own = Players:GetPlayers()
		for i = 1, #own do
			local p = own[i]
			if not names[p.UserId] then
				names[p.UserId] = {
					name = p.Name,
					display = p.DisplayName,
					nl = string.lower(p.Name),
					dl = string.lower(p.DisplayName),
				}
			end
		end
		local batch = {}
		for id in pairs(located) do
			if not names[id] and not tried[id] then
				batch[#batch + 1] = id
				if #batch >= 100 then
					break
				end
			end
		end
		if #batch == 0 then
			return false
		end
		local url = "https://users.roblox.com/v1/users"
		local data, code = fetchJson("POST", url, { userIds = batch, excludeBannedUsers = false })
		if code == 429 then
			task.wait(4)
			return true
		end
		if data and data.data then
			for i = 1, #data.data do
				local u = data.data[i]
				names[u.id] = {
					name = u.name,
					display = u.displayName,
					nl = string.lower(u.name),
					dl = string.lower(u.displayName),
				}
			end
			dirty = true
		end
		if data or code ~= 0 then
			for i = 1, #batch do
				tried[batch[i]] = true
			end
		end
		return true
	end

	local function fetchPublic()
		local fresh = {}
		local cursor = nil
		for _ = 1, 5 do
			local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
				.. "/servers/Public?sortOrder=Desc&limit=100"
			if cursor then
				url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
			end
			local res = fetchJson("GET", url)
			if not res or not res.data then
				break
			end
			for i = 1, #res.data do
				local sv = res.data[i]
				if type(sv.id) == "string" then
					fresh[sv.id] = {
						playing = tonumber(sv.playing) or 0,
						max = tonumber(sv.maxPlayers) or Players.MaxPlayers,
						ping = tonumber(sv.ping),
					}
				end
			end
			cursor = res.nextPageCursor
			if not cursor then
				break
			end
			task.wait(1)
		end
		if next(fresh) ~= nil then
			pubData = fresh
		end
		pubLoaded = true
		if mode == "pub" then
			readPub()
		end
	end

	local function joinServer(srv)
		if srv.jobId == game.JobId then
			toast("You are already in this server")
			return
		end
		if srv.count >= srv.max then
			toast("This server is full")
			return
		end
		toast("Teleporting...")
		local ok = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.jobId, player)
		end)
		if not ok then
			toast("Teleport failed")
		end
	end

	local function copyId(srv)
		if clip then
			clip(srv.jobId)
			toast("Copied server id")
		else
			toast("Your executor cannot copy")
		end
	end

	local root = new("Frame", {
		Name = "ServerRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	local bar = new("Frame", {
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, bar)

	local function makeBox(order, width)
		local f = new("Frame", {
			LayoutOrder = order,
			Size = width,
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, bar)
		corner(f, 6)
		stroke(f, T.BORDER, 1, 0)
		return f
	end

	local function hoverFill(btn, base)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = base }):Play()
		end)
	end

	local modeBox = makeBox(1, UDim2.new(0, 210, 1, 0))
	local modeButtons = {}
	local function paintModes()
		for key, b in pairs(modeButtons) do
			local on = key == mode
			b.BackgroundTransparency = on and 0 or 1
			b.TextColor3 = on and T.TEXT_COLOR or T.DIM_TEXT
		end
	end
	local function makeModeButton(key, text, x)
		local b = new("TextButton", {
			AutoButtonColor = false,
			Position = UDim2.new(x, x == 0 and 3 or 1, 0, 3),
			Size = UDim2.new(0.5, -4, 1, -6),
			BackgroundColor3 = T.HOVER_GREY,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			Text = text,
		}, modeBox)
		corner(b, 4)
		modeButtons[key] = b
		return b
	end

	local searchBox = makeBox(2, UDim2.new(1, -(210 + 112 + 84 + 24), 1, 0))
	local searchInput = new("TextBox", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = "",
		PlaceholderText = "Search players or servers",
		PlaceholderColor3 = T.DIM_TEXT,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, searchBox)

	local function makeButton(order, width, text)
		local b = new("TextButton", {
			LayoutOrder = order,
			AutoButtonColor = false,
			Size = UDim2.new(0, width, 1, 0),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = text,
		}, bar)
		corner(b, 6)
		stroke(b, T.BORDER, 1, 0)
		hoverFill(b, T.CLUSTER_BG)
		return b
	end

	local sortButton = makeButton(3, 112, SORTS[1])
	local refreshButton = makeButton(4, 84, "Refresh")

	local statsLabel = label(root, "", UDim2.fromOffset(2, BAR_H + 8), UDim2.new(1, -4, 0, 16),
		Enum.Font.GothamMedium, 12, T.DIM_TEXT)

	local panel = new("Frame", {
		Position = UDim2.fromOffset(0, BAR_H + 30),
		Size = UDim2.new(1, 0, 1, -(BAR_H + 44)),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, root)
	corner(panel, 6)
	stroke(panel, T.BORDER, 1, 0)

	local list = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = T.BORDER,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, panel)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, list)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}, list)

	local emptyLabel = label(panel, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamMedium, 13, T.DIM_TEXT, Enum.TextXAlignment.Center)
	emptyLabel.TextWrapped = true

	local pool = {}

	local function makeRow(i)
		local r = {}
		r.frame = new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundColor3 = T.WELL,
			BorderSizePixel = 0,
		}, list)
		corner(r.frame, 6)
		stroke(r.frame, T.BORDER, 1, 0)
		hoverFill(r.frame, T.WELL)

		r.avatar = new("ImageLabel", {
			Position = UDim2.new(0, 8, 0.5, -17),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, r.frame)
		corner(r.avatar, 100)

		r.title = label(r.frame, "", UDim2.fromOffset(12, 6), UDim2.new(1, -330, 0, 18),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		r.sub = label(r.frame, "", UDim2.fromOffset(12, 24), UDim2.new(1, -330, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		r.title.TextTruncate = Enum.TextTruncate.AtEnd
		r.sub.TextTruncate = Enum.TextTruncate.AtEnd

		r.count = label(r.frame, "", UDim2.new(1, -312, 0, 0), UDim2.fromOffset(70, ROW_H),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER, Enum.TextXAlignment.Right)
		r.ping = label(r.frame, "", UDim2.new(1, -236, 0, 0), UDim2.fromOffset(70, ROW_H),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT, Enum.TextXAlignment.Right)

		local function rowButton(x, w, text, fill, ink)
			local b = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, x, 0.5, 0),
				Size = UDim2.fromOffset(w, 26),
				AutoButtonColor = false,
				BackgroundColor3 = fill,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = ink,
				Text = text,
			}, r.frame)
			corner(b, 5)
			return b
		end

		r.copy = rowButton(-82, 56, "Copy", T.CLUSTER_BG, T.ICON_HOVER)
		stroke(r.copy, T.BORDER, 1, 0)
		r.join = rowButton(-12, 62, "Join", T.JOIN_BG, T.BLACK)
		r.copy.Activated:Connect(function()
			if r.srv then
				copyId(r.srv)
			end
		end)
		r.join.Activated:Connect(function()
			if r.srv then
				joinServer(r.srv)
			end
		end)
		return r
	end

	local function setRow(r, item)
		local srv = item.srv
		r.srv = srv
		r.frame.Visible = true
		r.count.Text = srv.count .. "/" .. srv.max
		r.ping.Text = pingText(srv.ping)
		r.ping.TextColor3 = pingColor(srv.ping)
		if item.kind == "player" then
			r.avatar.Visible = true
			r.avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. item.uid .. "&w=150&h=150"
			r.title.Position = UDim2.fromOffset(54, 6)
			r.sub.Position = UDim2.fromOffset(54, 24)
			r.title.Text = item.name.display
			r.sub.Text = "@" .. item.name.name .. "  |  " .. srv.name
			return
		end
		r.avatar.Visible = false
		r.title.Position = UDim2.fromOffset(12, 6)
		r.sub.Position = UDim2.fromOffset(12, 24)
		local title = srv.name
		if srv.own then
			title = title .. "  (you)"
		end
		r.title.Text = title
		local sub = srv.region
		local up = uptime(srv.startedAt)
		if up then
			sub = sub .. "  |  up " .. up
		elseif mode == "pub" and not srv.own then
			sub = sub .. "  |  " .. srv.jobId
		end
		r.sub.Text = sub
	end

	local function sortItems(items)
		table.sort(items, function(a, b)
			local x, y = a.srv, b.srv
			if x.own ~= y.own then
				return x.own == true
			end
			if sortIndex == 3 then
				local px, py = x.ping or 1e9, y.ping or 1e9
				if px ~= py then
					return px < py
				end
			elseif sortIndex == 2 then
				if x.count ~= y.count then
					return x.count < y.count
				end
			elseif x.count ~= y.count then
				return x.count > y.count
			end
			return x.jobId < y.jobId
		end)
	end

	local function collect()
		local items = {}
		local q = string.lower(query)
		if mode == "zhd" and q ~= "" then
			for uid, srv in pairs(located) do
				local n = names[uid]
				if not n and tostring(uid) == q then
					n = { name = q, display = q, nl = q, dl = q }
				end
				if n and (string.find(n.nl, q, 1, true) or string.find(n.dl, q, 1, true)
					or tostring(uid) == q) then
					items[#items + 1] = { kind = "player", uid = uid, srv = srv, name = n }
				end
			end
			if #items > 0 then
				table.sort(items, function(a, b)
					return a.name.dl < b.name.dl
				end)
				return items
			end
		end
		for _, srv in pairs(servers) do
			local hit = q == ""
				or string.find(string.lower(srv.jobId), q, 1, true)
				or string.find(string.lower(srv.name), q, 1, true)
				or string.find(string.lower(srv.region), q, 1, true)
			if hit then
				items[#items + 1] = { kind = "server", srv = srv }
			end
		end
		sortItems(items)
		return items
	end

	local function emptyText()
		if mode == "zhd" and not hasFolder then
			return "The Zee Hood server list was not found in this game"
		end
		if mode == "pub" and not httpFn then
			return "Your executor has no request function"
		end
		if mode == "pub" and not pubLoaded then
			return "Loading servers..."
		end
		if query ~= "" then
			return "Nothing matches your search"
		end
		return "No servers found"
	end

	local function render()
		local items = collect()
		local n = math.min(#items, MAX_ROWS)
		for i = 1, n do
			if not pool[i] then
				pool[i] = makeRow(i)
			end
			setRow(pool[i], items[i])
		end
		for i = n + 1, #pool do
			pool[i].frame.Visible = false
			pool[i].srv = nil
		end
		emptyLabel.Text = n == 0 and emptyText() or ""

		local total = 0
		local playerTotal = 0
		for _, srv in pairs(servers) do
			total = total + 1
			playerTotal = playerTotal + srv.count
		end
		local text = total .. " servers"
		if mode == "zhd" then
			text = text .. "  |  " .. playerTotal .. " players"
		end
		if #items > MAX_ROWS then
			text = text .. "  |  showing " .. MAX_ROWS
		end
		statsLabel.Text = text
	end

	local function setMode(key)
		mode = key
		lastSig = ""
		paintModes()
		if key == "zhd" then
			searchInput.PlaceholderText = "Search players or servers"
		else
			searchInput.PlaceholderText = "Search servers"
			if not pubLoaded then
				kick = true
			end
		end
		pcall(refresh)
		dirty = true
	end

	makeModeButton("zhd", "Zhd Servers", 0).Activated:Connect(function()
		setMode("zhd")
	end)
	makeModeButton("pub", "Servers", 0.5).Activated:Connect(function()
		setMode("pub")
	end)

	sortButton.Activated:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButton.Text = SORTS[sortIndex]
		dirty = true
	end)

	refreshButton.Activated:Connect(function()
		kick = mode == "pub"
		pcall(refresh)
		dirty = true
		toast("Refreshing")
	end)

	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		query = searchInput.Text
		dirty = true
	end)

	paintModes()
	pcall(refresh)

	task.spawn(function()
		local tick = 0
		while running do
			if not isIdle() then
				tick = tick + 1
				if tick % 4 == 0 then
					pcall(refresh)
				end
				if dirty then
					dirty = false
					local ok, err = pcall(render)
					if not ok then
						warn("[servertab] " .. tostring(err))
					end
				end
			end
			task.wait(0.5)
		end
	end)

	task.spawn(function()
		while running do
			if mode ~= "zhd" or isIdle() then
				task.wait(2)
			else
				local ok, more = pcall(resolveNames)
				task.wait((ok and more) and 0.6 or 2)
			end
		end
	end)

	task.spawn(function()
		while running do
			if mode == "pub" and httpFn and not isIdle() then
				pcall(fetchPublic)
				kick = false
				for _ = 1, 20 do
					if kick or not running then
						break
					end
					task.wait(1)
				end
			else
				task.wait(0.5)
			end
		end
	end)

	local function unload()
		running = false
		pcall(function()
			root:Destroy()
		end)
	end

	return { Root = root, Unload = unload }
end

return ServerTab
