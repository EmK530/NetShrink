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
If you want to encode a table of arguments to avoid register limits, NetShrink offers a variant called `NetShrink.EncodeT`<br>
These arguments you send will be the variables you compress into the buffer for transmission.<br>
Here is a code example of how you encode data:
```
local encoded = NetShrink.Encode(
	123,
	{["test1"] = "test2"},
	0.5
)
print("Successfully encoded to "..buffer.len(encoded).." bytes.")
```
<br>
<b>To reduce data usage, see the section "<a href="https://github.com/EmK530/NetShrink#Optimizing-data-usage">Optimizing data usage</a>"</b>

## Encrypting data
Once you've ran `NetShrink.Encode` and gotten your buffer, you can also choose to encrypt it using `NetShrink.Encrypt`<br>
This function takes two arguments, the buffer and a numeric key to use for encryption and it will return the encrypted buffer.<br>
The encryption works by using the number as a seed to randomly XOR shift every single byte.<br>
To decrypt you have two options, either use `NetShrink.Encrypt` again with the same key, or see the section "[Decoding data](https://github.com/EmK530/NetShrink#Decoding-data)"

## Decoding data
To decode data from a buffer, call the `NetShrink.Decode` function.<br>
This function takes a `buffer` as an input but also optionally a `boolean` and a `number`.<br>
The buffer is of course what's being decoded but if you send `true` as the second argument,<br>
the function returns the decoded variables in a table instead of multiple return values.<br>
If a third argument is given (must be `number`) then it will decrypt the input buffer with the argument as the key, before decoding.<br>
This argument must be used if you are decoding an encrypted buffer and the key must match what was used during encoding.

If we are trying to decode our example transmission, here's a simple example:
```
print(NetShrink.Decode(encoded,true)) -- prints a table
print(NetShrink.Decode(encoded)) -- prints: 123 {...} 0.5
```
If `encoded` was encrypted, adding the key used during encoding as the third argument to Decode will make sure the buffer is read correctly.

## Optimizing data usage
Now that NetShrink's recommended encoding method is to handle type conversion automatically,<br>
there are some configs offered to control how aggressive the compression should be for auto conversion.<br>
These settings are accessible through `NetShrink.Config.AutoConversion` and here are all the currently available settings:<br>
#### Strings.CompressMode
Controls the compression method that is attempted on all converted strings.<br>
**Default value: 1 (DEFLATE)**

#### Strings.CompressLevel
Controls the compression level that is used with the compression method.<br>
**Default value: 9**

#### Preferf32
Compresses all floating point numbers as 32-bit, not 64-bit, cutting data size and precision in half. Applies to:<br>
- Decimal Numbers
- Vector2/Vector3
- CFrame
- Color3 (if Use3bColors is false)

**Default value: false**

#### Use3bColors
Compresses every Color3 channel as a UInt8 instead of a floating point number, reducing size from 12/24 bytes to 3 bytes.<br>
**Default value: true**

#### UseEulerCFrames
Compresses CFrames with only XYZ coordinates and euler angles, cutting data size in half.<br>
**Default value: false**

## What's with these type functions?
Before NetShrink updated to v1.3, you would have to convert your variables to NetShrink data types manually.<br>
This is handled automatically now, but you also have the choice to do the conversion yourself with `NetShrink.EncodeManual`<br>
Here's a code example of encoding with EncodeManual, and below you will find [Documentation](https://github.com/EmK530/NetShrink#Documentation) of all types you can encode.<br>
```
local encoded = NetShrink.EncodeManual(
	NetShrink.UInt8(127),
	NetShrink.UInt16(65533),
	NetShrink.UInt32(4294967295),
	NetShrink.Table(NetShrink.Single(0.5)),
	NetShrink.Dictionary({[NetShrink.String("test",0,0)] = NetShrink.Boolean5(true)})
)
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
- [Table](https://github.com/EmK530/NetShrink#table)
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
If more than one boolean is encoded, it decodes as a table of booleans.<br>
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
Sizes: `Single-precision: 8 bytes`, `Double-precision: 16 bytes.`<br>
Arguments: `input: Vector2`, `float: boolean`, setting `float` to true will encode the Vector2 as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.Vector2(Vector2.new(384956,29538),true)`, this encodes as single-precision.
<hr>

### Vector3
Stores a Vector3 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 12 bytes`, `Double-precision: 24 bytes.`<br>
Arguments: `input: Vector3`, `float: boolean`, setting `float` to true will encode the Vector3 as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.Vector3(Vector3.new(384956,29538,347835),true)`, this encodes as single-precision.
<hr>

### CFrame
Stores a CFrame with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 48 bytes`, `Double-precision: 96 bytes.`<br>
Arguments: `input: CFrame`, `float: boolean`, setting `float` to true will encode the CFrame as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.CFrame(workspace.SpawnLocation.CFrame,true)`, this encodes as single-precision.
<hr>

### CFrameEuler
Stores a CFrame with an option to use single-precision to reduce size by half.<br>
This variant only stores XYZ coordinates and XYZ EulerAngles from the `ToEulerAnglesXYZ` function to save space.<br>
Sizes: `Single-precision: 24 bytes`, `Double-precision: 48 bytes.`<br>
Arguments: `input: CFrame`, `float: boolean`, setting `float` to true will encode the CFrame as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.CFrameEuler(workspace.SpawnLocation.CFrame,true)`, this encodes as single-precision.
<hr>

### Color3
Stores a Color3 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 12 bytes`, `Double-precision: 24 bytes.`<br>
Arguments: `input: Color3`, `float: boolean`, setting `float` to true will encode the Color3 as single-precision, sacrificing precision for size.<br>
Example: `NetShrink.Color3(Color3.fromRGB(255,127,64),true)`, this encodes as single-precision.
<hr>

### Color3b
Stores a Color3 as a 3-byte RGB value from 0-255. Any number outside this range will be clamped.<br>
Arguments: `input: Color3`<br>
Example: `NetShrink.Color3b(Color3.fromRGB(255,127,64))`
<hr>

### Table
Accepts a variable number of data type arguments and instructs NetShrink to encode them into a table.<br>
Tables can be placed within eachother endlessly. Cost per table is 1 byte.<br>
Arguments: `...`<br>
Example: `NetShrink.Table(NetShrink.UInt8(127),NetShrink.UInt16(32767))`
<hr>

### Dictionary
Accepts a table with NetShrink DataType keys & values and encodes as a dictionary.<br>
Like with tables, you can have dictionaries in dictionaries. Cost per dictionary is 1.5 bytes.<br>
Arguments: `input: {}`<br>
Example: `NetShrink.Dictionary({[NetShrink.String("testKey",0,0)] = NetShrink.UInt8(123)})`
<hr>
