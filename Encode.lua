local module = {}

local p = pairs
local ti = table.insert
local b3ba = bit32.band
local b3rs = bit32.rshift
local b3bo = bit32.bor
local bucr = buffer.create
local buwu8 = buffer.writeu8
local buwu16 = buffer.writeu16
local buwi16 = buffer.writei16
local buwu32 = buffer.writeu32
local buwf32 = buffer.writef32
local buwf64 = buffer.writef64
local buws = buffer.writestring
local bule = buffer.len
local buco = buffer.copy

local tbfFunctions = {
	function(input)
		local dat = input.Data
		local size = #dat
		local buf = bucr(size)
		buws(buf,0,dat,size)
		return buf
	end,
}

local function ToBuffer(input)
	return tbfFunctions[input.DataType+1](input)
end

local function toI16(num: number)
	return math.floor(num * 32767 + 0.5)
end

local function BufByte(input)
	local buf = bucr(1)
	buwu8(buf,0,input)
	return buf
end

local function MergeBuffers(...)
	local offset = 0
	local totalSize = 0
	local list = {...}
	for _,v in p(list) do
		totalSize += bule(v)
	end
	local buf = bucr(totalSize)
	for _,v in p(list) do
		local size = bule(v)
		buco(buf,offset,v,0,size)
		offset+=size
	end
	return buf
end

