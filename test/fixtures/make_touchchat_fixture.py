# Builds test/fixtures/touchchat_sample.{ce,c4v}: TouchChat's real schema, invented words.
# Run from any scratch dir:  python3 make_touchchat_fixture.py <repo>/test/fixtures
import sqlite3, zipfile, os, struct, zlib, json, sys
out=sys.argv[1]
def png(color):
    # 2x2 PNG
    raw=b''.join(b'\x00'+bytes(color)*2 for _ in range(2))
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')

# ---- TouchChat-like board (schema copied from a real TouchChat HD export; data invented)
for f in ['vocab.c4v','Images.c4s']:
    if os.path.exists(f): os.remove(f)
c=sqlite3.connect('vocab.c4v'); c.execute('pragma page_size=1024')
c.executescript('''
CREATE TABLE variables (id INTEGER PRIMARY KEY, name TEXT, value TEXT);
CREATE TABLE resources (id INTEGER PRIMARY KEY, rid TEXT, name TEXT, type INTEGER);
CREATE TABLE buttons (id INTEGER PRIMARY KEY, resource_id INTEGER, label TEXT, message TEXT, symbol_link_id INTEGER, visible INTEGER, button_style_id INTEGER);
CREATE TABLE actions (id INTEGER PRIMARY KEY, resource_id INTEGER, rank INTEGER, code INTEGER);
CREATE TABLE pages (id INTEGER PRIMARY KEY, resource_id INTEGER, symbol_link_id INTEGER, page_style_id INTEGER, button_style_id INTEGER, feature INTEGER);
CREATE TABLE button_box_instances (id INTEGER PRIMARY KEY, page_id INTEGER, button_box_id INTEGER, position_x INTEGER, position_y INTEGER, size_x INTEGER, size_y INTEGER);
CREATE TABLE button_box_cells (id INTEGER PRIMARY KEY, button_box_id INTEGER, resource_id INTEGER, location INTEGER, span_x INTEGER, span_y INTEGER);
CREATE TABLE symbol_links (id INTEGER PRIMARY KEY, rid TEXT, feature INTEGER);
CREATE TABLE special_pages (id INTEGER PRIMARY KEY, name TEXT, page_id INTEGER);
''')
c.execute("insert into variables(name,value) values('Name','לוח לדוגמה'),('Locale','he_IL')")
rid=[100]
def res():
    rid[0]+=1; return rid[0]
# page 2 is HOME (so ordering must put it first even though page 1 exists)
c.execute("insert into pages(id,resource_id) values(1,1),(2,2)")
c.execute("insert into special_pages(name,page_id) values('HOME',2)")
c.execute("insert into button_box_instances(page_id,button_box_id) values(1,10),(2,20)")
def button(box,loc,label,msg='',visible=1,codes=(10,),sym=None):
    r=res()
    c.execute("insert into buttons(resource_id,label,message,symbol_link_id,visible) values(?,?,?,?,?)",(r,label,msg,sym,visible))
    c.execute("insert into button_box_cells(button_box_id,resource_id,location) values(?,?,?)",(box,r,loc))
    for k,code in enumerate(codes): c.execute("insert into actions(resource_id,rank,code) values(?,?,?)",(r,k,code))
c.execute("insert into symbol_links(id,rid,feature) values(1,'{PIC-DOG}',0),(2,'{STIX-BUILTIN}',0)")
# HOME page (box 20), inserted out of location order on purpose
button(20,3,'כלב','',sym=1)            # has a custom picture
button(20,1,'אמא','אִמָּא')              # spoken with nikud
button(20,2,'מקלדת','',codes=(10,61,71,71))  # system: keyboard
button(20,4,'מחיקה','',codes=(28,))      # system: delete
button(20,5,'סוד','',visible=0)          # hidden
button(20,6,'','',codes=(10,7))         # empty label (navigation)
button(20,7,'לגן','',sym=2)             # builtin symbol: no picture in export
# page 1 (box 10)
button(10,1,'מֶלון','מֶלון')               # same word as below once nikud is removed
button(10,2,'מלון','מלון')
button(10,3,'פירות','',codes=(10,8))     # category button: still a word
button(10,4,'ש'*900,'')                  # long label -> overflow page
for i in range(700):                     # many rows -> interior b-tree pages
    button(10,10+i,f'מילה{i}','')
# a button that sits on no page
r=res(); c.execute("insert into buttons(resource_id,label,message,visible) values(?,?,?,1)",(r,'יתום',''))
c.commit(); c.execute('vacuum'); c.close()

i=sqlite3.connect('Images.c4s')
i.executescript("CREATE TABLE symbols (id INTEGER PRIMARY KEY, rid TEXT, compressed INTEGER, type INTEGER, width INTEGER, height INTEGER, data BLOB);")
i.execute("insert into symbols(rid,compressed,type,width,height,data) values(?,?,?,?,?,?)",('{PIC-DOG}',0,1,2,2,png((200,120,40))))
i.execute("insert into symbols(rid,compressed,type,width,height,data) values(?,?,?,?,?,?)",('{JUNK}',1,1,2,2,b'\x01\x02\x03'))
i.commit(); i.close()
with zipfile.ZipFile(f'{out}/touchchat_sample.ce','w',zipfile.ZIP_DEFLATED) as z:
    z.write('vocab.c4v','לוח לדוגמה.c4v'); z.write('Images.c4s'); z.writestr('Manifest.c4i',b''); z.writestr('version.txt','1')
os.replace('vocab.c4v',f'{out}/touchchat_sample.c4v')
os.remove('Images.c4s')
