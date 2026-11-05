from __future__ import print_function
import ctypes,json
cg=ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
ds=ctypes.CDLL('/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices')
ds.DisplayServicesGetBrightness.argtypes=[ctypes.c_uint32,ctypes.POINTER(ctypes.c_float)]
ds.DisplayServicesSetBrightness.argtypes=[ctypes.c_uint32,ctypes.c_float]
ids=(ctypes.c_uint32*32)();count=ctypes.c_uint32()
cg.CGGetOnlineDisplayList(32,ids,ctypes.byref(count))
for display in ids[:count.value]:
    if cg.CGDisplayVendorNumber(display)==0xA1DE:continue
    value=ctypes.c_float();error=ds.DisplayServicesGetBrightness(display,ctypes.byref(value))
    print(json.dumps(dict(display=display,builtin=bool(cg.CGDisplayIsBuiltin(display)),error=error,brightness=value.value)))