module.EncodeVarLength = function(input: number)
	local bytes = {}
	while true do
		local x = b3ba(input, 0x7F)
		input = b3rs(input, 7)
		if input == 0 then
			ti(bytes, b3bo(0x80, x))
			break
		end
		ti(bytes,x)
		input-=1
	end
	local buf = bucr(#bytes)
	for i,v in p(bytes) do
		buwu8(buf,i-1,v)
	end
	return buf
end

local function OutlineMoment(v)
	local buf
	local func
	local off
	local dat = v.Data
	if v.comp then
		buf = bucr(#dat*4+1)
		func = buwf32
		off = 4
	else
		buf = bucr(#dat*8+1)
		func = buwf64
		off = 8
	end
	buwu8(buf,0,(if v.comp then 1 else 0))
	for i,d in pairs(dat) do
		func(buf,(i-1)*off+1,d)
	end
	return buf
end

local mf = math.floor
local mc = math.clamp
local function toByte(num)
	return mc(mf(num*255),0,255)
end

local functions
functions = {
	function(v) -- String
		local varlen = module.EncodeVarLength(#v.Data)
		local buf = MergeBuffers(varlen,BufByte(v.CompressMode),ToBuffer(v))
		return buf
	end,
	function(v) -- Boolean5
		local buf = bucr(1)
		buwu8(buf,0,v.Value)
		return buf
	end,
	function(v) -- UInt8
		local buf = bucr(1)
		buwu8(buf,0,v.Value)
		return buf
	end,
	function(v) -- UInt16
		local buf = bucr(2)
		buwu16(buf,0,v.Value)
		return buf
	end,
	function(v) -- UInt32
		local buf = bucr(4)
		buwu32(buf,0,v.Value)
		return buf
	end,
	function(v) -- float
		local buf = bucr(4)
		buwf32(buf,0,v.Value)
		return buf
	end,
	function(v) -- double
		local buf = bucr(8)
		buwf64(buf,0,v.Value)
		return buf
	end,
	function(v) -- Vector2
		return OutlineMoment(v)
	end,
	function(v) -- Vector3
		return OutlineMoment(v)
	end,
	
	function(v) -- CFrame
		--> roblox always stores cframes as 3 f32s for position and 9 i16s for rotation matrices
		--> since the rotation vectors are always perpendicular we can only save two
		--> and reconstruct the other when decoding from cross product

		local x, y, z, r00, r01, r02, r10, r11, r12, _, _, _ = unpack(v.Data)
		
		local buf = bucr(24)
		--> position
		buwf32(buf, 0, x); buwf32(buf, 4, y); buwf32(buf, 8, z)
		
		--> rotation vector 1
		buwi16(buf, 12, toI16(r00)); buwi16(buf, 14, toI16(r01)); buwi16(buf, 16, toI16(r02))
		
		--> rotation vector 2
		buwi16(buf, 18, toI16(r10)); buwi16(buf, 20, toI16(r11)); buwi16(buf, 22, toI16(r12))
		
		return buf
	end,
	
	function(v) -- CFrameEuler
		return OutlineMoment(v)
	end,
	function(v , ident) -- Color3
		local buf
		local func
		local off
		local dat = v.Data
		if v.comp then
			buf = bucr(#dat*4+2)
			func = buwf32
			off = 4
		else
			buf = bucr(#dat*8+2)
			func = buwf64
			off = 8
		end
		local o = 1
		if ident == false then
			o = 0
		else
			buwu8(buf,0,(if v.Brick then 1 else 0))
		end
		buwu8(buf,o,(if v.comp then 1 else 0))
		for i,d in pairs(dat) do
			func(buf,(i-1)*off+(o+1),d)
		end
		return buf
	end,
	function(v, ident) -- Color3b
		local buf = bucr(4)
		local o = 1
		if ident == false then
			o = 0
		else
			buwu8(buf,0,(if v.Brick then 1 else 0))
		end
		buwu8(buf,o,v.R)
		buwu8(buf,o+1,v.G)
		buwu8(buf,o+2,v.B)
		return buf
	end,
	function(v) -- Table
		local objs = {}
		local total = 0
		for _,a in p(v.Value) do
			local buf = functions[a.DataType+1](a)
			total += bule(buf)
			ti(objs, buf)
		end
		local out = bucr(total)
		total = 0
		for _,v in p(objs) do
			local len = bule(v)
			buco(out,total,v,0,len)
			total += len
		end
		return out
	end,
	nil, -- DO NOT USE: End marker for tables.
	nil, -- DO NOT USE: Handled elsewhere, begin marker for dictionaries.
	function(v) -- nil
		return bucr(0)
	end,
	function(v) -- ColorSequence
		local func
		local off
		local dat = v.Data
		local kp = v.Value.Keypoints
		local count = #kp
		if v.comp1 then
			func = buwf32
			off = 4
		else
			func = buwf64
			off = 8
		end
		local sz = (if v.comp2 then 3 else off*3)*count+2
		local varlen = module.EncodeVarLength(count)
		local lensz = bule(varlen)
		local buf = bucr(count*off+sz+lensz)
		buco(buf,0,varlen,0,lensz)
		buwu8(buf,lensz,(if v.comp1 then 1 else 0))
		buwu8(buf,lensz+1,(if v.comp2 then 1 else 0))
		local pos = lensz+2
		for _,k in kp do
			func(buf,pos,k.Time)
			pos += off
		end
		for _,k in kp do
			local c = k.Value
			if v.comp2 then
				buwu8(buf,pos,toByte(c.R))
				buwu8(buf,pos+1,toByte(c.G))
				buwu8(buf,pos+2,toByte(c.B))
				pos += 3
			else
				-- looks dumb but should technically be faster
				func(buf,pos,c.R)
				pos += off
				func(buf,pos,c.G)
				pos += off
				func(buf,pos,c.B)
				pos += off
			end
		end
		return buf
	end,
	function(v) -- Vector2int16
		local buf = bucr(4)
		buwu16(buf,0,v.Data[1]+32768)
		buwu16(buf,2,v.Data[2]+32768)
		return buf
	end,
	function(v) -- Vector3int16
		local buf = bucr(6)
		buwu16(buf,0,v.Data[1]+32768)
		buwu16(buf,2,v.Data[2]+32768)
		buwu16(buf,4,v.Data[3]+32768)
		return buf
	end,
	function(v) -- EnumItem
		local buf = bucr(3)
		buwu8(buf, 0, v.Data[1]) -- value
		buwu16(buf, 1, v.Data[2]) -- enum idx
		return buf
	end,
	
	function(v) -- UDim2
		local dat = v.Data
		local buf = bucr(#dat*4)
		for i,d in pairs(dat) do
			buwf32(buf,(i-1)*4,d)
		end
		return buf
	end,
}

module.Convert = function(v)
	return functions[v.DataType+1](v)
end

return module
