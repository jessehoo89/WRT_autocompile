#!/usr/bin/env python3
"""Strip given module names from a .ko's modinfo depends field.

Usage: python3 patch_modinfo.py <path/to/module.ko> [dep1] [dep2] ...

The ELF .modinfo section is parsed and the 'depends=' value is rewritten
with the specified module names removed. This is necessary when a kernel
module declares optional runtime dependencies that the OpenWrt build
system treats as mandatory packaging constraints.
"""

import sys
import struct
import io

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <module.ko> [dep1] [dep2] ...", file=sys.stderr)
        sys.exit(1)

    ko_path = sys.argv[1]
    strip_deps = set(sys.argv[2:])

    with open(ko_path, 'rb') as f:
        data = bytearray(f.read())

    # ELF header: EI_MAG (4), EI_CLASS (1), EI_DATA (1), ...
    if data[:4] != b'\x7fELF':
        print(f"Not an ELF file: {ko_path}", file=sys.stderr)
        sys.exit(1)

    # Determine endianness and word size
    is_64bit = data[4] == 2  # EI_CLASS: 1=32bit, 2=64bit
    is_le = data[5] == 1     # EI_DATA: 1=LE, 2=BE
    endian = '<' if is_le else '>'

    # Parse ELF header to find section headers
    if is_64bit:
        # 64-bit ELF header
        e_shoff = struct.unpack_from(endian + 'Q', data, 0x28)[0]
        e_shentsize = struct.unpack_from(endian + 'H', data, 0x3A)[0]
        e_shnum = struct.unpack_from(endian + 'H', data, 0x3C)[0]
        e_shstrndx = struct.unpack_from(endian + 'H', data, 0x3E)[0]
        sh_name_offset = 0
        sh_type_offset = 4
        sh_offset_offset = 0x18
        sh_size_offset = 0x20
        sh_link_offset = 0x28
        sh_entsize_offset = 0x38
    else:
        # 32-bit ELF header
        e_shoff = struct.unpack_from(endian + 'I', data, 0x20)[0]
        e_shentsize = struct.unpack_from(endian + 'H', data, 0x2E)[0]
        e_shnum = struct.unpack_from(endian + 'H', data, 0x30)[0]
        e_shstrndx = struct.unpack_from(endian + 'H', data, 0x32)[0]
        sh_name_offset = 0
        sh_type_offset = 4
        sh_offset_offset = 0x10
        sh_size_offset = 0x14
        sh_link_offset = 0x18
        sh_entsize_offset = 0x28

    # Read section name string table
    shstrtab_hdr_off = e_shoff + e_shstrndx * e_shentsize
    shstrtab_off = struct.unpack_from(endian + 'I', data, shstrtab_hdr_off + sh_offset_offset)[0]
    shstrtab_size = struct.unpack_from(endian + 'I', data, shstrtab_hdr_off + sh_size_offset)[0]
    shstrtab = data[shstrtab_off:shstrtab_off + shstrtab_size]

    # Find .modinfo section
    modinfo_off = None
    modinfo_size = None
    for i in range(e_shnum):
        shdr_off = e_shoff + i * e_shentsize
        name_off = struct.unpack_from(endian + 'I', data, shdr_off + sh_name_offset)[0]
        name = shstrtab[name_off:shstrtab.index(b'\0', name_off)].decode('ascii', errors='replace')
        if name == '.modinfo':
            sh_type = struct.unpack_from(endian + 'I', data, shdr_off + sh_type_offset)[0]
            if sh_type != 1:  # SHT_STRTAB
                print(f"Warning: .modinfo section type is {sh_type}, expected SHT_STRTAB (1)", file=sys.stderr)
            modinfo_off = struct.unpack_from(endian + 'I', data, shdr_off + sh_offset_offset)[0]
            modinfo_size = struct.unpack_from(endian + 'I', data, shdr_off + sh_size_offset)[0]
            break

    if modinfo_off is None:
        print(f"No .modinfo section found in {ko_path}", file=sys.stderr)
        sys.exit(1)

    modinfo_data = data[modinfo_off:modinfo_off + modinfo_size]

    # Parse modinfo entries (null-terminated key=value pairs)
    new_modinfo = bytearray()
    found = False
    pos = 0
    while pos < len(modinfo_data):
        end = modinfo_data.find(b'\0', pos)
        if end == -1:
            break
        entry = modinfo_data[pos:end]
        pos = end + 1

        if entry.startswith(b'depends='):
            depends = entry[len(b'depends='):].decode('ascii', errors='replace')
            deps = [d.strip() for d in depends.split(',') if d.strip()]
            original_deps = list(deps)
            deps = [d for d in deps if d not in strip_deps]

            if deps != original_deps:
                found = True
                new_depends = ','.join(deps)
                print(f"  Modinfo depends: '{depends}' → '{new_depends}'")
                new_entry = f"depends={new_depends}".encode('ascii')
                new_modinfo.extend(new_entry)

                # If entry was shorter, pad with nulls to preserve alignment
                if len(new_entry) < len(entry):
                    new_modinfo.extend(b'\0' * (len(entry) - len(new_entry)))
                else:
                    new_modinfo.extend(b'\0')
            else:
                new_modinfo.extend(entry)
                new_modinfo.extend(b'\0')
        else:
            new_modinfo.extend(entry)
            new_modinfo.extend(b'\0')

    # Pad to original size
    if len(new_modinfo) < modinfo_size:
        new_modinfo.extend(b'\0' * (modinfo_size - len(new_modinfo)))
    elif len(new_modinfo) > modinfo_size:
        # Truncate or write beyond — shouldn't happen but handle gracefully
        new_modinfo = new_modinfo[:modinfo_size]

    # Write back to file
    data[modinfo_off:modinfo_off + modinfo_size] = new_modinfo

    with open(ko_path, 'wb') as f:
        f.write(data)

    if found:
        print(f"  ✓ Patched {ko_path}")
    else:
        print(f"  - No matching deps found in {ko_path}")

if __name__ == '__main__':
    main()
