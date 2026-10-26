-- Strict, minimal emulation of the WoW client API for testing AfkDelight outside the game.
-- Widget methods and event names come from Blizzard's generated API documentation (only names
-- present in BOTH the live 12.1.5 and forever 1.60.1 clients are accepted), so calling a method
-- or registering an event that doesn't exist in the real clients fails the tests.

local widgetAPI, apiLists, flavor = ...

-- Lua 5.1's math.random wraps the C library's rand(), which gives different numbers on Windows and Linux.
-- A small Park-Miller generator (exact in doubles) makes every run identical, locally and on GitHub Actions.
do
	local MODULUS = 2147483647
	local state = 42
	function math.randomseed(seed)
		state = math.floor(seed) % (MODULUS - 1) + 1
	end
	function math.random(low, high)
		state = (state * 16807) % MODULUS
		local value = state / MODULUS
		if low == nil then
			return value
		elseif high == nil then
			low, high = 1, low
		end
		assert(low <= high, "bad argument to 'random' (interval is empty)")
		return low + math.floor(value * (high - low + 1))
	end
end

local H = {
	flavor = flavor,
	printed = {},
	time = 1000,
	timers = {},
	registry = {},
	opened = {},
	flashCount = 0,
	moveViewStart = 0,
	moveViewStop = 0,
	animations = {},
	lineUpdates = 0,
	rotations = 0,
}

local S = {
	afk = false, afkValue = nil, lockdown = false, combat = false, casting = nil, channeling = nil,
	instance = false, petBattle = false, level = 80, maxLevel = 80, xp = 0, xpMax = 0, rested = nil,
	resting = true, money = 1234567, titleID = 0, titleName = " the Insane", bgStatus = "none",
	showSurname = false, name = "Frostanon", surname = nil, galaxyLoads = true, hasAnimation = true,
	guild = true, onModelLoaded = true, shift = false, faction = "Alliance", flyerLoads = true,
}
H.S = S

-- Flying animations per creature display, as found in WoW Forever's model files:
-- Onyxia's high-detail model only has FlyRun/FlyWalk/FlyStand, the classic models have Fly.
function H.DefaultFlyers()
	local function Set(...)
		local set = {}
		for i = 1, select("#", ...) do set[select(i, ...)] = true end
		return set
	end
	return {
		[8570] = Set(229, 233, 234), -- Onyxia
		[1149] = Set(135), -- gryphon
		[295] = Set(135), -- wind rider
		[3212] = Set(135, 193, 229, 234), -- white hippogryph
		[2717] = Set(135, 193), -- green dragon
		[1267] = Set(135, 193), -- faerie dragon
	}
end
S.flyers = H.DefaultFlyers()

-- Secret value sentinel: any arithmetic, concatenation, comparison or indexing raises an error.
local SECRET = newproxy(true)
do
	local mt = getmetatable(SECRET)
	local function boom() error("attempted to operate on a secret value", 2) end
	for _, key in ipairs({ "__index", "__newindex", "__concat", "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__lt", "__le", "__len", "__call" }) do
		mt[key] = boom
	end
	mt.__tostring = function() return "<secret>" end
end
H.SECRET = SECRET
function issecretvalue(value)
	return rawequal(value, SECRET)
end

local function ToSet(...)
	local result = {}
	for i = 1, select("#", ...) do
		local list = select(i, ...)
		assert(list, "missing API list #" .. i)
		for _, name in ipairs(list) do
			result[name] = true
		end
	end
	return result
end

local W = widgetAPI
local FSO, OBJ, SR, SRR, AO = W.SimpleFrameScriptObjectAPI, W.SimpleObjectAPI, W.SimpleScriptRegionAPI, W.SimpleScriptRegionResizingAPI, W.SimpleAnimatableObjectAPI
local METHODS = {
	Frame = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleFrameAPI),
	Button = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleFrameAPI, W.SimpleButtonAPI),
	PlayerModel = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleFrameAPI, W.SimpleModelAPI, W.FrameAPICharacterModelBase),
	ScrollingMessageFrame = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleFrameAPI, apiLists.smf),
	Texture = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleRegionAPI, W.SimpleTextureBaseAPI, W.SimpleTextureAPI),
	MaskTexture = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleRegionAPI, W.SimpleTextureBaseAPI, W.SimpleMaskTextureAPI),
	Line = ToSet(FSO, OBJ, SR, AO, W.SimpleRegionAPI, W.SimpleTextureBaseAPI, W.SimpleLineAPI),
	FontString = ToSet(FSO, OBJ, SR, SRR, AO, W.SimpleRegionAPI, W.SimpleFontStringAPI),
	AnimationGroup = ToSet(FSO, OBJ, W.SimpleAnimGroupAPI),
	Alpha = ToSet(FSO, OBJ, W.SimpleAnimAPI, W.SimpleAnimAlphaAPI),
	Font = ToSet(FSO, W.SimpleFontAPI),
	GameTooltip = ToSet({ "SetOwner", "SetText", "AddLine", "Show", "Hide", "IsShown" }),
}

