local module = {}

--[[

NetShrink v1.3
Developed by EmK530

]]

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

--[[

Optimization Constants

Most of these do nothing if supported by FASTCALL,
but it still optimizes cases where FASTCALL fails for whatever reason,
replacing a GETIMPORT instruction with a MOVE instruction.

]]

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
local min = math.min

local compressModeTargets = {
	"Deflate",
	"Zlib"
}

-- Possible Storage: 2 ^ DataTypeBits
-- 2, 4, 8, 16, 32, 64, 128, 256
-- Should not exceed 8
local DataTypeBits = 4

module.Config = {
	["AutoConversion"] = {
		["Strings"] = {
			["CompressMode"] = 1,
			["CompressLevel"] = 9
		},
		["Preferf32"] = false,
		["Use3bColors"] = true,
		["UseEulerCFrames"] = false
	}
}

-- Encrypts/decrypts your NetShrink buffer through XOR shifting using random numbers with the key as a seed
module.Encrypt = function(input: buffer, key: number)
	local len = bule(input)
	local rand = Random.new(key+len)
	for i = 1, len do
		buwu8(input,i-1,b3bx(buru8(input,i-1),rand:NextInteger(0,255)))
	end
	return input
end

-- Decodes a NetShrink encoded buffer into the original variables
module.Decode = function(input: buffer, asTable, key)
	if key ~= nil and typeof(key) == "number" then
		-- Decrypt buffer with key
		input = module.Encrypt(input, key)
	end
	local st = burs(input,0,4)
	assert(st == "NShd", "[NetShrink] Cannot decode invalid buffer, expected 'NShd' header but got '"..st.."'")
	local dataTypesSize,read = Decode.DecodeVarLength(input,4)
	local offset = 4+read
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
	local i = 1
	local decodeRecursive
	decodeRecursive = function(insert)
		local startLayer = layer
		while i <= #dataTypes do
			local ty = dataTypes[i]
			if ty == 13 then
				layer += 1
				local new = {}
				ti(layers, new)
				cur = new
				i += 1
			elseif ty == 14 then
				layer -= 1
				local ret = cur
				local n = layers[layer]
				tr(layers, layer + 1)
				cur = n
				i += 1
				if startLayer == layer and not insert then
					return ret
				else
					ti(n, ret)
				end
			elseif ty == 15 then
				local keys = {}
				local values = {}
				local tgt = keys
				i += 1
				local swap = false
				while true do
					local ty2 = dataTypes[i]
					if ty2 == 14 then
						if swap then break else swap = true tgt = values end
						i += 1
					else
						ti(tgt,decodeRecursive(false))
					end
				end
				i += 1
				local ret = {}
				for i = 1, min(#keys,#values) do
					local v1,v2 = keys[i],values[i]
					if v1 and v2 then
						ret[v1] = v2
					end
				end
				ti(cur, ret)
			else
				local ret, r = Decode.ReadType(input, offset, ty)
				offset = r
				i += 1
				if startLayer == layer and not insert then
					return ret
				else
					if ret ~= nil then ti(cur, ret) end
				end
			end
		end
	end
	decodeRecursive(true)
	if asTable then
		return returns
	else
		return unpack(returns)
	end
end

local EncodeList

local max = 2^DataTypeBits-1

local function RecursiveEncode(inp: {}, output, types, dictionary)
	local amt = #inp
	local totals = 0
	if dictionary then
		local l1 = {}
		for i,_ in inp do
			ti(l1, i)
		end
		totals += EncodeList(l1, output, types)
		ti(types, 14)
		totals += 1
	end
	totals += EncodeList(inp, output, types)
	return totals
end

EncodeList = function(inp: {}, output, types)
	local totals = 0
	for _,v in inp do
		local t = typeof(v)
		assert(t=="table", "[NetShrink] Invalid argument type for EncodeManual, expected table but got "..t)
		assert(v.DataType <= max, "[NetShrink] Cannot encode DataType "..v.DataType)
		if v.DataType == 13 or v.DataType == 15 then
			ti(types, v.DataType)
			local a = RecursiveEncode(v.Value,output,types,v.DataType==15)
			ti(types, 14)
			totals += a + 2
		else
			ti(types, v.DataType)
			local enc = Encode.Convert(v)
			ti(output,enc)
			totals += 1
		end
	end
	return totals
end

local function IsDictionary(t: {})
	for i, _ in t do
		if typeof(i) ~= "number" or i % 1 ~= 0 then
			return true
		end
	end
	return false
end

-- Encodes NetShrink data types into a buffer and returns said buffer
module.EncodeManual = function(...)
	local dataTypes = {}
	local encodedData = {}
	local dataTypesSize = RecursiveEncode({...},encodedData,dataTypes)
	local dataTypesBuffer = bucr(5 + mace(dataTypesSize * DataTypeBits / 8))
	buws(dataTypesBuffer,0,"NShd")
	local varlen = Encode.EncodeVarLength(dataTypesSize)
	local vls = bule(varlen)
	local offset = 4+vls
	buco(dataTypesBuffer,4,varlen,0,vls)
	print("Encoded datatypes: "..dataTypesSize)
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

--[[
Create a NetShrink data type for a collection of up to 5 booleans.
Size: 1 byte.
]]
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

--[[
Create a NetShrink data type for an unsigned 8-bit integer.
Does not support decimals and ranges outside 0-255
Size: 1 byte.
]]
module.UInt8 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt8 cannot be less than 0") end
	if num > 255 then return error("[NetShrink] Number for UInt8 cannot be greater than 255") end
	return {
		DataType = 2,
		Value = num
	}
end

--[[
Create a NetShrink data type for an unsigned 16-bit integer.
Does not support decimals and ranges outside 0-65535
Size: 2 bytes.
]]
module.UInt16 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt16 cannot be less than 0") end
	if num > 65535 then return error("[NetShrink] Number for UInt16 cannot be greater than 65535") end
	return {
		DataType = 3,
		Value = num
	}
end

--[[
Create a NetShrink data type for an unsigned 32-bit integer.
Does not support decimals and ranges outside 0-4294967295
Size: 4 bytes.
]]
module.UInt32 = function(num: number)
	if num < 0 then return error("[NetShrink] Number for UInt32 cannot be less than 0") end
	if num > 4294967295 then return error("[NetShrink] Number for UInt32 cannot be greater than 4294967295") end
	return {
		DataType = 4,
		Value = num
	}
end

--[[
Create a NetShrink data type for a 32-bit floating point number.
Roblox numbers use Doubles, so you may lose precision with this.
Size: 4 bytes.
]]
module.Single = function(num: number)
	return {
		DataType = 5,
		Value = num
	}
end

--[[
Create a NetShrink data type for a 64-bit floating point number.
Size: 8 bytes.
]]
module.Double = function(num: number)
	return {
		DataType = 6,
		Value = num
	}
end

--[[
Create a NetShrink data type for a Vector2.
Size: 8 bytes as float, 16 bytes as double.
]]
module.Vector2 = function(input: Vector2, float: boolean)
	if not float then float = false end
	return {
		DataType = 7,
		comp = float,
		Data = {input.X,input.Y}
	}
end

--[[
Create a NetShrink data type for a Vector3.
Size: 12 bytes as float, 24 bytes as double.
]]
module.Vector3 = function(input: Vector3, float: boolean)
	if not float then float = false end
	return {
		DataType = 8,
		comp = float,
		Data = {input.X,input.Y,input.Z}
	}
end

--[[
Create a NetShrink data type for a CFrame.
Size: 48 bytes as float, 96 bytes as double.
]]
module.CFrame = function(input: CFrame, float: boolean)
	if not float then float = false end
	return {
		DataType = 9,
		comp = float,
		Data = {input:GetComponents()}
	}
end

--[[
Create a NetShrink data type for a CFrame.
This variant only encodes XYZ coordinates and EulerAngles to reduce the size.
Size: 24 bytes as float, 48 bytes as double.
]]
module.CFrameEuler = function(input: CFrame, float: boolean)
	if not float then float = false end
	local rx,ry,rz = input:ToEulerAnglesXYZ()
	return {
		DataType = 10,
		comp = float,
		Data = {input.X,input.Y,input.Z,rx,ry,rz}
	}
end

--[[
Create a NetShrink data type for a Color3.
Size: 12 bytes as float, 24 bytes as double.
]]
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

--[[
Create a NetShrink data type for a Color3.
This variant loses some precision by converting each color channel to a single byte.
Size: 3 bytes.
]]
module.Color3b = function(input: Color3)
	return {
		DataType = 12,
		R = toByte(input.R),
		G = toByte(input.G),
		B = toByte(input.B)
	}
end


--[[
Create a NetShrink data type for a table.
This function accepts NetShrink data types as entries
]]
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

--[[
Create a NetShrink data type for a dictionary. (table with keys)
This function accepts a dictionary, keys and values should be NetShrink data types
If any value is incorrect it will be removed
]]
module.Dictionary = function(v: {})
	local t = {}
	for i,v in pairs(v) do
		local t1,t2 = typeof(i),typeof(v)
		if t1 == "table" and t2 == "table" and i["DataType"] and v["DataType"] then
			t[i] = v
		else
			if t1 ~= "table" then
				warn("[NetShrink] Ignoring non-datatype dictionary key: "..i)
				continue
			end
			warn("[NetShrink] Ignoring non-datatype dictionary key: "..i)
			continue
		end
	end
	return {
		DataType = 15,
		Value = t
	}
end

local function Boolean5Compatible(v: {})
	local len = #v
	if len <= 1 or len > 5 then return false end
	for _,a in v do
		if typeof(a) ~= "boolean" then return false end
	end
	return true
end

local VtoDT
VtoDT = {
	["number"] = function(v: number)
		local decimal = v % 1 ~= 0
		if decimal or v < 0 or v > 4294967295 then
			local f32 = module.Config.AutoConversion.Preferf32
			return module[if f32 then "Single" else "Double"](v)
		end
		if v <= 255 then return module.UInt8(v) end
		if v <= 65535 then return module.UInt16(v) end
		return module.UInt32(v)
	end,
	["string"] = function(v: string)
		local stringConfig = module.Config.AutoConversion.Strings
		return module.String(v, stringConfig.CompressMode, stringConfig.CompressLevel)
	end,
	["table"] = function(v: {})
		if Boolean5Compatible(v) then
			print("Doing boolean5")
			return module.Boolean5(unpack(v))
		end
		local stuff = {}
		local is_dict = IsDictionary(v)
		if not is_dict then -- Encode as table
			for _,v in v do
				local t = typeof(v)
				local converter = VtoDT[t]
				if not converter then
					warn("[NetShrink] Unsupported variable type: "..t)
					continue
				end
				local result = converter(v)
				if result then
					ti(stuff, result)
				end
			end
			return module.Table(unpack(stuff))		
		end
		-- Encode as dictionary
		for i,v in v do
			local t1,t2 = typeof(i),typeof(v)
			local c1,c2 = VtoDT[t1],VtoDT[t2]
			if not c1 then warn("[NetShrink] Unsupported variable type: "..t1) continue end
			if not c2 then warn("[NetShrink] Unsupported variable type: "..t2) continue end
			local r1,r2 = c1(i),c2(v)
			if r1 and r2 then stuff[r1] = r2 end
		end
		return module.Dictionary(stuff)
	end,
	["boolean"] = function(v: boolean)
		return module.Boolean5(v)
	end,
	["Vector2"] = function(v: Vector2)
		return module.Vector2(v,module.Config.AutoConversion.Preferf32)
	end,
	["Vector3"] = function(v: Vector3)
		return module.Vector3(v,module.Config.AutoConversion.Preferf32)
	end,
	["CFrame"] = function(v: CFrame)
		local ac = module.Config.AutoConversion
		return module[if ac.UseEulerCFrames then "CFrameEuler" else "CFrame"](v,ac.Preferf32)
	end,
	["Color3"] = function(v: Color3)
		local ac = module.Config.AutoConversion
		if ac.Use3bColors then
			return module.Color3b(v)
		end
		return module.Color3(v,ac.Preferf32)
	end,
}

--[[
Variant of NetShrink.Encode that requires arguments to be within a table
Should help with cases where you might exceed a register limit when unpacking.
Automatically converts variables in the table to NetShrink data types then encodes it to a buffer.
]]
module.EncodeT = function(t: {})
	local dataTypes = {}
	for _,v in t do
		local t = typeof(v)
		local converter = VtoDT[t]
		if not converter then
			warn("[NetShrink] Unsupported variable type: "..t)
			continue
		end
		local result = converter(v)
		if result then
			ti(dataTypes, result)
		end
	end
	return module.EncodeManual(unpack(dataTypes))
end

-- Automatically convert variables to NetShrink data types and encode it to a buffer
module.Encode = function(...)
	return module.EncodeT({...})
end

return module
