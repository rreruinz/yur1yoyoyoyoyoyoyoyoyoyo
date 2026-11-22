-- hometab.lua  (Y1 Home tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Home overview INTO a frame (the Home tab of ui.lua). It does not make its own window.
--
--   Good evening, <name>
--   Welcome back to Y1. Here's your overview.
--
--   [ icon ]  Account                [ icon ]  Application
--             <name>                           Beta 0.6
--             Lifetime membership              Current build
--
--   [ game icon ]  Current session
--             <game name>
--             Connected game - Session information
--
--   What's new                                                              [Beta 0.6]
--   Yur1 is starting to get done..
--
-- MAINTENANCE: while ctx.Maintenance is not false (the default) the right edge of the greeting row shows an
-- amber warning symbol (a diamond with a "!", it pulses softly) and the text "Under maintenance"
-- (ctx.MaintenanceText changes the words). The greeting stays on the left. Set Maintenance = false in the
-- Home table of main.lua to hide the maintenance notice.
--
-- LOOK: every block is its own card (dark fill, thin border, rounded). Inside a card the icon sits in a
-- small rounded tile on the LEFT, centred on the middle of the text block (title, value, caption), so the
-- icon and its information read as one unit.
--
-- * the greeting follows the time on this device: morning 05:00-11:59, afternoon 12:00-16:59,
--   evening 17:00-20:59, night 21:00-04:59
-- * <name> is the yur1 account name from the login (getgenv().Y1_SESSION.username)
-- * membership: "Lifetime membership", or "Expires in 3d 4h" (live) for a timed key
--   (reads lifetime / key_expires_at from getgenv().Y1_SESSION)
-- * Current session: the tile shows the icon of the game you are in (until it loads, the first letter of the game)
-- * Account picture: double-click the Account icon to set a picture. Paste an image link (PNG or JPG) or the
--   file name of an image in your executor's workspace folder. It is copied to  Y1/account_<name>_<time>.png|jpg
--   and remembered in  Y1/account_<name>.txt , so it is still there next time. "Remove" brings the icon back.
--   (needs writefile / readfile / getcustomasset in your executor)
-- * options (the Home table in main.lua is passed in as ctx):
--     Build = "Beta 0.6"                       text of the Application card and the What's new badge
--     WhatsNew = "..."                         text under What's new
--
--   build(container, T, H, ctx)  ->  { Unload = fn }

local HomeTab = {}

function HomeTab.build(container, T, H, ctx)
	ctx = ctx or {}
	local MarketplaceService = game:GetService("MarketplaceService")
	local TweenService = game:GetService("TweenService")
	local TextService = game:GetService("TextService")
	local new, corner, stroke = H.new, H.corner, H.stroke
	local RADIUS = T.RADIUS

	local alive = true
	local PAD = 16
	local GAP = 12             -- space between the cards
	local CARD_H = 76
	local NEWS_H = 78          -- height of the What's new card
	local BOTTOM_GAP = 18      -- empty space between the What's new card and the bottom of the page
	local TILE = 40            -- the rounded square that holds an icon
	local TILE_X = 14          -- its distance from the left edge of the card
	local TEXT_X = TILE_X + TILE + 14   -- where the text column starts inside a card
	local buildText = tostring(ctx.Build or "Beta 0.6")
	local maintenance = (ctx.Maintenance ~= false)
	local maintenanceText = tostring(ctx.MaintenanceText or "Under maintenance")
	local AMBER = Color3.fromRGB(224, 168, 80)
	local whatsNewText = tostring(ctx.WhatsNew or "Yur1 is starting to get done..")
	local DOT = "\u{00B7}"

	---------------------------------------------------------------------
	-- DATA
	---------------------------------------------------------------------
	local function getSession()
		local ok, genv = pcall(getgenv)
		if ok and type(genv) == "table" and type(genv.Y1_SESSION) == "table" then
			return genv.Y1_SESSION
		end
		return nil
	end

	local function accountName()
		local s = getSession()
		if s and type(s.username) == "string" and s.username ~= "" then
			return s.username
		end
		return nil
	end

	local function greetingWord()
		local hour = tonumber(os.date("%H")) or 12
		if hour >= 5 and hour < 12 then
			return "Good morning"
		elseif hour >= 12 and hour < 17 then
			return "Good afternoon"
		elseif hour >= 17 and hour < 21 then
			return "Good evening"
		end
		return "Good night"
	end

	local function escape(s)
		s = string.gsub(s, "&", "&amp;")
		s = string.gsub(s, "<", "&lt;")
		s = string.gsub(s, ">", "&gt;")
		return s
	end

	-- how many seconds until an ISO date like 2026-12-01T10:00:00Z (negative = already past), nil if unreadable
	local function secondsUntil(stamp)
		if type(stamp) ~= "string" then
			return nil
		end
		local y, mo, d, h, mi, sec = string.match(stamp, "(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
		if y == nil then
			return nil
		end
		local ok, res = pcall(function()
			local t = os.time({
				year = tonumber(y), month = tonumber(mo), day = tonumber(d),
				hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec),
			})
			local off = os.time(os.date("*t")) - os.time(os.date("!*t"))
			return (t + off) - os.time()
		end)
		if ok and type(res) == "number" then
			return res
		end
		return nil
	end

	-- 273600 -> "3d 4h", 15120 -> "4h 12m", 725 -> "12m 5s"
	local function formatLeft(sec)
		sec = math.floor(sec)
		local d = math.floor(sec / 86400)
		local h = math.floor((sec % 86400) / 3600)
		local m = math.floor((sec % 3600) / 60)
		local r = sec % 60
		if d > 0 then
			return d .. "d " .. h .. "h"
		elseif h > 0 then
			return h .. "h " .. m .. "m"
		elseif m > 0 then
			return m .. "m " .. r .. "s"
		end
		return r .. "s"
	end

	-- membership from the login: "lifetime", "timed" (target = the os.clock() moment it ends) or "none"
	local memberMode = "none"
	local memberTarget = 0
	do
		local s = getSession()
		if s then
			if s.lifetime == true then
				memberMode = "lifetime"
			elseif type(s.key_expires_at) == "string" then
				local left = secondsUntil(s.key_expires_at)
				if left ~= nil then
					memberMode = "timed"
					memberTarget = os.clock() + left
				end
			end
		end
	end

	---------------------------------------------------------------------
	-- BUILDING BLOCKS
	---------------------------------------------------------------------
	local function text(parent, str, pos, size, font, textSize, color, align)
		return new("TextLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = pos,
			Size = size,
			Font = font,
			Text = str,
			TextSize = textSize,
			TextColor3 = color,
			TextXAlignment = align or Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, parent)
	end

	-- small line icons (16 x 16, drawn with frames, in the icon colour)
	local function iconPerson(h)
		local head = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 1),
			Size = UDim2.fromOffset(6, 6),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, h)
		corner(head, 100)
		stroke(head, T.ICON_HOVER, 1.5, 0)
		local clip = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(13, 6),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, h)
		local body = new("Frame", {
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, clip)
		corner(body, 100)
		stroke(body, T.ICON_HOVER, 1.5, 0)
	end

	local function iconWindow(h)
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(13, 11),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, h)
		corner(box, 3)
		stroke(box, T.ICON_HOVER, 1.5, 0)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, -2.5),
			Size = UDim2.fromOffset(13, 1.5),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
		}, h)
	end

	local root = new("Frame", {
		Name = "HomeRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	-- a plain card: dark fill, thin border, rounded corners
	-- fromBottom = true: y is the gap above the bottom edge of the page and the card stands on it
	local function makeCard(name, xs, xo, ws, wo, y, h, fromBottom)
		local pos = UDim2.new(xs, xo, 0, y)
		local anchor = Vector2.new(0, 0)
		if fromBottom then
			pos = UDim2.new(xs, xo, 1, -y)
			anchor = Vector2.new(0, 1)
		end
		local c = new("Frame", {
			Name = name,
			AnchorPoint = anchor,
			Position = pos,
			Size = UDim2.new(ws, wo, 0, h),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, root)
		corner(c, RADIUS + 4)
		stroke(c, T.BORDER, 1, 0)
		return c
	end

	-- an information card: the icon tile on the left, centred on the text block
	-- (title, value, caption) on the right. Returns the value label, the caption label, the tile and the icon holder.
	local function infoCard(name, xs, xo, ws, wo, y, iconFn)
		local c = makeCard(name, xs, xo, ws, wo, y, CARD_H)

		-- icon tile, vertically centred in the card
		local tile = new("Frame", {
			Name = "IconTile",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, TILE_X, 0.5, 0),
			Size = UDim2.fromOffset(TILE, TILE),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(tile, RADIUS + 4)
		stroke(tile, T.BORDER, 1, 0)

		-- the 16x16 icon is centred in the tile and scaled up a little so it fills it nicely
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, tile)
		new("UIScale", { Scale = 1.25 }, holder)
		iconFn(holder)

		-- text column: three lines whose combined height is centred on the tile's middle (the card's middle)
		--   title 16 + gap 2 + value 24 + gap 2 + caption 16 = 60  ->  starts 10px from the top of an 80px card
		local top = (CARD_H - 60) / 2
		text(c, name, UDim2.fromOffset(TEXT_X, top), UDim2.new(1, -(TEXT_X + 14), 0, 16),
			Enum.Font.GothamMedium, 12, T.DIM_TEXT)
		local value = text(c, "", UDim2.fromOffset(TEXT_X, top + 18), UDim2.new(1, -(TEXT_X + 14), 0, 24),
			Enum.Font.GothamBold, 18, T.TEXT_COLOR)
		local cap = text(c, "", UDim2.fromOffset(TEXT_X, top + 44), UDim2.new(1, -(TEXT_X + 14), 0, 16),
			Enum.Font.GothamMedium, 12, T.ICON)
		return value, cap, tile, holder
	end

	---------------------------------------------------------------------
	-- HEADER: greeting, subtitle
	---------------------------------------------------------------------
	-- a hidden probe: its width tells how much the window is scaled (the window can be shrunk / maximized)
	local probe = new("Frame", {
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, root)

	-- the maintenance notice on the RIGHT edge of the greeting row: a warning diamond with a "!" and the words
	local notice = nil
	local noticeLabel = nil
	local noticeFull = 0   -- width of the whole notice (symbol + words) in pixels
	if maintenance then
		local okSize, sz = pcall(function()
			return TextService:GetTextSize(maintenanceText, 14, Enum.Font.GothamBold, Vector2.new(1000, 28))
		end)
		local wordsW = #maintenanceText * 8
		if okSize and sz then
			wordsW = sz.X
		end
		noticeFull = 28 + 8 + wordsW + 2

		notice = new("Frame", {
			Name = "MaintenanceNotice",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -PAD, 0, 10),
			Size = UDim2.fromOffset(noticeFull, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, root)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}, notice)

		local sym = new("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, notice)
		local diamond = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(19, 19),
			Rotation = 45,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, sym)
		corner(diamond, 5)
		local diamondStroke = stroke(diamond, AMBER, 2, 0)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			Text = "!",
			TextSize = 16,
			TextColor3 = AMBER,
		}, sym)
		-- a slow soft pulse so it reads as a status, not as decoration
		TweenService:Create(diamondStroke,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.65 }):Play()

		noticeLabel = new("TextLabel", {
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(noticeFull - 36, 28),
			Font = Enum.Font.GothamBold,
			Text = maintenanceText,
			TextSize = 14,
			TextColor3 = T.TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, notice)
	end

	-- the greeting, on the left like before
	local greeting = new("TextLabel", {
		Name = "Greeting",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(PAD, 10),
		Size = UDim2.new(1, -PAD * 2, 0, 28),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextSize = 22,
		TextColor3 = T.TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
	}, root)

	-- keeps the greeting and the notice from ever covering each other:
	-- enough room -> symbol + words on the right, the greeting gets the rest.
	-- too narrow -> only the symbol stays (the words are hidden), so the greeting always keeps its space.
	local function layoutHeader()
		local scale = probe.AbsoluteSize.X / 100
		if scale <= 0 then
			scale = 1
		end
		local width = root.AbsoluteSize.X / scale
		if width <= 0 then
			return
		end
		local reserve = 0
		if maintenance then
			local roomIfFull = width - PAD * 2 - noticeFull - 14
			if roomIfFull >= 190 then
				noticeLabel.Visible = true
				notice.Size = UDim2.fromOffset(noticeFull, 28)
				reserve = noticeFull + 14
			else
				noticeLabel.Visible = false
				notice.Size = UDim2.fromOffset(28, 28)
				reserve = 28 + 14
			end
		end
		greeting.Size = UDim2.new(1, -(PAD * 2 + reserve), 0, 28)
	end
	layoutHeader()
	task.defer(layoutHeader)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHeader)

	text(root, "Welcome back to Y1. Here's your overview.", UDim2.fromOffset(PAD, 38), UDim2.new(1, -PAD * 2, 0, 16),
		Enum.Font.GothamMedium, 11, T.ICON)

	---------------------------------------------------------------------
	-- ROW 1: Account | Application   (two cards side by side, a small gap between them)
	---------------------------------------------------------------------
	local ROW1 = 62
	local half = GAP / 2
	local accValue, accCap, accTile, accHolder = infoCard("Account", 0, PAD, 0.5, -(PAD + half), ROW1, iconPerson)
	local appValue, appCap = infoCard("Application", 0.5, half, 0.5, -(PAD + half), ROW1, iconWindow)

	---------------------------------------------------------------------
	-- ROW 2: Current session (full width)
	---------------------------------------------------------------------
	local ROW2 = ROW1 + CARD_H + GAP
	local sesValue, sesCap, sesTile, sesHolder = infoCard("Current session", 0, PAD, 1, -PAD * 2, ROW2,
		function() end)
	sesHolder.Visible = false

	---------------------------------------------------------------------
	-- ROW 3: What's new (a card too, so the page reads as one set)
	---------------------------------------------------------------------
	-- it stands on the bottom of the page with BOTTOM_GAP of free space under it, so it never touches
	-- the tab bar, whatever size the window is
	local news = makeCard("What's new", 0, PAD, 1, -PAD * 2, BOTTOM_GAP, NEWS_H, true)
	text(news, "What's new", UDim2.fromOffset(14, 11), UDim2.new(1, -110, 0, 20), Enum.Font.GothamBold, 14,
		T.TEXT_COLOR)
	local badge = new("Frame", {
		Name = "BuildBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 13),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
	}, news)
	corner(badge, 100)
	stroke(badge, T.BORDER, 1, 0)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, badge)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Enum.Font.GothamBold,
		Text = buildText,
		TextSize = 10,
		TextColor3 = T.TEXT_COLOR,
	}, badge)
	text(news, whatsNewText, UDim2.fromOffset(14, 38), UDim2.new(1, -28, 0, 36), Enum.Font.GothamMedium, 12,
		T.ICON).TextWrapped = true

	---------------------------------------------------------------------
	-- FILL IN
	---------------------------------------------------------------------
	local lastGreeting = nil
	local function paintGreeting()
		local word = greetingWord()
		local name = accountName()
		local t = word
		if name then
			t = word .. ", <font color=\"rgb(196,92,92)\">" .. escape(name) .. "</font>"
		end
		if t ~= lastGreeting then
			lastGreeting = t
			greeting.Text = t
		end
	end

	local function paintMember()
		local t = "Member"
		if memberMode == "lifetime" then
			t = "Lifetime membership"
		elseif memberMode == "timed" then
			local left = memberTarget - os.clock()
			if left <= 0 then
				t = "Membership expired"
			else
				t = "Expires in " .. formatLeft(left)
			end
		end
		accCap.Text = t
	end

	paintGreeting()
	accValue.Text = accountName() or "Guest"
	paintMember()
	appValue.Text = buildText
	appCap.Text = "Current build"
	sesValue.Text = game.Name
	sesCap.Text = "Connected game " .. DOT .. " Session information"

	-- the real game name comes from the marketplace (in the background)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			if alive and sesValue.Parent then
				sesValue.Text = info.Name
			end
		end
	end)

	-- the greeting follows the time of day, the membership counts down
	task.spawn(function()
		local n = 0
		while alive do
			task.wait(1)
			if not alive or not root.Parent then
				return
			end
			n = n + 1
			if memberMode == "timed" then
				paintMember()
			end
			if n % 30 == 0 then
				paintGreeting()
			end
		end
	end)

	---------------------------------------------------------------------
	-- GAME ICON (the Current session tile shows the icon of the game you are in)
	---------------------------------------------------------------------
	do
		local initial = string.upper(string.sub(game.Name, 1, 1))
		if initial == "" then
			initial = "?"
		end
		local letter = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBold,
			Text = initial,
			TextSize = 18,
			TextColor3 = T.ICON_HOVER,
		}, sesTile)
		local gameIcon = new("ImageLabel", {
			Name = "GameIcon",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Crop,
			ImageTransparency = 1,
			Image = "",
		}, sesTile)
		corner(gameIcon, RADIUS + 3)

		local function tryImage(url, seconds)
			gameIcon.Image = url
			local started = os.clock()
			while alive and os.clock() - started < seconds do
				if gameIcon.IsLoaded then
					return true
				end
				task.wait(0.15)
			end
			return alive and gameIcon.IsLoaded
		end

		task.spawn(function()
			local ok = false
			if game.GameId ~= 0 then
				ok = tryImage("rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150", 6)
			end
			if not ok and alive then
				local good, info = pcall(function()
					return MarketplaceService:GetProductInfo(game.PlaceId)
				end)
				if good and type(info) == "table" then
					local assetId = tonumber(info.IconImageAssetId)
					if assetId and assetId ~= 0 then
						ok = tryImage("rbxassetid://" .. tostring(assetId), 6)
					end
				end
			end
			if ok and alive and gameIcon.Parent then
				letter.Visible = false
				TweenService:Create(gameIcon, TweenInfo.new(0.25), { ImageTransparency = 0 }):Play()
			end
		end)
	end

	---------------------------------------------------------------------
	-- ACCOUNT PICTURE (double-click the Account icon; the picture is saved in the executor's workspace folder)
	---------------------------------------------------------------------
	do
		local FOLDER = "Y1"
		local MAX_BYTES = 6 * 1024 * 1024
		local DOUBLE_CLICK = 0.45
		local ACCENT = T.ACCENT or Color3.fromRGB(196, 92, 92)
		local owner = string.lower(accountName() or "guest")
		local safe = string.gsub(owner, "[^%w_%-]", "_")
		local metaPath = FOLDER .. "/account_" .. safe .. ".txt"

		local function safeCall(fn, ...)
			local ok, res = pcall(fn, ...)
			if ok then
				return res
			end
			return nil
		end

		local function ensureFolder()
			if safeCall(isfolder, FOLDER) ~= true then
				pcall(makefolder, FOLDER)
			end
		end

		local function readMeta()
			if safeCall(isfile, metaPath) ~= true then
				return nil
			end
			local s = safeCall(readfile, metaPath)
			if type(s) ~= "string" then
				return nil
			end
			local path = string.match(s, "^file:(.-)%s*$")
			if path == nil or path == "" then
				return nil
			end
			return path
		end

		local function writeMeta(path)
			ensureFolder()
			return (pcall(writefile, metaPath, "file:" .. path))
		end

		local function customAsset(path)
			local fn = getcustomasset or getsynasset
			if not fn then
				return nil
			end
			local ok, res = pcall(fn, path)
			if ok and type(res) == "string" and res ~= "" then
				return res
			end
			return nil
		end

		local function download(url)
			local req = (syn and syn.request) or (http and http.request) or http_request or request
			if req then
				local ok, res = pcall(req, { Url = url, Method = "GET" })
				if ok and type(res) == "table" and res.StatusCode == 200
					and type(res.Body) == "string" and res.Body ~= "" then
					return res.Body
				end
			end
			local ok2, body = pcall(function()
				return game:HttpGet(url)
			end)
			if ok2 and type(body) == "string" and body ~= "" then
				return body
			end
			return nil
		end

		local function imageType(bytes)
			if string.sub(bytes, 1, 4) == "\137PNG" then
				return "png"
			end
			if string.sub(bytes, 1, 3) == "\255\216\255" then
				return "jpg"
			end
			return nil
		end

		local avatar = new("ImageLabel", {
			Name = "AccountPicture",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Crop,
			Image = "",
			Visible = false,
		}, accTile)
		corner(avatar, RADIUS + 3)

		local hasPicture = false
		local function showPicture(content)
			if content then
				avatar.Image = content
				avatar.Visible = true
				accHolder.Visible = false
				hasPicture = true
			else
				avatar.Visible = false
				avatar.Image = ""
				accHolder.Visible = true
				hasPicture = false
			end
		end

		do
			local saved = readMeta()
			if saved and safeCall(isfile, saved) == true then
				showPicture(customAsset(saved))
			end
		end

		local function removeOldFile()
			local old = readMeta()
			if old then
				pcall(delfile, old)
			end
		end

		-- returns true, or false and a message
		local function applyInput(raw)
			raw = string.gsub(raw, "^%s+", "")
			raw = string.gsub(raw, "%s+$", "")
			if raw == "" then
				return false, "Type an image link or a file name first."
			end
			if not (getcustomasset or getsynasset) then
				return false, "Your executor can't show local images."
			end

			local bytes = nil
			if string.match(string.lower(raw), "^https?://") then
				bytes = download(raw)
				if not bytes then
					return false, "Could not download that link."
				end
			else
				if safeCall(isfile, raw) ~= true then
					return false, "No file with that name in your workspace folder."
				end
				bytes = safeCall(readfile, raw)
				if type(bytes) ~= "string" or bytes == "" then
					return false, "Could not read that file."
				end
			end

			if #bytes > MAX_BYTES then
				return false, "That image is too big (6 MB max)."
			end
			local ext = imageType(bytes)
			if not ext then
				return false, "Use a PNG or JPG image."
			end

			ensureFolder()
			local path = FOLDER .. "/account_" .. safe .. "_" .. tostring(os.time()) .. "." .. ext
			if not pcall(writefile, path, bytes) then
				return false, "Could not save the image."
			end
			local content = customAsset(path)
			if not content then
				pcall(delfile, path)
				return false, "Your executor could not load the image."
			end

			removeOldFile()
			if not writeMeta(path) then
				return false, "Could not save the image."
			end
			showPicture(content)
			return true, ""
		end

		local function removePicture()
			removeOldFile()
			if safeCall(isfile, metaPath) == true then
				if not pcall(delfile, metaPath) then
					pcall(writefile, metaPath, "")
				end
			end
			showPicture(nil)
		end

		-- the small dialog
		local overlay = new("TextButton", {
			Name = "PictureDialog",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Visible = false,
			ZIndex = 20,
		}, root)
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(330, 176),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 21,
		}, overlay)
		corner(box, RADIUS + 4)
		stroke(box, T.BORDER, 1, 0)

		text(box, "Account picture", UDim2.fromOffset(16, 14), UDim2.new(1, -32, 0, 20),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		local hint = text(box,
			"Paste an image link (PNG or JPG), or the file name of an image in your executor's workspace folder.",
			UDim2.fromOffset(16, 38), UDim2.new(1, -32, 0, 30), Enum.Font.GothamMedium, 11, T.ICON)
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.TextTruncate = Enum.TextTruncate.None

		local input = new("TextBox", {
			Position = UDim2.fromOffset(16, 76),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.GothamMedium,
			PlaceholderText = "https://...  or  picture.png",
			PlaceholderColor3 = T.DIM_TEXT,
			Text = "",
			TextSize = 12,
			TextColor3 = T.TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, box)
		corner(input, RADIUS)
		stroke(input, T.BORDER, 1, 0)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, input)

		local status = text(box, "", UDim2.fromOffset(16, 112), UDim2.new(1, -32, 0, 14),
			Enum.Font.GothamMedium, 11, ACCENT)

		local function makeButton(label, anchorX, xOffset, primary)
			local b = new("TextButton", {
				AnchorPoint = Vector2.new(anchorX, 0),
				Position = UDim2.new(anchorX, xOffset, 0, 134),
				Size = UDim2.fromOffset(76, 28),
				BackgroundColor3 = primary and ACCENT or T.CLUSTER_BG,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Enum.Font.GothamBold,
				Text = label,
				TextSize = 12,
				TextColor3 = primary and Color3.new(1, 1, 1) or T.TEXT_COLOR,
			}, box)
			corner(b, RADIUS)
			if not primary then
				stroke(b, T.BORDER, 1, 0)
			end
			local rest = b.BackgroundColor3
			local over = primary and Color3.fromRGB(212, 110, 110) or T.BORDER
			b.MouseEnter:Connect(function()
				b.BackgroundColor3 = over
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundColor3 = rest
			end)
			return b
		end
		local saveBtn = makeButton("Save", 1, -16, true)
		local cancelBtn = makeButton("Cancel", 1, -100, false)
		local removeBtn = makeButton("Remove", 0, 16, false)

		for _, d in ipairs(box:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 22
			end
		end

		local busy = false
		local function closeDialog()
			overlay.Visible = false
			input:ReleaseFocus()
		end
		local function openDialog()
			input.Text = ""
			status.Text = ""
			removeBtn.Visible = hasPicture
			busy = false
			overlay.Visible = true
			task.defer(function()
				if overlay.Visible then
					pcall(function()
						input:CaptureFocus()
					end)
				end
			end)
		end

		local function save()
			if busy then
				return
			end
			busy = true
			status.TextColor3 = T.DIM_TEXT
			status.Text = "Saving..."
			task.spawn(function()
				local ok, message = applyInput(input.Text)
				busy = false
				if not alive or not overlay.Parent then
					return
				end
				if ok then
					closeDialog()
				else
					status.TextColor3 = ACCENT
					status.Text = message
				end
			end)
		end

		saveBtn.Activated:Connect(save)
		cancelBtn.Activated:Connect(closeDialog)
		overlay.Activated:Connect(closeDialog)
		removeBtn.Activated:Connect(function()
			removePicture()
			closeDialog()
		end)
		input.FocusLost:Connect(function(enterPressed)
			if enterPressed and overlay.Visible then
				save()
			end
		end)

		-- double-click on the Account icon opens the dialog
		local tileStroke = accTile:FindFirstChildOfClass("UIStroke")
		local hit = new("TextButton", {
			Name = "PictureHit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 5,
		}, accTile)
		local lastClick = 0
		hit.Activated:Connect(function()
			local now = os.clock()
			if now - lastClick <= DOUBLE_CLICK then
				lastClick = 0
				openDialog()
			else
				lastClick = now
			end
		end)
		hit.MouseEnter:Connect(function()
			if tileStroke then
				tileStroke.Color = ACCENT
			end
		end)
		hit.MouseLeave:Connect(function()
			if tileStroke then
				tileStroke.Color = T.BORDER
			end
		end)
	end

	return {
		Root = root,
		Unload = function()
			alive = false
			pcall(function()
				root:Destroy()
			end)
		end,
	}
end

return HomeTab
