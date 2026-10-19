"""Validate the DEX invariants that package-string byte replacements can break."""
import hashlib,struct,zlib

def validate_dex(data):
    def u32(p):return struct.unpack_from('<I',data,p)[0]
    assert data[:4]==b'dex\n' and len(data)>=112,'Not a standard DEX'
    assert u32(32)==len(data),'DEX file size mismatch'
    assert data[12:32]==hashlib.sha1(data[32:]).digest(),'DEX signature mismatch'
    assert u32(8)==zlib.adler32(data[12:])&0xffffffff,'DEX checksum mismatch'
    count,offset=u32(56),u32(60)
    previous=None
    for i in range(count):
        p=u32(offset+4*i)
        while data[p]&128:p+=1
        p+=1
        raw=data[p:data.index(0,p)]
        # MUTF-8 encodes NUL specially and preserves UTF-16 surrogate units.
        value=raw.replace(b'\xc0\x80',b'\0').decode('utf-8','surrogatepass').encode('utf-16-be','surrogatepass')
        assert previous is None or previous<value,'DEX string_ids are not strictly sorted'
        previous=value
    return count