local FRAME_SCRIPTS = { "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnKeyDown", "OnKeyUp", "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnEnter", "OnLeave", "OnSizeChanged", "OnLoad" }
local SCRIPTS = {
	Frame = ToSet(FRAME_SCRIPTS),
	Button = ToSet(FRAME_SCRIPTS, { "OnClick", "PreClick", "PostClick", "OnDoubleClick" }),
	PlayerModel = ToSet(FRAME_SCRIPTS, { "OnModelLoaded", "OnAnimFinished", "OnAnimStarted" }),
	ScrollingMessageFrame = ToSet(FRAME_SCRIPTS, { "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" }),
	AnimationGroup = ToSet({ "OnPlay", "OnFinished", "OnStop", "OnLoop", "OnPause", "OnUpdate" }),
	GameTooltip = ToSet(FRAME_SCRIPTS),
}

local POINTS = ToSet({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })
local LAYERS = ToSet({ "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT" })
local STRATA = ToSet({ "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" })
local validEvents = ToSet(apiLists.events)

local objects = {}
local Impl = {}

local function New(objectType, name, parent)
	assert(METHODS[objectType], "unsupported object type " .. tostring(objectType))
	local obj = {
		__type = objectType, __name = name, __parent = parent, __shown = true, __alpha = 1,
		__scripts = {}, __children = {}, __level = parent and (parent.__level or 0) + 1 or 0,
	}
	if parent and parent.__children then
		table.insert(parent.__children, obj)
	end
	setmetatable(obj, {
		__index = function(_, key)
			if type(key) ~= "string" or not METHODS[objectType][key] then
				return nil
			end
			return Impl[key] or function() end
		end,
	})
	objects[#objects + 1] = obj
	if name then
		_G[name] = obj
	end
	return obj
end
H.New = New

local function IsVisible(obj)
	while obj do
		if not obj.__shown then
			return false
		end
		obj = obj.__parent
	end
	return true
end

local function CollectShown(obj, out)
	if obj.__shown then
		out[#out + 1] = obj
		for _, child in ipairs(obj.__children) do
			CollectShown(child, out)
		end
	end
	return out
end

local function RunScript(obj, script, ...)
	local handler = obj.__scripts[script]
	if handler then
		handler(obj, ...)
	end
end
H.RunScript = RunScript

local function IsNumber(value)
	return type(value) == "number" and value == value
end

-- Visibility -----------------------------------------------------------
function Impl.Show(self)
	if self.__shown then return end
	self.__shown = true
	if IsVisible(self) then
		for _, obj in ipairs(CollectShown(self, {})) do RunScript(obj, "OnShow") end
	end
end
function Impl.Hide(self)
	if not self.__shown then return end
	local before = IsVisible(self) and CollectShown(self, {}) or {}
	self.__shown = false
	for _, obj in ipairs(before) do RunScript(obj, "OnHide") end
end
function Impl.SetShown(self, shown)
	assert(type(shown) == "boolean", "SetShown needs a boolean, got " .. type(shown))
	if shown then Impl.Show(self) else Impl.Hide(self) end
end
function Impl.IsShown(self) return self.__shown end
function Impl.IsVisible(self) return IsVisible(self) end
function Impl.SetAlpha(self, alpha)
	assert(IsNumber(alpha) and alpha >= 0 and alpha <= 1.000001, "SetAlpha out of range: " .. tostring(alpha))
	self.__alpha = alpha
end
function Impl.GetAlpha(self) return self.__alpha end
function Impl.SetIgnoreParentAlpha(self, ignore) assert(type(ignore) == "boolean"); self.__ignoreParentAlpha = ignore end

-- Scripts ---------------------------------------------------------------
local function CheckScript(self, script)
	assert(SCRIPTS[self.__type] and SCRIPTS[self.__type][script], self.__type .. " has no script handler " .. tostring(script))
end
function Impl.SetScript(self, script, handler)
	CheckScript(self, script)
	assert(handler == nil or type(handler) == "function", "bad script handler")
	self.__scripts[script] = handler
end
function Impl.GetScript(self, script) CheckScript(self, script); return self.__scripts[script] end
function Impl.HookScript(self, script, handler)
	CheckScript(self, script)
	assert(type(handler) == "function", "bad hook")
	local previous = self.__scripts[script]
	self.__scripts[script] = previous and function(...) previous(...); handler(...) end or handler
end
function Impl.HasScript(self, script) return (SCRIPTS[self.__type] and SCRIPTS[self.__type][script]) and true or false end

-- Geometry --------------------------------------------------------------
function Impl.SetPoint(self, point, a, b, c, d)
	assert(POINTS[point], "bad anchor point " .. tostring(point))
	local relative, relativePoint, x, y
	if type(a) == "number" then
		x, y = a, b
	else
		relative = a
		if type(b) == "string" then relativePoint, x, y = b, c, d else x, y = b, c end
	end
	assert(relative == nil or type(relative) == "table", "bad relative region")
	assert(relativePoint == nil or POINTS[relativePoint], "bad relative point " .. tostring(relativePoint))
	assert(x == nil or IsNumber(x), "bad x offset " .. tostring(x))
	assert(y == nil or IsNumber(y), "bad y offset " .. tostring(y))
	self.__points = self.__points or {}
	self.__points[#self.__points + 1] = { point, relative, relativePoint, x, y }
end
function Impl.ClearAllPoints(self) self.__points = {} end
function Impl.SetAllPoints(self, relative) self.__allPoints = relative or self.__parent or true end
function Impl.SetSize(self, width, height)
	assert(IsNumber(width) and IsNumber(height), "bad size")
	self.__width, self.__height = width, height
end
function Impl.SetWidth(self, width) assert(IsNumber(width), "bad width"); self.__width = width end
function Impl.SetHeight(self, height) assert(IsNumber(height), "bad height"); self.__height = height end
function Impl.GetWidth(self)
	if self.__width then return self.__width end
	if type(self.__allPoints) == "table" then return Impl.GetWidth(self.__allPoints) end
	return 0
end
function Impl.GetHeight(self)
	if self.__height then return self.__height end
	if type(self.__allPoints) == "table" then return Impl.GetHeight(self.__allPoints) end
	return 0
end
function Impl.GetFrameLevel(self) return self.__level end
function Impl.SetFrameLevel(self, level) assert(IsNumber(level), "bad frame level"); self.__level = level end
function Impl.SetFrameStrata(self, strata) assert(STRATA[strata], "bad strata " .. tostring(strata)); self.__strata = strata end

-- Input -----------------------------------------------------------------
function Impl.EnableKeyboard(self, enable) assert(type(enable) == "boolean"); self.__keyboard = enable end
function Impl.EnableMouse(self, enable) assert(type(enable) == "boolean"); self.__mouse = enable end
function Impl.EnableMouseWheel(self, enable) assert(type(enable) == "boolean"); self.__wheel = enable end
function Impl.SetPropagateKeyboardInput(self, propagate)
	assert(type(propagate) == "boolean")
	if S.combat then error("ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput() in combat") end
	self.__propagate = propagate
end

-- Events ----------------------------------------------------------------
function Impl.RegisterEvent(self, event)
	if not validEvents[event] then
		error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
	end
	H.registry[event] = H.registry[event] or {}
	H.registry[event][self] = true
end
function Impl.UnregisterEvent(self, event)
	if H.registry[event] then H.registry[event][self] = nil end
end
function H.Fire(event, ...)
	assert(validEvents[event], "test fired unknown event " .. tostring(event))
	local list = {}
	for frame in pairs(H.registry[event] or {}) do list[#list + 1] = frame end
	for _, frame in ipairs(list) do RunScript(frame, "OnEvent", event, ...) end
	return #list
end
function H.IsRegistered(event)
	return next(H.registry[event] or {}) ~= nil
end

-- Children --------------------------------------------------------------
local function CheckLayer(layer, subLevel)
	assert(layer == nil or LAYERS[layer], "bad draw layer " .. tostring(layer))
	assert(subLevel == nil or (IsNumber(subLevel) and subLevel >= -8 and subLevel <= 7), "bad draw sublevel " .. tostring(subLevel))
end
function Impl.CreateTexture(self, name, layer, template, subLevel) CheckLayer(layer, subLevel); return New("Texture", name, self) end
function Impl.CreateMaskTexture(self, name, layer, template, subLevel) CheckLayer(layer, subLevel); return New("MaskTexture", name, self) end
function Impl.AddMaskTexture(self, mask)
	assert(type(mask) == "table" and mask.__type == "MaskTexture", "AddMaskTexture needs a MaskTexture")
	self.__masks = self.__masks or {}
	table.insert(self.__masks, mask)
end
function Impl.CreateFontString(self, name, layer, template) CheckLayer(layer); return New("FontString", name, self) end
function Impl.CreateLine(self, name, layer, template, subLevel) CheckLayer(layer, subLevel); return New("Line", name, self) end
function Impl.CreateAnimationGroup(self)
	local group = New("AnimationGroup")
	group.__animations = {}
	return group
end
function Impl.CreateAnimation(self, animationType)
	assert(animationType == "Alpha", "mock only knows Alpha animations, got " .. tostring(animationType))
	local animation = New("Alpha")
	table.insert(self.__animations, animation)
	return animation
end
function Impl.SetLooping(self, mode) assert(mode == "NONE" or mode == "REPEAT" or mode == "BOUNCE", "bad looping") end
function Impl.Play(self) self.__playing = true end
function Impl.Stop(self) self.__playing = false end
function Impl.IsPlaying(self) return self.__playing == true end
function Impl.SetFromAlpha(self, alpha) assert(IsNumber(alpha) and alpha >= 0 and alpha <= 1, "bad from alpha") end
function Impl.SetToAlpha(self, alpha) assert(IsNumber(alpha) and alpha >= 0 and alpha <= 1, "bad to alpha") end
function Impl.SetDuration(self, duration) assert(IsNumber(duration) and duration >= 0, "bad duration") end
function Impl.SetStartDelay(self, delay) assert(IsNumber(delay) and delay >= 0, "bad delay") end
function Impl.SetSmoothing(self, smoothing) assert(smoothing == "NONE" or smoothing == "IN" or smoothing == "OUT" or smoothing == "IN_OUT", "bad smoothing") end

-- Text ------------------------------------------------------------------
function Impl.SetFont(self, path, size, flags)
	assert(type(path) == "string" and IsNumber(size) and size > 0, "bad SetFont arguments")
	assert(flags == nil or type(flags) == "string", "bad font flags")
	self.__font = { path, size, flags }
	return true
end
function Impl.GetFont(self) if self.__font then return self.__font[1], self.__font[2], self.__font[3] end end
function Impl.SetFontObject(self, font) assert(type(font) == "table", "bad font object") end
function Impl.SetText(self, text)
	assert(text == nil or type(text) == "string" or type(text) == "number", "SetText with " .. type(text))
	self.__text = text
end
function Impl.GetText(self) return self.__text end
function Impl.SetTextColor(self, r, g, b) assert(IsNumber(r) and IsNumber(g) and IsNumber(b), "bad text color") end
function Impl.SetShadowOffset(self, x, y) assert(IsNumber(x) and IsNumber(y), "bad shadow offset") end
function Impl.SetShadowColor(self, r, g, b, a) assert(IsNumber(r) and IsNumber(g) and IsNumber(b), "bad shadow color") end
function Impl.SetJustifyH(self, justify) assert(justify == "LEFT" or justify == "CENTER" or justify == "RIGHT", "bad justify") end
function Impl.GetStringHeight(self) return self.__font and self.__font[2] or 0 end
function Impl.GetTextWidth(self) return #(self.__text or "") * 7 end
function Impl.SetIndentedWordWrap(self, indent) assert(type(indent) == "boolean") end
function Impl.SetMaxLines(self, count) assert(IsNumber(count) and count > 0); self.__maxLines = count end
function Impl.SetFading(self, fading) assert(type(fading) == "boolean") end
function Impl.SetInsertMode(self, mode)
	assert(mode == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP or mode == SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM, "bad insert mode " .. tostring(mode))
	self.__insertMode = mode
end
-- Like the real history buffer: AddMessage pushes to the front (line 1 = newest),
-- BackFillMessage appends at the back and is refused once the buffer is full.
local function CheckMessage(text, r, g, b)
	assert(type(text) == "string", "messages need a string")
	assert(IsNumber(r) and IsNumber(g) and IsNumber(b), "messages need a color")
end
function Impl.AddMessage(self, text, r, g, b)
	CheckMessage(text, r, g, b)
	self.__lines = self.__lines or {}
	table.insert(self.__lines, 1, text)
	if #self.__lines > (self.__maxLines or 120) then table.remove(self.__lines) end
end
function Impl.BackFillMessage(self, text, r, g, b)
	CheckMessage(text, r, g, b)
	self.__lines = self.__lines or {}
	if #self.__lines >= (self.__maxLines or 120) then
		H.droppedMessages = (H.droppedMessages or 0) + 1
		return
	end
	table.insert(self.__lines, text)
end
function Impl.Clear(self) self.__lines, self.__offset = {}, 0 end
function Impl.GetNumMessages(self) return #(self.__lines or {}) end
function Impl.GetNumVisibleLines(self) return 12 end
function Impl.GetScrollOffset(self) return self.__offset or 0 end
function Impl.SetScrollOffset(self, offset)
	assert(IsNumber(offset), "bad scroll offset")
	self.__offset = math.max(0, math.min(offset, math.max(#(self.__lines or {}) - 1, 0)))
	self.__scrolls = self.__scrolls or {}
	table.insert(self.__scrolls, "SetScrollOffset:" .. offset)
end

-- Textures and lines ------------------------------------------------------
function Impl.SetColorTexture(self, r, g, b, a)
	assert(IsNumber(r) and IsNumber(g) and IsNumber(b), "bad color texture")
	assert(a == nil or (IsNumber(a) and a >= 0 and a <= 1), "bad color texture alpha " .. tostring(a))
	self.__color = { r, g, b, a or 1 }
end
function Impl.SetGradient(self, orientation, minColor, maxColor)
	assert(orientation == "HORIZONTAL" or orientation == "VERTICAL", "bad gradient orientation")
	assert(type(minColor) == "table" and minColor.GetRGBA and type(maxColor) == "table" and maxColor.GetRGBA, "SetGradient needs ColorMixin colors")
end
local WRAP_MODES = ToSet({ "CLAMP", "REPEAT", "CLAMPTOBLACK", "CLAMPTOBLACKADDITIVE", "CLAMPTOWHITE", "MIRROR" })
function Impl.SetTexture(self, texture, wrapH, wrapV)
	assert(type(texture) == "string" or type(texture) == "number", "bad texture")
	assert(wrapH == nil or WRAP_MODES[wrapH], "bad horizontal wrap mode " .. tostring(wrapH))
	assert(wrapV == nil or WRAP_MODES[wrapV], "bad vertical wrap mode " .. tostring(wrapV))
	self.__file, self.__wrap = texture, { wrapH, wrapV }
end
function Impl.SetDesaturated(self, desaturated) assert(type(desaturated) == "boolean", "bad desaturation"); self.__desaturated = desaturated end
function Impl.SetTexCoord(self, left, right, top, bottom)
	assert(IsNumber(left) and IsNumber(right) and IsNumber(top) and IsNumber(bottom), "bad texcoords")
	-- Coordinates past 1 only make sense for a texture that repeats.
	local repeats = self.__wrap and self.__wrap[1] == "REPEAT" and self.__wrap[2] == "REPEAT"
	assert(left >= 0 and top >= 0 and (repeats or (right <= 1 and bottom <= 1)), "texcoords out of range")
	self.__texCoord = { left, right, top, bottom }
end
function Impl.GetStringWidth(self) return #(self.__text or "") * 7 end
function Impl.SetBlendMode(self, mode) assert(ToSet({ "DISABLE", "BLEND", "ALPHAKEY", "ADD", "MOD" })[mode], "bad blend mode"); self.__blend = mode end
function Impl.SetVertexColor(self, r, g, b) assert(IsNumber(r) and IsNumber(g) and IsNumber(b), "bad vertex color"); self.__vertexColor = { r, g, b } end
function Impl.SetAtlas(self, atlas) assert(C_Texture.GetAtlasInfo(atlas), "unknown atlas " .. tostring(atlas)) end
function Impl.SetStartPoint(self, point, relative, x, y)
	assert(POINTS[point] and type(relative) == "table" and IsNumber(x) and IsNumber(y), "bad line start point")
	H.lineUpdates = H.lineUpdates + 1
end
function Impl.SetEndPoint(self, point, relative, x, y)
	assert(POINTS[point] and type(relative) == "table" and IsNumber(x) and IsNumber(y), "bad line end point")
end
function Impl.SetThickness(self, thickness) assert(IsNumber(thickness), "bad thickness") end

-- Models ------------------------------------------------------------------
local function ScheduleModelLoad(model)
	local source = model.__source
	H.After(0.2, function()
		if model.__source ~= source or source == nil then return end
		local fileID
		if source.unit then
			fileID = 4207724
		elseif (source.display == 67918 or source.file == 1305790) and S.galaxyLoads then
			fileID = 1305790
		elseif source.display and S.flyers[source.display] and S.flyerLoads then
			fileID = 100000 + source.display
		end
		if fileID then
			model.__loaded = fileID
			if S.onModelLoaded then RunScript(model, "OnModelLoaded") end
		end
	end)
end
function Impl.SetUnit(self, unit)
	assert(unit == "player", "unexpected unit " .. tostring(unit))
	self.__unit, self.__display, self.__loaded = unit, nil, nil
	self.__source = { unit = unit }
	ScheduleModelLoad(self)
	return true
end
function Impl.SetDisplayInfo(self, displayID)
	assert(IsNumber(displayID), "bad display ID")
	self.__display, self.__unit, self.__loaded = displayID, nil, nil
	self.__source = { display = displayID }
	ScheduleModelLoad(self)
end
function Impl.SetModel(self, file)
	assert(IsNumber(file) or type(file) == "string", "bad model file")
	self.__file, self.__loaded = file, nil
	self.__source = { file = file }
	ScheduleModelLoad(self)
end
function Impl.ClearModel(self)
	self.__unit, self.__display, self.__file, self.__loaded, self.__source = nil, nil, nil, nil, nil
end
function Impl.GetModelFileID(self) return self.__loaded end
function Impl.SetCamDistanceScale(self, scale) assert(IsNumber(scale), "bad camera distance") end
function Impl.SetRotation(self, radians, animate)
	assert(IsNumber(radians), "bad rotation")
	assert(animate == nil or type(animate) == "boolean", "bad rotation animate flag")
	self.__rotation = radians
	H.rotations = H.rotations + 1
end
function Impl.SetAnimation(self, animation)
	assert(IsNumber(animation), "bad animation")
	self.__animation = animation
	-- H.animations follows the character; creature models keep their own list.
	if self.__unit then
		H.animations[#H.animations + 1] = animation
	else
		H.flyerAnimations = H.flyerAnimations or {}
		H.flyerAnimations[#H.flyerAnimations + 1] = animation
	end
end
function Impl.HasAnimation(self, animation)
	assert(IsNumber(animation))
	local flyer = self.__display and S.flyers[self.__display]
	if flyer then
		return flyer[animation] == true
	end
	return S.hasAnimation
end
function Impl.SetLight(self, enabled, light)
	assert(type(enabled) == "boolean" and type(light) == "table", "bad SetLight arguments")
	assert(type(light.point) == "table" and light.point.GetXYZ, "ModelLight.point needs a Vector3D")
	assert(IsNumber(light.ambientIntensity) and IsNumber(light.diffuseIntensity), "ModelLight intensities")
	assert(light.ambientColor == nil or light.ambientColor.GetRGB, "ModelLight.ambientColor needs a color")
	self.__light = light
	H.lights = (H.lights or 0) + 1
end
local function RecordScroll(method)
	return function(self) self.__scrolls = self.__scrolls or {}; table.insert(self.__scrolls, method) end
end
Impl.ScrollUp, Impl.ScrollDown = RecordScroll("ScrollUp"), RecordScroll("ScrollDown")
Impl.PageUp, Impl.PageDown = RecordScroll("PageUp"), RecordScroll("PageDown")
Impl.ScrollToTop, Impl.ScrollToBottom = RecordScroll("ScrollToTop"), RecordScroll("ScrollToBottom")

-- Tooltip ---------------------------------------------------------------
function Impl.SetOwner(self, owner, anchor) assert(type(owner) == "table" and type(anchor) == "string"); self.__owner = owner end
function Impl.AddLine(self, text) assert(type(text) == "string", "bad tooltip line") end

-- Timers ----------------------------------------------------------------
local function NewTimer(seconds, callback)
	assert(IsNumber(seconds) and seconds >= 0 and type(callback) == "function", "bad timer")
	local timer = { due = H.time + seconds, callback = callback }
	function timer:Cancel() self.cancelled = true end
	function timer:IsCancelled() return self.cancelled == true end
	table.insert(H.timers, timer)
	return timer
end
function H.After(seconds, callback) NewTimer(seconds, callback) end
C_Timer = {
	NewTimer = NewTimer,
	After = function(seconds, callback) NewTimer(seconds, callback) end,
}
function GetTime() return H.time end

-- Steps of 1/16 s keep the clock exact in binary floating point.
function H.Advance(seconds, step)
	step = step or 0.0625
	local target = H.time + seconds
	while H.time < target - 1e-9 do
		local dt = math.min(step, target - H.time)
		H.time = H.time + dt
		local due = {}
		for i = #H.timers, 1, -1 do
			local timer = H.timers[i]
			if timer.cancelled then
				table.remove(H.timers, i)
			elseif timer.due <= H.time + 1e-9 then
				table.remove(H.timers, i)
				due[#due + 1] = timer
			end
		end
		table.sort(due, function(a, b) return a.due < b.due end)
		for _, timer in ipairs(due) do
			if not timer.cancelled then timer.callback(timer) end
		end
		for i = 1, #objects do
			local obj = objects[i]
			if obj.__scripts.OnUpdate and IsVisible(obj) then
				obj.__scripts.OnUpdate(obj, dt)
			end
		end
	end
end

function H.Key(key)
	local frame = AfkDelightFrame
	assert(IsVisible(frame) and frame.__keyboard, "the AFK screen doesn't receive keyboard input")
	RunScript(frame, "OnKeyDown", key)
	return frame.__propagate
end

function H.Click(frame)
	frame = frame or AfkDelightFrame
	assert(IsVisible(frame) and frame.__mouse, "frame doesn't receive mouse input")
	RunScript(frame, "OnMouseDown", "LeftButton")
end

-- Frames ------------------------------------------------------------------
UIParent = New("Frame", "UIParent")
UIParent:SetSize(1600, 900)
CinematicFrame = New("Frame", "CinematicFrame", UIParent)
CinematicFrame:Hide()
MovieFrame = New("Frame", "MovieFrame", UIParent)
MovieFrame:Hide()
GameTooltip = New("GameTooltip", "GameTooltip", UIParent)
GameTooltip:Hide()
ChatFontNormal = New("Font", "ChatFontNormal")

function CreateFrame(frameType, name, parent, template)
	assert(frameType == "Frame" or frameType == "Button" or frameType == "PlayerModel" or frameType == "ScrollingMessageFrame", "unexpected frame type " .. tostring(frameType))
	assert(template == nil or (template == "UIPanelButtonTemplate" and frameType == "Button"), "unexpected template " .. tostring(template))
	assert(parent == nil or type(parent) == "table", "bad parent")
	return New(frameType, name, parent)
end

-- Settings API --------------------------------------------------------------
H.settings = { list = {}, byVariable = {}, initializers = {} }

local SettingMixin = {}
SettingMixin.__index = SettingMixin
function SettingMixin:GetValue() return self.tbl[self.key] end
function SettingMixin:SetValue(value)
	if type(value) ~= self.varType then
		error(string.format("SetValue '%s' requires '%s' type, not '%s' type.", self.name, self.varType, type(value)))
	end
	self.tbl[self.key] = value
	for _, callback in ipairs(self.callbacks) do callback(self, value) end
end
function SettingMixin:SetValueChangedCallback(callback) table.insert(self.callbacks, callback) end
function SettingMixin:GetVariable() return self.variable end
function SettingMixin:GetVariableType() return self.varType end
function SettingMixin:GetDefaultValue() return self.default end

local Initializer = {}
Initializer.__index = Initializer
function Initializer:SetParentInitializer(parent, predicate)
	assert(type(parent) == "table" and parent ~= self, "bad parent initializer")
	assert(predicate == nil or type(predicate) == "function", "bad modify predicate")
	self.parent, self.predicate = parent, predicate
end
function Initializer:GetSetting() return self.setting end

local function AddInitializer(kind, setting, options, tooltip)
	local initializer = setmetatable({ kind = kind, setting = setting, options = options, tooltip = tooltip }, Initializer)
	table.insert(H.settings.layout.initializers, initializer)
	return initializer
end

Settings = {
	RegisterVerticalLayoutCategory = function(name)
		assert(type(name) == "string" and not H.settings.category, "bad or duplicate category")
		local category = { name = name, ID = 9001 }
		function category:GetID() return self.ID end
		local layout = { initializers = {} }
		function layout:AddInitializer(initializer) assert(type(initializer) == "table"); table.insert(self.initializers, initializer) end
		H.settings.category, H.settings.layout = category, layout
		return category, layout
	end,
	RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
		assert(category == H.settings.category, "unknown category")
		assert(type(variable) == "string" and not H.settings.byVariable[variable], "bad or duplicate variable " .. tostring(variable))
		assert(type(tbl) == "table", "'variableTbl' argument must be a table.")
		assert(type(varType) == "string" and type(name) == "string", "bad setting type or name")
		assert(type(default) == varType, "default type mismatch for " .. variable)
		if tbl[key] == nil then tbl[key] = default end
		local setting = setmetatable({ variable = variable, key = key, tbl = tbl, varType = varType, name = name, default = default, callbacks = {} }, SettingMixin)
		H.settings.byVariable[variable] = setting
		table.insert(H.settings.list, setting)
		return setting
	end,
	CreateCheckbox = function(category, setting, tooltip)
		assert(setting.varType == "boolean", "checkbox needs a boolean setting")
		return AddInitializer("checkbox", setting, nil, tooltip)
	end,
	CreateSlider = function(category, setting, options, tooltip)
		assert(setting.varType == "number" and options, "slider needs a number setting and options")
		return AddInitializer("slider", setting, options, tooltip)
	end,
	CreateDropdown = function(category, setting, options, tooltip)
		assert(options ~= nil, "dropdown needs options")
		return AddInitializer("dropdown", setting, options, tooltip)
	end,
	CreateSliderOptions = function(minValue, maxValue, rate)
		local options = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate, formatters = {} }
		function options:SetLabelFormatter(labelType, formatter) self.formatters[labelType] = formatter end
		return options
	end,
	CreateControlTextContainer = function()
		local container = { data = {} }
		function container:Add(value, label, tooltip) table.insert(self.data, { value = value, label = label, text = label, tooltip = tooltip }) end
		function container:GetData() return self.data end
		return container
	end,
	RegisterAddOnCategory = function(category) H.settings.registered = category end,
	OpenToCategory = function(categoryID) table.insert(H.opened, categoryID) end,
}
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
function CreateSettingsListSectionHeaderInitializer(name)
	assert(type(name) == "string")
	return setmetatable({ kind = "header", name = name }, Initializer)
end
function CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)
	assert(type(name) == "string" and type(buttonText) == "string" and type(onClick) == "function")
	return setmetatable({ kind = "button", name = name, onClick = onClick }, Initializer)
end

-- Game state API ------------------------------------------------------------
function CreateColor(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a or 1 }
	function color:GetRGBA() return self.r, self.g, self.b, self.a end
	function color:GetRGB() return self.r, self.g, self.b end
	function color:WrapTextInColorCode(text) return string.format("|cff%02x%02x%02x%s|r", self.r * 255, self.g * 255, self.b * 255, text) end
	return color
end
function CreateVector3D(x, y, z)
	assert(IsNumber(x) and IsNumber(y) and IsNumber(z), "bad vector")
	local vector = { x = x, y = y, z = z }
	function vector:GetXYZ() return self.x, self.y, self.z end
	return vector
end
function IsShiftKeyDown() return S.shift end
C_ClassColor = { GetClassColor = function(classFile) assert(type(classFile) == "string"); return CreateColor(0.25, 0.78, 0.92, 1) end }
RAID_CLASS_COLORS = setmetatable({}, { __index = function(_, classFile) return C_ClassColor.GetClassColor(classFile) end })
C_Texture = { GetAtlasInfo = function(atlas) if type(atlas) == "string" and atlas:match("^classicon%-%l+$") then return { width = 64, height = 64 } end end }
C_ChatInfo = { InChatMessagingLockdown = function() return S.lockdown end }
C_PetBattles = { IsInBattle = function() return S.petBattle end }
C_EventUtils = { IsEventValid = function(event) return validEvents[event] == true end }
C_AddOns = { GetAddOnMetadata = function(name, field) assert(name == "AfkDelight"); if field == "Version" then return "1.0.0" end end }
C_PlayerInfo = { ShouldDisplaySurname = function() return S.showSurname end }

function UnitIsAFK(unit) assert(unit == "player"); if S.afkValue ~= nil then return S.afkValue end; return S.afk end
function UnitName(unit) assert(unit == "player"); return S.name, S.surname end
function UnitClass(unit) return "Mage", "MAGE", 8 end
function UnitRace(unit) return "Void Elf", "VoidElf", 29 end
function UnitFactionGroup(unit) assert(unit == "player", "faction of " .. tostring(unit)); return S.faction, S.faction end
function UnitLevel(unit) return S.level end
function UnitXP(unit) return S.xp end
function UnitXPMax(unit) return S.xpMax end
function UnitAffectingCombat(unit) return S.combat end
function UnitCastingInfo(unit) return S.casting end
function UnitChannelInfo(unit) return S.channeling end
function GetMaxLevelForPlayerExpansion() return S.maxLevel end
function GetXPExhaustion() return S.rested end
function IsXPUserDisabled() return false end
function IsResting() return S.resting end
function GetSpecialization() return 3 end
function GetSpecializationInfo(index) assert(index == 3); return 64, "Frost", "", 135846, "DAMAGER", "MAGE" end
function IsInGuild() return S.guild end
function GetGuildInfo(unit) if S.guild then return "Wicked Demise", "Officer", 1, nil end end
function GetAverageItemLevel() return 680.4, 678.9, 679 end
function GetRealZoneText() return "Stormwind City" end
function GetZoneText() return "Stormwind City" end
function GetSubZoneText() return "Trade District" end
function GetMoney() return S.money end
function InCombatLockdown() return S.combat end
function IsInInstance() return S.instance, S.instance and "party" or "none" end
function GetCurrentTitle() return S.titleID end
function GetTitleName(titleID) return S.titleName, true end
function FlashClientIcon() H.flashCount = H.flashCount + 1 end
function Ambiguate(name, context) assert(type(name) == "string" and type(context) == "string"); return (name:gsub("%-.*$", "")) end
function GetPlayerInfoByGUID(guid) assert(type(guid) == "string"); return "Priest", "PRIEST", "Human", "Human", 2, "Bob", "Silvermoon" end
function GetBattlefieldStatus(index) assert(IsNumber(index)); return S.bgStatus end
function GetBindingByKey(key) if key == "PRINTSCREEN" then return "SCREENSHOT" elseif key == "W" then return "MOVEFORWARD" end end
function MoveViewLeftStart(speed) assert(IsNumber(speed)); H.moveViewStart = H.moveViewStart + 1 end
function MoveViewLeftStop() H.moveViewStop = H.moveViewStop + 1 end
function GameTime_GetTime(showAMPM) return "17:05", 17, 5 end
function GameTime_GetLocalTime(wantAMPM) return "17:05", 17, 5 end
function SecondsToTime(seconds) return string.format("%d Min %d Sec", math.floor(seconds / 60), seconds % 60) end
function GetMoneyString(copper) return tostring(copper) .. "c" end
function GetLocale() return "enUS" end
function GetBuildInfo()
	if flavor == "forever" then
		return "1.60.1", "70532", "Oct 22 2026", 16001
	end
	return "12.1.5", "70529", "Oct 22 2026", 120105
end
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CAMELOT = 21
WOW_PROJECT_ID = flavor == "forever" and WOW_PROJECT_CAMELOT or WOW_PROJECT_MAINLINE

if flavor == "forever" then
	function RegionalUniqueNamesEnabled() return true end
	NameUtil = {
		FormatUnitNameForDisplay = function(unit, showSurname)
			local name, surname = UnitName(unit)
			if surname and surname ~= "" and showSurname then return name .. "-" .. surname end
			return name
		end,
		GetUnitFirstName = function(unit) return (UnitName(unit):match("^([^-]+)")) end,
	}
end

CALENDAR_WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
CALENDAR_FULLDATE_MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
FULLDATE_NO_YEAR = "%s, %s %d"
ChatTypeInfo = {}
for _, chatType in ipairs({ "WHISPER", "BN_WHISPER", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }) do
	ChatTypeInfo[chatType] = { r = 0.5, g = 0.6, b = 0.7 }
end
CHAT_WHISPER_GET = "%s whispers: "
SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP = 1
SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM = 2
CHAT_BN_WHISPER_GET = "%s whispers: "
CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: "
CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[Officer]|h %s: "
CHAT_PARTY_GET = "|Hchannel:PARTY|h[Party]|h %s: "
MARKED_AFK_MESSAGE = "You are now AFK: %s"
DEFAULT_AFK_MESSAGE = "Away from Keyboard"
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
CLOSE, LEVEL, STAT_AVERAGE_ITEM_LEVEL, YES, NO, GENERAL, APPEARANCE_LABEL, RESET = "Close", "Level", "Item Level", "Yes", "No", "General", "Appearance", "Reset"

SlashCmdList = {}
date = os.date
function strtrim(text) assert(type(text) == "string", "strtrim needs a string"); return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function geterrorhandler() return function(err) error(err, 0) end end
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(H.printed, table.concat(parts, " "))
end

return H
