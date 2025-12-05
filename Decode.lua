local module = {}

local ti = table.insert
local b3ba = bit32.band
local b3ls = bit32.lshift
local b3rs = bit32.rshift
local buru8 = buffer.readu8
local buru16 = buffer.readu16
local buri16 = buffer.readi16
local buru32 = buffer.readu32
local burf32 = buffer.readf32
local burf64 = buffer.readf64
local burs = buffer.readstring
local buco = buffer.copy
local bucr = buffer.create

local V2n = Vector2.new
local V3n = Vector3.new
local BCn = BrickColor.new
local C3n = Color3.new
local C3r = Color3.fromRGB
local CFnew = CFrame.new
local CFe = CFrame.fromEulerAnglesXYZ
local UD2new = UDim2.new

local EncodingService = game:GetService("EncodingService")
local Comp = require(script.Parent.Compression)

local compressModeTargets = {
	"Deflate",
	"Zlib",
	"ZlibNative"
}

--local enumMap: {[Enum]: number} = {} --> number -> enum
local enumMap = nil
local enumMapFallback = {}
for i,v in Enum:GetEnums() do
	enumMapFallback[i] = v
end

module.TryLoadEnumMap = function()
	if enumMap == nil then
		local enumStrMap = script:FindFirstChild("EnumStringMap")
		if not enumStrMap then return false end

		enumMap = {}
		for _, str in enumStrMap.Value:split("/") do
			local contents = str:split("-")
			local isValid = pcall(function() assert(Enum[contents[2]]) end)

			enumMap[tonumber(contents[1])] = (isValid and Enum[contents[2]] or "SERVER_ONLY_ENUM")
		end
	else
		return true
	end
end

