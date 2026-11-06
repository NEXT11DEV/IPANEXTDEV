from pathlib import Path
import copy,struct,zipfile,hashlib,json
source=Path('output/8BallPool-SkinMenu-v4-needs-signing.ipa');out=Path('output/8BallPool-SkinMenu-v5-needs-signing.ipa')
framework='Payload/pool.app/Frameworks/SkinMenu.framework/'
engine='Payload/pool.app/Frameworks/ninja.framework/ninja'
def branch(pc,target,link=False):
 delta=target-pc;assert delta%4==0 and -(1<<27)<=delta<(1<<27)
 return (0x94000000 if link else 0x14000000)|((delta//4)&0x3ffffff)
def adrp(reg,pc,target):
 delta=((target&~4095)-(pc&~4095))//4096;assert -(1<<20)<=delta<(1<<20)
 v=delta&0x1fffff
 return 0x90000000|((v&3)<<29)|((v>>2)<<5)|reg
def cbz(pc,target,wide=False):
 d=(target-pc)//4;assert -(1<<18)<=d<(1<<18)
 return (0xb4000000 if wide else 0x34000000)|((d&0x7ffff)<<5)
with zipfile.ZipFile(source) as original,zipfile.ZipFile('output/SkinMenu-v5.zip') as compiled:
 replacements={}
 for filename in ['SkinMenu','Info.plist']:
  names=[n for n in compiled.namelist() if n.rsplit('/',1)[-1]==filename and not n.startswith('__MACOSX/')];assert len(names)==1
  replacements[framework+filename]=compiled.read(names[0])
 assert b'SkinMenu-5' in replacements[framework+'SkinMenu']
 assert b'SkinFeatureAccess' in replacements[framework+'SkinMenu']
 native=bytearray(original.read(engine));symbol=0x3100;name=b'SkinFeatureAccess\0';assert not any(native[symbol:symbol+len(name)]);native[symbol:symbol+len(name)]=name
 guards=[]
 for entry,pad,expected,label in [(0x36f24,0x2400,'ffc303d1','AutoPlay.Update'),(0x3b294,0x2500,'ffc303d1','TickAutoQueue'),(0x40330,0x2600,'ef3bb66d','DrawESP')]:
  old=struct.unpack_from('<I',native,entry)[0];assert native[entry:entry+4].hex()==expected
  # Preserve all integer/SIMD argument registers across dlsym and access checks.
  stores=[];loads=[]
  for r,off in [(0,16),(2,32),(4,48),(6,64),(8,80)]:
   common=((off//8)<<15)|((r+1)<<10)|(31<<5)|r
   stores.append(0xa9000000|common);loads.append(0xa9400000|common)
  for r,off in [(0,96),(2,128),(4,160),(6,192)]:
   common=((off//16)<<15)|((r+1)<<10)|(31<<5)|r
   stores.append(0xad000000|common);loads.append(0xad400000|common)
  words=[0xa9b07bfd,0x910003fd]+stores
  words += [0x92800020,adrp(1,pad+4*(len(words)+1),symbol),0x91000021|((symbol&4095)<<10)]
  words.append(branch(pad+4*len(words),0xd92a4,True))
  missing=len(words);words.append(0)
  words.append(0xd63f0000)
  denied=len(words);words.append(0)
  words += loads+[0xa8d07bfd,old]
  words.append(branch(pad+4*len(words),entry+4))
  failure=pad+4*len(words);words += [0xa8d07bfd,0xd65f03c0]
  words[missing]=cbz(pad+4*missing,failure,True);words[denied]=cbz(pad+4*denied,failure)
  size=4*len(words);assert size<=256 and not any(native[pad:pad+size])
  native[pad:pad+size]=struct.pack('<%dI'%len(words),*words);struct.pack_into('<I',native,entry,branch(entry,pad));guards.append({'function':label,'entry':hex(entry),'guard':hex(pad)})
 replacements[engine]=bytes(native)
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as result:
  for info in original.infolist():result.writestr(copy.copy(info),replacements.get(info.filename,original.read(info.filename)))
 with zipfile.ZipFile(out) as result:
  assert result.testzip() is None
  changed=[n for n in original.namelist() if original.read(n)!=result.read(n)];assert set(changed)==set(replacements)
  for n in ['Payload/pool.app/pool','Payload/pool.app/Frameworks/ActivationKit.framework/ActivationKit']:assert original.read(n)==result.read(n)
report={'revision':5,'archiveCRC':'PASS','changedFiles':changed,'nativeGuards':guards,'activationVerification':'Startup SHA256 of ActivationKit __text and activation-function address range; server session remains required','runtimeTest':'NOT RUN','securityLimit':'Client-side binary patches remain possible; not tamper-proof','requires':'Full re-signing of the app and embedded frameworks','sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
Path('output/SkinMenu-v5-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
