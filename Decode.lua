local module = {}

local ti = table.insert
local b3ba = bit32.band
local b3ls = bit32.lshift
local b3rs = bit32.rshift
local buru8 = buffer.readu8
local buru16 = buffer.readu16
local buru32 = buffer.readu32
local burf32 = buffer.readf32
local burf64 = buffer.readf64
local burs = buffer.readstring

local V2n = Vector2.new
local V3n = Vector3.new
local C3n = Color3.new
local C3r = Color3.fromRGB
local CFn = CFrame.new
local CFe = CFrame.fromEulerAnglesXYZ

local Comp = require(script.Parent.Compression)

local compressModeTargets = {
	"Deflate",
	"Zlib"
}

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
		local str = burs(input, offset, len)
		offset+=len
		if mode > 0 then
			str = Comp[compressModeTargets[mode]].Decompress(str)
		end
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
		local values = {}
		for i = 1, 12 do
			ti(values,func(input, offset+((i-1)*4*mult)))
		end
		offset+=48*mult
		return CFn(unpack(values)),offset
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
		local R = func(input, offset)
		local G = func(input, offset+4*mult)
		local B = func(input, offset+8*mult)
		offset+=12*mult
		return C3n(R,G,B),offset
	end,
	function(input: buffer, offset: number) -- Color3b
		local R = buru8(input, offset)
		local G = buru8(input, offset+1)
		local B = buru8(input, offset+2)
		offset+=3
		return C3r(R,G,B),offset
	end,
	nil,
	nil,
	function(input: buffer, offset: number) -- Boolean
		local b = buru8(input, offset)
		offset+=1
		return (b==1),offset
	end,
}

module.ReadType = function(input: buffer, offset: number, type: number)
	return functions[type+1](input, offset)
end

return module