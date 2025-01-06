local module = {}

local isStudio = game:GetService("RunService"):IsStudio()
local debugMode = false and isStudio -- change this if you want, enables compression fail reports for strings

local function CheckForModules(names)
	for _,name in pairs(names) do
		local Check = script:FindFirstChild(name)
		if not Check then
			return error("[NetShrink] Could not locate child module '"..name.."'")
		end
		if Check.ClassName ~= "ModuleScript" then
			return error("[NetShrink] Child instance '"..name.."' is not a ModuleScript")
		end
	end
end

CheckForModules({"Compression","Encode","Decode"})

local Comp = require(script.Compression)
local Encode = require(script.Encode)
local Decode = require(script.Decode)

-- Optimization Constants

local p = pairs
local ts = tostring
local ti = table.insert
local tr = table.remove
local mace = math.ceil
local b3ba = bit32.band
local b3ls = bit32.lshift
local b3rs = bit32.rshift
local b3bx = bit32.bxor
local buco = buffer.copy
local bucr = buffer.create
local buru8 = buffer.readu8
local buwu8 = buffer.writeu8
local burs = buffer.readstring
local buws = buffer.writestring
local bule = buffer.len

local compressModeTargets = {
	"Deflate",
	"Zlib"
}

local debuggingFunctions = {
	function(input)
		local dataSize = #input.Data
		local varlen = Encode.EncodeVarLength(dataSize)
		warn("Debugging Data Type 'string'")
		local compressed = input.CompressMode~=0
		print("Compressed: "..ts(compressed).." ("..ts(compressModeTargets[input.CompressMode])..")")
		print("Size: "..dataSize.." (VarLength bytes: "..bule(varlen)..")")
		local data = input.Data
		if compressed then
			data = Comp[compressModeTargets[input.CompressMode]].Decompress(data)
		end
		print("Content: "..data)
	end,
}

-- Possible Storage: 2 ^ DataTypeBits
-- 2, 4, 8, 16, 32, 64, 128, 256
-- Should not exceed 8
local DataTypeBits = 4

-- Encrypts/decrypts your buffer through XOR shifting using random numbers with the key as a seed
module.Shift = function(input: buffer, key: number)
	local len = bule(input)
	local rand = Random.new(key+len)
	for i = 1, len do
		buwu8(input,i-1,b3bx(buru8(input,i-1),rand:NextInteger(0,255)))
	end
	return input
end

-- Decodes data types from a buffer and returns them as multiple arguments
module.Decode = function(input: buffer, asTable, key)
	if key ~= nil and typeof(key) == "number" then
		-- Decrypt buffer with key
		input = module.Shift(input, key)
	end
	local st = burs(input,0,4)
	assert(st == "NShd", "[NetShrink] Cannot decode invalid buffer, expected 'NShd' header but got '"..st.."'")
	local offset = 5
	local dataTypesSize = buru8(input, 4)
	local dataTypes = {}
	local bitBuffer = 0
	local bitsUsed = 0
	local byte
	for i = 1, dataTypesSize do
		while bitsUsed < DataTypeBits do
			byte = buru8(input, offset)
			offset+=1
			bitBuffer = bitBuffer + b3ls(byte, bitsUsed)
			bitsUsed+=8
		end
		local mask = b3ls(1,DataTypeBits)-1
		local value = b3ba(bitBuffer, mask)
		ti(dataTypes, value)
		bitBuffer = b3rs(bitBuffer, DataTypeBits)
		bitsUsed-=DataTypeBits
	end
	local returns = {}
	local cur = returns
	local layers = {returns}
	local layer = 1
	for i = 1, #dataTypes do
		local ty = dataTypes[i]
		if ty ~= 13 and ty ~= 14 then
			local ret,r = Decode.ReadType(input,offset,ty)
			if ret~=nil then ti(cur,ret) end
			offset = r
		else
			if ty == 14 then
				layer -= 1
				local n = layers[layer]
				ti(n,cur)
				tr(layers,layer+1)
				cur = n
			else
				layer += 1
				local new = {}
				ti(layers, new)
				cur = new
			end
		end
	end
	if asTable then
		return returns
	else
		return unpack(returns)
	end
end

local function RecursiveEncode(inp: {}, output, types, topmost)
	local max = 2^DataTypeBits-1
	local amt = #inp
	local key = nil
	local totals = 0
	for i,v in p(inp) do
		local t = typeof(v)
		if t ~= "table" then
			if topmost and i == amt and t == "number" then
				key = v
				continue
			else
				error("[NetShrink] Invalid argument type for Encode, expected table but got "..t)
			end
		end
		assert(v.DataType <= max, "[NetShrink] Cannot encode DataType "..v.DataType)
		if v.DataType == 13 then
			ti(types, 13)
			local _,a = RecursiveEncode(v.Value,output,types)
			ti(types, 14)
			totals += a + 2
		else
			ti(types, v.DataType)
			local enc = Encode.Convert(v)
			ti(output,enc)
			totals += 1
		end
	end
	return key,totals
end

