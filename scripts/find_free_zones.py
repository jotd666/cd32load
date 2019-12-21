# scans memory for either a contiguous zone of 0 or 0xCC (whdload init)
# resload & cdbuffer can probably be installed there
import sys

f = open(sys.argv[1],"rb")

contents = f.read()

f.close()


def find_free_zone(fill_code,free_zone_threshold):
    current_zone_len = 0

    for i,c in enumerate(contents):
        oc = ord(c)
        if oc==fill_code:
            current_zone_len+=1
        else:
            if current_zone_len>=free_zone_threshold:
                print("Free zone: start %08x, end %08x, len $%04x" % ((i-current_zone_len),i,current_zone_len))
            current_zone_len = 0

z=0x10000
find_free_zone(0,z)
find_free_zone(0xcc,z)
