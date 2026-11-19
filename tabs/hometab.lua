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
--   [ icon ]  Current session
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

	local function iconClock(h)
		local face = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, h)
		corner(face, 100)
		stroke(face, T.ICON_HOVER, 1.5, 0)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1.5, 4),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
		}, h)
		new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(3.5, 1.5),
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
	-- (title, value, caption) on the right. Returns the value label and the caption label.
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
		return value, cap
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
	local accValue, accCap = infoCard("Account", 0, PAD, 0.5, -(PAD + half), ROW1, iconPerson)
	local appValue, appCap = infoCard("Application", 0.5, half, 0.5, -(PAD + half), ROW1, iconWindow)

	---------------------------------------------------------------------
	-- ROW 2: Current session (full width)
	---------------------------------------------------------------------
	local ROW2 = ROW1 + CARD_H + GAP
	local sesValue, sesCap = infoCard("Current session", 0, PAD, 1, -PAD * 2, ROW2, iconClock)

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