-- Encodes data types into a buffer and returns said buffer
module.Encode = function(...)
	local dataTypes = {}
	local encodedData = {}
	local key,dataTypesSize = RecursiveEncode({...},encodedData,dataTypes,true)
	local dataTypesBuffer = bucr(5 + mace(dataTypesSize * DataTypeBits / 8))
	buws(dataTypesBuffer,0,"NShd")
	local offset = 5
	buwu8(dataTypesBuffer, 4, dataTypesSize)
	local bitBuffer = 0
	local bitsUsed = 0
	for _, v in p(dataTypes) do
		bitBuffer+=b3ls(v, bitsUsed)
		bitsUsed+=DataTypeBits
		if bitsUsed >= 8 then
			buwu8(dataTypesBuffer, offset, b3ba(bitBuffer, 0xFF))
			bitBuffer = b3rs(bitBuffer, 8)
			bitsUsed-=8
			offset+=1
		end
	end
	if bitsUsed > 0 then
		buwu8(dataTypesBuffer, offset, bitBuffer)
		offset+=1
	end
	
	local encodedDataSize = 0
	for _, v in p(encodedData) do
		encodedDataSize+=bule(v)
	end
	local finalBuffer = bucr(offset + encodedDataSize)
	buco(finalBuffer, 0, dataTypesBuffer, 0, offset)
	local finalOffset = offset
	for _, v in p(encodedData) do
		local s = bule(v)
		buco(finalBuffer, finalOffset, v, 0, s)
		finalOffset+=s
	end
	if key ~= nil then
		finalBuffer = module.Shift(finalBuffer, key)
	end
	return finalBuffer
end

module.DebugDataType = function(input: any)
	debuggingFunctions[input.DataType+1](input)
end

-- Data Types

--[[
CompressMode:
0 - Raw
1 - Deflate
2 - Zlib

CompressLevel: 0 - 9
]]
module.String = function(input: string, compressMode: number, compressLevel: number)
	if not compressMode then compressMode = 0 end
	if not compressLevel then compressLevel = 0 end
	if compressLevel < 0 or compressLevel > 9 then return error("[NetShrink] Compression level not within range 0-9") end
	if compressMode < 0 or compressMode > 2 then return error("[NetShrink] Compression mode not within range 0-9") end
	local compressed = compressMode > 0 and compressLevel > 0
	
	if compressed then
		local new = Comp[compressModeTargets[compressMode]].Compress(input, {
			level = compressLevel,
			strategy = "fixed"
		})
		if #new < #input then
			input = new
		else
			if debugMode then
				print("[NetShrink] Could not compress string! Gained "..(#new-#input).." bytes.")
			end
			compressed = false
		end
	end
	
	return {
		DataType = 0,
		CompressMode = (if compressed then compressMode else 0),
		Data = input
	}
end

module.Boolean = function(bool: boolean)
	return {
		DataType = 15,
		Value = bool
	}
end

module.Boolean5 = function(...)
	local tbl = {...}
	local len = #tbl
	if len > 5 then return error("[NetShrink] BooleanTables cannot hold more than 5 booleans") end
	if len == 0 then return error("[NetShrink] BooleanTables cannot be empty") end
	local out = b3ls(len-1,5)
	for i = 1, len do
		local val = tbl[i]
		if val then
			out += b3ls(1,5-i)
		end
	end
	return {
		DataType = 1,
		Value = out
	}
end

module.UInt8 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt8 cannot be less than 0") end
	if num > 255 then return error("[NetShrink] Number for UInt8 cannot be greater than 255") end
	return {
		DataType = 2,
		Value = num
	}
end

module.UInt16 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt16 cannot be less than 0") end
	if num > 65535 then return error("[NetShrink] Number for UInt16 cannot be greater than 65535") end
	return {
		DataType = 3,
		Value = num
	}
end

module.UInt32 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt32 cannot be less than 0") end
	if num > 4294967295 then return error("[NetShrink] Number for UInt32 cannot be greater than 4294967295") end
	return {
		DataType = 4,
		Value = num
	}
end

module.Single = function(num: number)
	return {
		DataType = 5,
		Value = num
	}
end

module.Double = function(num: number)
	return {
		DataType = 6,
		Value = num
	}
end

module.Vector2 = function(input: Vector2, float: boolean)
	if not float then float = false end
	return {
		DataType = 7,
		comp = float,
		Data = {input.X,input.Y}
	}
end

module.Vector3 = function(input: Vector3, float: boolean)
	if not float then float = false end
	return {
		DataType = 8,
		comp = float,
		Data = {input.X,input.Y,input.Z}
	}
end

module.CFrame = function(input: CFrame, float: boolean)
	if not float then float = false end
	return {
		DataType = 9,
		comp = float,
		Data = {input:GetComponents()}
	}
end

module.CFrameEuler = function(input: CFrame, float: boolean)
	if not float then float = false end
	local rx,ry,rz = input:ToEulerAnglesXYZ()
	return {
		DataType = 10,
		comp = float,
		Data = {input.X,input.Y,input.Z,rx,ry,rz}
	}
end

module.Color3 = function(input: Color3, float: boolean)
	if not float then float = false end
	return {
		DataType = 11,
		comp = float,
		Data = {input.R,input.G,input.B}
	}
end

local mf = math.floor
local mc = math.clamp

local function toByte(num)
	return mc(mf(num*255),0,255)
end

module.Color3b = function(input: Color3)
	return {
		DataType = 12,
		R = toByte(input.R),
		G = toByte(input.G),
		B = toByte(input.B)
	}
end

module.Table = function(...)
	local t = {}
	for _,v in pairs({...}) do
		table.insert(t,v)
	end
	return {
		DataType = 13,
		Value = t
	}
end

return module