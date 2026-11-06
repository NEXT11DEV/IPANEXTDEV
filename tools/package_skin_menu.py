"""Add a separately compiled read-only diagnostic to the supplied donor IPA."""
from pathlib import Path
import copy,hashlib,json,struct,zipfile
root=Path(__file__).resolve().parent.parent
source=root/'upload/8BallPool-ActivationKit-landscape-test-needs-signing.ipa'
artifact=root/'output/SkinMenu-unsigned.zip'
out=root/'output/8BallPool-SkinMenu-v3-needs-signing.ipa'
with zipfile.ZipFile(source) as original,zipfile.ZipFile(artifact) as framework:
    main='Payload/pool.app/pool'
    raw=original.read(main)
    binary=bytearray(raw)
    assert struct.unpack_from('<I',binary)[0]==0xfeedfacf, 'Expected thin ARM64 Mach-O'
    assert struct.unpack_from('<I',binary,4)[0]==0x100000c
    count,size=struct.unpack_from('<II',binary,16)
    p=32;first=len(binary);dependencies=[]
    for _ in range(count):
        cmd,n=struct.unpack_from('<II',binary,p)
        if cmd==0x19:
            for j in range(struct.unpack_from('<I',binary,p+64)[0]):
                q=p+72+j*80
                off=struct.unpack_from('<I',binary,q+48)[0]
                if off:first=min(first,off)
        if cmd==0xc:
            off=struct.unpack_from('<I',binary,p+8)[0]
            dependencies.append(bytes(binary[p+off:p+n]).split(b'\0')[0].decode())
        p+=n
    name=b'@executable_path/Frameworks/SkinMenu.framework/SkinMenu\0'
    assert not any('SkinMenu' in d for d in dependencies)
    length=(24+len(name)+7)&~7
    end=32+size
    assert end+length<=first
    assert not any(binary[end:end+length]),'Non-zero header padding'
    cmd=struct.pack('<IIIIII',0xc,length,24,0,0x10000,0x10000)+name
    binary[end:end+length]=cmd.ljust(length,b'\0')
    struct.pack_into('<II',binary,16,count+1,size+length)
    assert binary[first:]==raw[first:],'Unexpected change outside Mach-O header'
    new=[]
    for filename in ['SkinMenu','Info.plist']:
        candidates=[n for n in framework.namelist() if n.rsplit('/',1)[-1]==filename and not n.startswith('__MACOSX/')]
        assert len(candidates)==1,(filename,candidates)
        data=framework.read(candidates[0])
        if filename=='SkinMenu':assert struct.unpack_from('<I',data)[0]==0xfeedfacf
        new.append((f'Payload/pool.app/Frameworks/SkinMenu.framework/{filename}',data,filename=='SkinMenu'))
    with zipfile.ZipFile(root/'upload/Ninja_8BP_v56330326(1).ipa') as donor:
        names=['ESP.png','autoplay_on.png','queue.png','account.png']+[f'league_star_{c}.png' for c in ['magenta','cyan','green','amber','gunmetal','red','blue']]
        for filename in names:
            new.append((f'Payload/pool.app/Frameworks/SkinMenu.framework/{filename}',donor.read('Payload/pool.app/ninja_assets/images/'+filename),False))
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as result:
        for info in original.infolist():
            result.writestr(copy.copy(info),bytes(binary) if info.filename==main else original.read(info.filename))
        for name,data,executable in new:
            info=zipfile.ZipInfo(name)
            info.create_system=3
            info.external_attr=((0o100755 if executable else 0o100644)<<16)
            info.compress_type=zipfile.ZIP_DEFLATED
            result.writestr(info,data)
    with zipfile.ZipFile(out) as result:
        assert result.testzip() is None
        changed=[i.filename for i in original.infolist() if original.read(i.filename)!=result.read(i.filename)]
        assert changed==[main],changed
report={'purpose':'Experimental independently rebuilt cosmetic controls, not donor engine transplant','input':source.name,'unchanged':'All existing ActivationKit and Ninja engine bytes preserved; only a dependency added to the main Mach-O header','modifiedOriginalEntries':changed,'added':[n for n,_,_ in new],'archiveCRC':'PASS','deviceTest':'NOT RUN','requires':'Full re-signing of app and embedded framework','sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
(root/'output/SkinMenu-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(out)
print(json.dumps(report,indent=2))
