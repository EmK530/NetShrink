# NetShrink
A Roblox module that compresses data types into a buffer for minimal network use during transmission.

## Credits
DEFLATE/Zlib module not created by me, [see the original asset here](https://create.roblox.com/store/asset/5649237524)

## How to use
Either download the rbxm from the [Releases](https://github.com/EmK530/NetShrink/releases) section, or set it up yourself with the 4 source scripts.<br>
NetShrink is the main script you will be requiring. If you are setting up manually,<br>the three other scripts should be children of the NetShrink module as demonstrated.<br>
<img src="https://i.imgur.com/GJjvz2y.png"><br>

## Encoding data for transmission
To encode data into a buffer, you call the `NetShrink.Encode` function which takes a variable number of arguments.<br>
These arguments will be the variables you compress into the buffer for transmission,<br>
but these have to be passed through a custom NetShrink function to convert them into proper data for encoding.<br>
Many of them exist and they are all documented below, but here is a code example:
```
local encoded = NetShrink.Encode(
	NetShrink.UInt8(127),
	NetShrink.UInt16(65533),
	NetShrink.UInt32(4294967295)
)
-- To get encoded size, do buffer.len(encoded)
game.ReplicatedStorage.UnreliableRemoteEvent:FireServer(encoded)
```

## Decoding data
To decode data from a buffer, call the `NetShrink.Decode` function.<br>
This function takes a `buffer` as an input but also a `boolean`.<br>
The buffer is of course what's being decoded but if you send `true` as the second argument,<br>
the function returns the decoded variables in a table instead of multiple return values.

If we are trying to decode our example transmission, here's a simple example:
```
game.ReplicatedStorage.Unrel.OnServerEvent:Connect(function(plr,data)
  print(NetShrink.Decode(data,true)) -- prints a table
  print(NetShrink.Decode(data)) -- prints: 127 65533 4294967295
end)
```

## Documentation
Below is a list of all supported data types and their respective functions and documentation.
- [String](https://github.com/EmK530/NetShrink#string)
- [Boolean5](https://github.com/EmK530/NetShrink#boolean5)
- [UInt8](https://github.com/EmK530/NetShrink#uint8)
- [UInt16](https://github.com/EmK530/NetShrink#uint16)
- [UInt32](https://github.com/EmK530/NetShrink#uint32)
- [Single](https://github.com/EmK530/NetShrink#single)
- [Double](https://github.com/EmK530/NetShrink#double)
- [Vector2](https://github.com/EmK530/NetShrink#vector2)
- [Vector3](https://github.com/EmK530/NetShrink#vector3)
- [CFrame](https://github.com/EmK530/NetShrink#cframe)
- [CFrameEuler](https://github.com/EmK530/NetShrink#cframeeuler)
- [Color3](https://github.com/EmK530/NetShrink#color3)
- [Color3b](https://github.com/EmK530/NetShrink#color3b)
<hr>

### String
Stores a string with optional compression methods.<br>
Arguments: `input: string`, `compressMode: number`, `compressLevel: number`<br>
`compressMode`: Controls what compression method to use, (0: `None`, 1: `DEFLATE`, 2: `Zlib`)<br>
`compressLevel`: Controls the compression level, higher takes longer to process, range: 0-9<br>
Example: `NetShrink.String("aaaaaaaaaaaaa",1,9)`
<hr>

### Boolean5
Stores up to 5 booleans into one byte.<br>
Arguments: `...`, only booleans can be sent, exceeding 5 arguments or sending none causes an error.<br>
Example: `NetShrink.Boolean5(true,true,false,false,true)`
<hr>

### UInt8
Stores a number from 0-255 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `NetShrink.UInt8(127)`
<hr>

### UInt16
Stores a number from 0-65535 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `NetShrink.UInt16(32767)`
<hr>

### UInt32
Stores a number from 0-4294967295 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `NetShrink.UInt32(2147483647)`
<hr>

### Single
Stores a number as a 4-byte single-precision floating point. This risks losing some precision over normal number variables.<br>
Arguments: `num: number`<br>
Example: `NetShrink.Single(34578547893347589)` (this loses precision and becomes 34578547624378370)
<hr>

### Double
Stores a number as a 8-byte double-precision floating point. The standard number variable data type.<br>
Arguments: `num: number`<br>
Example: `NetShrink.Double(34578547893347589)`
<hr>

### Vector2
Stores a Vector2 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 8 bytes`, `Double-precision: 16 bytes.`
Arguments: `input: Vector2`, `float: boolean`, setting `float` to true will encode the Vector2 as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.Vector2(Vector2.new(384956,29538),true)`, this encodes as single-precision.
<hr>

### Vector3
Stores a Vector3 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 12 bytes`, `Double-precision: 24 bytes.`
Arguments: `input: Vector3`, `float: boolean`, setting `float` to true will encode the Vector3 as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.Vector3(Vector3.new(384956,29538,347835),true)`, this encodes as single-precision.
<hr>

### CFrame
Stores a CFrame with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 48 bytes`, `Double-precision: 96 bytes.`
Arguments: `input: CFrame`, `float: boolean`, setting `float` to true will encode the CFrame as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.CFrame(workspace.SpawnLocation.CFrame,true)`, this encodes as single-precision.
<hr>
