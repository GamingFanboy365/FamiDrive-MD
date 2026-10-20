#!/usr/bin/env python3
"""libretro.py CORE ROM FRAMES OUT -- runs a Mega Drive ROM on a libretro core (Genesis Plus GX)
for FRAMES frames with no input, writing after each one the 4 KB of 68000 RAM at $FF8000
(FamiDrive's variables) to OUT, one block after another."""
import ctypes as C
import os
import sys

core_path, rom_path, frames, out_path = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
core = C.CDLL(os.path.abspath(core_path))
here = C.c_char_p(os.path.abspath(os.path.dirname(out_path) or '.').encode())


class GameInfo(C.Structure):
    _fields_ = [('path', C.c_char_p), ('data', C.c_void_p), ('size', C.c_size_t), ('meta', C.c_char_p)]


ENV_CB = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDEO_CB = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDIO_CB = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
AUDIOB_CB = C.CFUNCTYPE(C.c_size_t, C.c_void_p, C.c_size_t)
POLL_CB = C.CFUNCTYPE(None)
STATE_CB = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)


def env(cmd, data):
    cmd &= 0xFFFF
    if cmd in (9, 31):              # system and save directories
        C.cast(data, C.POINTER(C.c_char_p))[0] = here.value
        return True
    if cmd in (3, 10):              # can dupe frames; pixel format
        return True
    return False


callbacks = [ENV_CB(env), VIDEO_CB(lambda *a: None), AUDIO_CB(lambda *a: None),
             AUDIOB_CB(lambda d, n: n), POLL_CB(lambda: None), STATE_CB(lambda *a: 0)]
core.retro_set_environment(callbacks[0])
core.retro_init()
core.retro_set_video_refresh(callbacks[1])
core.retro_set_audio_sample(callbacks[2])
core.retro_set_audio_sample_batch(callbacks[3])
core.retro_set_input_poll(callbacks[4])
core.retro_set_input_state(callbacks[5])

rom = open(rom_path, 'rb').read()
buf = C.create_string_buffer(rom, len(rom))
info = GameInfo(os.path.abspath(rom_path).encode(), C.cast(buf, C.c_void_p), len(rom), None)
if not core.retro_load_game(C.byref(info)):
    sys.exit('libretro.py: the core would not load ' + rom_path)

core.retro_get_memory_data.restype = C.c_void_p
core.retro_get_memory_size.restype = C.c_size_t
ram = core.retro_get_memory_data(2)                 # RETRO_MEMORY_SYSTEM_RAM: 64 KB
if not ram or core.retro_get_memory_size(2) < 0x10000:
    sys.exit('libretro.py: no 68000 RAM from the core')

with open(out_path, 'wb') as out:
    for _ in range(frames):
        core.retro_run()
        block = C.string_at(ram + 0x8000, 0x1000)
        # Genesis Plus GX keeps the 68000's RAM in host order, a word at a time: swap it back
        out.write(bytes(block[i ^ 1] for i in range(0x1000)))
core.retro_unload_game()
core.retro_deinit()
