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

### Boolean5
Stores up to 5 booleans into one single byte.<br>
Arguments: `...`, only booleans can be sent, exceeding 5 arguments or sending none causes an error.<br>
Example: `NetShrink.Boolean5(true,true,false,false,true)`
