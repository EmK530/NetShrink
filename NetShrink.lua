local module = {}

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
local mace = math.ceil
local b3ba = bit32.band
local b3ls = bit32.lshift
local b3rs = bit32.rshift
local buco = buffer.copy
local bucr = buffer.create
local buru8 = buffer.readu8
local buwu8 = buffer.writeu8
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

-- Decodes data types from a buffer and returns them as multiple arguments
module.Decode = function(input,asTable)
	local offset = 1
	local dataTypesSize = buru8(input, 0)
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
	for i = 1, #dataTypes do
		local ty = dataTypes[i]
		local ret,r = Decode.ReadType(input,offset,ty)
		ti(returns,ret)
		offset = r
	end
	if asTable then
		return returns
	else
		return unpack(returns)
	end
end

-- Encodes data types into a buffer and returns said buffer
module.Encode = function(...)
	local dataTypes = {}
	local encodedData = {}
	local max = 2^DataTypeBits-1
	for i,v in p({...}) do
		if v.DataType > max then return error("Cannot encode DataType "..v.DataType) end
		ti(dataTypes, v.DataType)
		local enc = Encode.Convert(v)
		ti(encodedData,enc)
	end
	
	local dataTypesSize = #dataTypes
	local dataTypesBuffer = bucr(1 + mace(dataTypesSize * DataTypeBits / 8))
	local offset = 1
	buwu8(dataTypesBuffer, 0, dataTypesSize)
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
			print("Could not compress string! Gained "..(#new-#input).." bytes.")
			compressed = false
		end
	end
	
	return {
		DataType = 0,
		CompressMode = (if compressed then compressMode else 0),
		Data = input
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

return module