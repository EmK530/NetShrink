local module = {}

local p = pairs
local ti = table.insert
local b3ba = bit32.band
local b3rs = bit32.rshift
local b3bo = bit32.bor
local bucr = buffer.create
local buwu8 = buffer.writeu8
local buwu16 = buffer.writeu16
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
		return OutlineMoment(v)
	end,
	function(v) -- CFrameEuler
		return OutlineMoment(v)
	end,
	function(v) -- Color3
		return OutlineMoment(v)
	end,
	function(v) -- Color3b
		local buf = bucr(3)
		buwu8(buf,0,v.R)
		buwu8(buf,1,v.G)
		buwu8(buf,2,v.B)
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
	nil -- not populated
}

module.Convert = function(v)
	return functions[v.DataType+1](v)
end

return module