module.Init = function()
	if game:GetService("RunService"):IsServer() then
		--> we also store a stringvalue for the client to use, because the client and server have different enums
		local strMap: string = "" 
		enumMap = {}
		for i, v in Enum:GetEnums() do
			strMap ..= `{i}-{v}/`
			enumMap[i] = v
		end
		strMap = strMap:sub(1, #strMap - 1) -- remove last /

		if script:FindFirstChild("EnumStringMap") then return end
		local obj = Instance.new("StringValue")
		obj.Value = strMap
		obj.Name = "EnumStringMap"

		obj.Parent = script
		return
	end
	
	module.TryLoadEnumMap()
end

module.DecodeVarLength = function(input: buffer, offset: number)
	if not offset then offset = 0 end
	local data,shift = 0,1
	local loop = 0
	while true do
		local x = buru8(input, loop+offset)
		data += b3ba(x, 0x7F) * shift
		loop += 1
		if b3ba(x, 0x80) ~= 0 then
			break
		end
		shift = b3ls(shift, 7)
		data += shift
	end
	return data,loop
end

local functions = {
	function(input: buffer, offset: number) -- String
		local len,amt = module.DecodeVarLength(input,offset)
		offset+=amt
		local mode = buru8(input, offset)
		offset+=1
		
		local str
		if mode > 0 then
			if mode == 3 then
				local strBuf = bucr(len)
				buco(strBuf, 0, input, offset, len)
				str = buffer.tostring(EncodingService:DecompressBuffer(strBuf, Enum.CompressionAlgorithm.Zstd))
			else
				str = burs(input, offset, len)
				str = Comp[compressModeTargets[mode]].Decompress(str)
			end
		else
			str = burs(input, offset, len)
		end
		offset+=len
		return str,offset
	end,
	function(input: buffer, offset: number) -- Boolean5
		local byte = buru8(input, offset)
		offset+=1
		local amt = b3rs(b3ba(byte, 224), 5) + 1
		local bools = {}
		for i = 1, amt do
			local bool = b3ba(b3rs(byte, 5-i),1)
			ti(bools,bool==1)
		end
		if amt == 1 then bools = unpack(bools) end
		return bools,offset
	end,
	function(input: buffer, offset: number) -- UInt8
		local byte = buru8(input, offset)
		offset+=1
		return byte,offset
	end,
	function(input: buffer, offset: number) -- UInt16
		local val = buru16(input, offset)
		offset+=2
		return val,offset
	end,
	function(input: buffer, offset: number) -- UInt32
		local val = buru32(input, offset)
		offset+=4
		return val,offset
	end,
	function(input: buffer, offset: number) -- float
		local val = burf32(input, offset)
		offset+=4
		return val,offset
	end,
	function(input: buffer, offset: number) -- double
		local val = burf64(input, offset)
		offset+=8
		return val,offset
	end,
	function(input: buffer, offset: number) -- Vector2
		local comp = buru8(input, offset)
		local func,mult
		if comp == 1 then
			func = burf32
			mult = 1
		else
			func = burf64
			mult = 2
		end
		offset+=1
		local X = func(input, offset)
		local Y = func(input, offset+4*mult)
		offset+=8*mult
		return V2n(X,Y),offset
	end,
	function(input: buffer, offset: number) -- Vector3
		local comp = buru8(input, offset)
		local func,mult
		if comp == 1 then
			func = burf32
			mult = 1
		else
			func = burf64
			mult = 2
		end
		offset+=1
		local X = func(input, offset)
		local Y = func(input, offset+4*mult)
		local Z = func(input, offset+8*mult)
		offset+=12*mult
		return V3n(X,Y,Z),offset
	end,

	function(input: buffer, offset: number) -- CFrame
		--> roblox always stores cframes as 3 f32s for position and 9 i16s for rotation matrices
		--> since the rotation vectors are always perpendicular we can only save two
		--> and reconstruct the other when decoding from cross product

		local x, y, z = burf32(input, offset), burf32(input, offset + 4), burf32(input, offset + 8)

		local r00, r01, r02 = 
			buri16(input, offset + 12) / 32767, 
		buri16(input, offset + 14) / 32767, 
		buri16(input, offset + 16) / 32767

		local r10, r11, r12 = 
			buri16(input, offset + 18) / 32767,
		buri16(input, offset + 20) / 32767, 
		buri16(input, offset + 22) / 32767

		offset += 24

		local r2 = Vector3.new(r00, r01, r02):Cross(Vector3.new(r10, r11, r12))

		return CFnew(x, y, z, r00, r01, r02, r10, r11, r12, r2.X, r2.Y, r2.Z), offset
	end,

	function(input: buffer, offset: number) -- CFrameEuler
		local comp = buru8(input, offset)
		local func,mult
		if comp == 1 then
			func = burf32
			mult = 1
		else
			func = burf64
			mult = 2
		end
		offset+=1
		local X = func(input, offset)
		local Y = func(input, offset+4*mult)
		local Z = func(input, offset+8*mult)
		local rX = func(input, offset+12*mult)
		local rY = func(input, offset+16*mult)
		local rZ = func(input, offset+20*mult)
		offset+=24*mult
		return (CFe(rX,rY,rZ)+V3n(X,Y,Z)),offset
	end,
	function(input: buffer, offset: number) -- Color3
		local brick = buru8(input, offset)
		local comp = buru8(input, offset+1)
		local func,mult
		if comp == 1 then
			func = burf32
			mult = 1
		else
			func = burf64
			mult = 2
		end
		offset+=2
		local R = func(input, offset)
		local G = func(input, offset+4*mult)
		local B = func(input, offset+8*mult)
		offset+=12*mult
		if brick == 1 then
			return BCn(R,G,B),offset
		else
			return C3n(R,G,B),offset
		end
	end,
	function(input: buffer, offset: number) -- Color3b
		local brick = buru8(input, offset)
		local R = buru8(input, offset+1)
		local G = buru8(input, offset+2)
		local B = buru8(input, offset+3)
		offset+=4
		if brick == 1 then
			return BCn(R/255,G/255,B/255),offset
		else
			return C3r(R,G,B),offset
		end
	end,
	nil, -- DO NOT USE: Handled elsewhere, begin marker for tables.
	nil, -- DO NOT USE: End marker for tables.
	nil, -- DO NOT USE: Handled elsewhere, begin marker for dictionaries.
	function(input: buffer, offset:number) -- nil
		return nil,offset
	end,
	function(input: buffer, offset:number) -- ColorSequence
		local count, off = module.DecodeVarLength(input, offset)
		offset += off
		local float = buru8(input, offset)==1 offset += 1
		local bytes = buru8(input, offset)==1 offset += 1
		local times = {}
		local keypoints = {}
		local func,add
		if float then func,add = burf32,4 else func,add = burf64,8 end
		for i = 1, count do
			ti(times, func(input, offset))
			offset += add
		end
		for i = 1, count do
			local col
			if bytes then
				local r = buru8(input, offset) offset += 1
				local g = buru8(input, offset) offset += 1
				local b = buru8(input, offset) offset += 1
				col = C3r(r,g,b)
			else
				local r = func(input, offset) offset += add
				local g = func(input, offset) offset += add
				local b = func(input, offset) offset += add
				col = C3n(r,g,b)
			end
			ti(keypoints, ColorSequenceKeypoint.new(times[i],col))
		end
		return ColorSequence.new(keypoints),offset
	end,
	function(input: buffer, offset:number) -- Vector2int16
		local X = buru16(input, offset) offset += 2
		local Y = buru16(input, offset) offset += 2
		return Vector2int16.new(X-32768,Y-32768),offset
	end,
	function(input: buffer, offset:number) -- Vector3int16
		local X = buru16(input, offset) offset += 2
		local Y = buru16(input, offset) offset += 2
		local Z = buru16(input, offset) offset += 2
		return Vector3int16.new(X-32768,Y-32768,Z-32768),offset
	end,

	function(input: buffer, offset: number) -- EnumItem
		local value = buru8(input, offset) 
		offset += 1

		local enumIdx = buru16(input, offset)
		offset += 2
		
		return (enumMap or enumMapFallback)[enumIdx]:FromValue(value), offset
	end,

	function(input: buffer, offset: number) -- UDim2
		local Xscale = burf32(input, offset)
		local Xoffset = burf32(input, offset + 4)
		local Yscale = burf32(input, offset + 8)
		local Yoffset = burf32(input, offset + 12)

		offset += 16
		return UD2new(Xscale, Xoffset, Yscale, Yoffset), offset
	end,
}

module.ReadType = function(input: buffer, offset: number, type: number)
	return functions[type+1](input, offset)
end

return module