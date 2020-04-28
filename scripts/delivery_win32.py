import sys,os,zipfile,re,shutil,glob
import find,which


MODULE_FILE = __file__
PROGRAM_DIR = os.path.abspath(os.path.dirname(MODULE_FILE))
ROOTDIR=os.path.join(PROGRAM_DIR,os.pardir)

PRODUCT_NAME="cd32load"

with open(os.path.join(ROOTDIR,"bin","cd32load"),"rb") as f:
    contents = f.read()

vs=b"CD32LOAD version "
offset = contents.find(vs)+len(vs)
version = "v"+contents[offset:offset+4].decode()

music=False
dev=False



print("making archive for version "+version)

os.chdir(ROOTDIR)
archname=PRODUCT_NAME+"_"+version+".zip"

zfn = os.path.join(ROOTDIR,archname)
if os.path.exists(zfn):
    os.remove(zfn)

zf = zipfile.ZipFile(zfn,mode="w",compression=zipfile.ZIP_DEFLATED)


items_list = ["src","lvo","bin","scripts","cdslaves","readme.txt","virtual_*.txt","tested_games.txt","history.txt"]

real_items_list = []
for i in items_list:
    real_items_list.extend(glob.glob(i))


for i in real_items_list:
    print("processing '"+i+"'")
    if os.path.isfile(i):
        zf.write(i,arcname=PRODUCT_NAME+"/"+i)
    else:
        fnd = find.Find()
        items = fnd.init(i)
        for f in items:
            fi = f.replace(os.sep,"/")[2:]
            if os.path.isfile(fi):
                if fi.endswith("~"):
                    pass
                else:
                    zf.write(fi,arcname=PRODUCT_NAME+"/"+fi)
            else:
                zfi = zipfile.ZipInfo(PRODUCT_NAME+"/"+fi+"/")
                zf.writestr(zfi, '')

zfi = zipfile.ZipInfo(PRODUCT_NAME+"/obj/")
zf.writestr(zfi, '')

zf.close()




