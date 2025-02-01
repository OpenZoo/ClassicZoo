# Copyright (c) 2021 Adrian Siekierka
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#!/usr/bin/env python3
from struct import unpack
import os, sys

f = open(sys.argv[1], 'rb')
hdr_magic, hdr_version = unpack('<HH', f.read(4))
entry_pos = 0

hdr_name = ''
hdr_engine_name = ''
hdr_flags = 0

if hdr_magic != 0xD327:
	print("Invalid magic!")
elif hdr_version == 0x0001:
	hdr_name, hdr_flags = unpack('<21pB', f.read(22))
	hdr_name = hdr_name.decode('cp437')
elif hdr_version == 0x0002:
	hdr_name, hdr_flags, hdr_engine_name = unpack('<21pB31p', f.read(53))
	hdr_name = hdr_name.decode('cp437')
	hdr_engine_name = hdr_engine_name.decode('cp437')
else:
	print("Invalid version!")

print(f"ZZD file v{hdr_version}, for world '{hdr_name}', under engine '{hdr_engine_name}', flags = {hdr_flags}")

f_data_start = f.tell()
f.seek(0, os.SEEK_END)
f_end = f.tell()
f.seek(f_data_start)
while f.tell() != f_end:
	f_pos = f.tell()
	cmdType = unpack('<B', f.read(1))[0]
	if cmdType == 0:
		count, deltaX, deltaY, shiftPressed, keyPressed = unpack('<hbbBB', f.read(6))
		print(f"[{entry_pos}:{f_pos}] Input: {count} x {deltaX},{deltaY}; shift={shiftPressed}, key={keyPressed}")
	elif cmdType == 1:
		randSeed = unpack('<I', f.read(4))[0]
		print(f"[{entry_pos}:{f_pos}] Reseed current tick: {randSeed}")
	elif cmdType == 2:
		randSeed, tickSpeed = unpack('<Ih', f.read(6))
		print(f"[{entry_pos}:{f_pos}] Game start: TickSpeed={tickSpeed}, RandSeed={randSeed}")
	elif cmdType == 3:
		print(f"[{entry_pos}:{f_pos}] Game stop")
	elif cmdType == 4:
		pitTicks = unpack('<h', f.read(2))[0]
		print(f"[{entry_pos}:{f_pos}] PIT tick delta: {pitTicks}")
	else:
		print(f"[{entry_pos}:{f_pos}] Unknown command type {cmdType}!")
	entry_pos += 1

f.close()
