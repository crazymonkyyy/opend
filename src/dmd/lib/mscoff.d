/**
 * A library in the COFF format, used on 32-bit and 64-bit Windows targets.
 *
 * Copyright:   Copyright (C) 1999-2021 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/lib/mscoff.d, _mscoff.d)
 * Documentation:  https://dlang.org/phobos/dmd_lib_mscoff.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/lib/mscoff.d
 */

module dmd.lib.mscoff;

import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.time;
import core.stdc.stdio;
import core.stdc.string;

version (Posix)
{
    import core.sys.posix.sys.stat;
    import core.sys.posix.unistd;
}
version (Windows)
{
    import core.sys.windows.stat;
}

import dmd.globals;
import dmd.lib;
import dmd.utils;

import dmd.root.array;
import dmd.root.file;
import dmd.root.filename;
import dmd.root.outbuffer;
import dmd.root.port;
import dmd.root.rmem;
import dmd.root.string;
import dmd.root.stringtable;

import dmd.lib.scanmscoff;

// Entry point (only public symbol in this module).
package extern (C++) Library LibMSCoff_factory()
{
    return new LibMSCoff();
}

private: // for the remainder of this module

enum LOG = false;

struct MSCoffObjSymbol
{
    const(char)[] name;         // still has a terminating 0
    MSCoffObjModule* om;

    /// Predicate for `Array.sort`for name comparison
    static int name_pred (scope const MSCoffObjSymbol** ppe1, scope const MSCoffObjSymbol** ppe2) nothrow @nogc pure
    {
        return dstrcmp((**ppe1).name, (**ppe2).name);
    }

    /// Predicate for `Array.sort`for offset comparison
    static int offset_pred (scope const MSCoffObjSymbol** ppe1, scope const MSCoffObjSymbol** ppe2) nothrow @nogc pure
    {
        return (**ppe1).om.offset - (**ppe2).om.offset;
    }
}

alias MSCoffObjModules = Array!(MSCoffObjModule*);
alias MSCoffObjSymbols = Array!(MSCoffObjSymbol*);

final class LibMSCoff : Library
{
    MSCoffObjModules objmodules; // MSCoffObjModule[]
    MSCoffObjSymbols objsymbols; // MSCoffObjSymbol[]

    /***************************************
     * Add object module or library to the library.
     * Examine the buffer to see which it is.
     * If the buffer is NULL, use module_name as the file name
     * and load the file.
     */
    override void addObject(const(char)[] module_name, const ubyte[] buffer)
    {
        static if (LOG)
        {
            printf("LibMSCoff::addObject(%.*s)\n", cast(int)module_name.length,
                   module_name.ptr);
        }

        void corrupt(int reason)
        {
            error("corrupt MS Coff object module %.*s %d",
                  cast(int)module_name.length, module_name.ptr, reason);
        }

        int fromfile = 0;
        auto buf = buffer.ptr;
        auto buflen = buffer.length;
        if (!buf)
        {
            assert(module_name.length, "No module nor buffer provided to `addObject`");
            // read file and take buffer ownership
            auto data = readFile(Loc.initial, module_name).extractSlice();
            buf = data.ptr;
            buflen = data.length;
            fromfile = 1;
        }
        if (buflen < 16)
        {
            static if (LOG)
            {
                printf("buf = %p, buflen = %d\n", buf, buflen);
            }
            return corrupt(__LINE__);
        }
        if (memcmp(buf, "!<arch>\n".ptr, 8) == 0)
        {
            /* It's a library file.
             * Pull each object module out of the library and add it
             * to the object module array.
             */
            static if (LOG)
            {
                printf("archive, buf = %p, buflen = %d\n", buf, buflen);
            }
            MSCoffLibHeader* flm = null; // first linker member
            MSCoffLibHeader* slm = null; // second linker member
            uint number_of_members = 0;
            uint* member_file_offsets = null;
            uint number_of_symbols = 0;
            ushort* indices = null;
            char* string_table = null;
            size_t string_table_length = 0;
            MSCoffLibHeader* lnm = null; // longname member
            char* longnames = null;
            size_t longnames_length = 0;
            size_t offset = 8;
            size_t mstart = objmodules.dim;
            while (1)
            {
                offset = (offset + 1) & ~1; // round to even boundary
                if (offset >= buflen)
                    break;
                if (offset + MSCoffLibHeader.sizeof >= buflen)
                    return corrupt(__LINE__);
                MSCoffLibHeader* header = cast(MSCoffLibHeader*)(cast(ubyte*)buf + offset);
                offset += MSCoffLibHeader.sizeof;
                char* endptr = null;
                uint size = cast(uint)strtoul(cast(char*)header.file_size, &endptr, 10);
                if (endptr >= header.file_size.ptr + 10 || *endptr != ' ')
                    return corrupt(__LINE__);
                if (offset + size > buflen)
                    return corrupt(__LINE__);
                //printf("header.object_name = '%.*s'\n", cast(int)MSCOFF_OBJECT_NAME_SIZE, header.object_name);
                if (memcmp(cast(char*)header.object_name, cast(char*)"/               ", MSCOFF_OBJECT_NAME_SIZE) == 0)
                {
                    if (!flm)
                    {
                        // First Linker Member, which is ignored
                        flm = header;
                    }
                    else if (!slm)
                    {
                        // Second Linker Member, which we require even though the format doesn't require it
                        slm = header;
                        if (size < 4 + 4)
                            return corrupt(__LINE__);
                        number_of_members = Port.readlongLE(cast(char*)buf + offset);
                        member_file_offsets = cast(uint*)(cast(char*)buf + offset + 4);
                        if (size < 4 + number_of_members * 4 + 4)
                            return corrupt(__LINE__);
                        number_of_symbols = Port.readlongLE(cast(char*)buf + offset + 4 + number_of_members * 4);
                        indices = cast(ushort*)(cast(char*)buf + offset + 4 + number_of_members * 4 + 4);
                        string_table = cast(char*)(cast(char*)buf + offset + 4 + number_of_members * 4 + 4 + number_of_symbols * 2);
                        if (size <= (4 + number_of_members * 4 + 4 + number_of_symbols * 2))
                            return corrupt(__LINE__);
                        string_table_length = size - (4 + number_of_members * 4 + 4 + number_of_symbols * 2);
                        /* The number of strings in the string_table must be number_of_symbols; check it
                         * The strings must also be in ascending lexical order; not checked.
                         */
                        size_t i = 0;
                        for (uint n = 0; n < number_of_symbols; n++)
                        {
                            while (1)
                            {
                                if (i >= string_table_length)
                                    return corrupt(__LINE__);
                                if (!string_table[i++])
                                    break;
                            }
                        }
                        if (i != string_table_length)
                            return corrupt(__LINE__);
                    }
                }
                else if (memcmp(cast(char*)header.object_name, cast(char*)"//              ", MSCOFF_OBJECT_NAME_SIZE) == 0)
                {
                    if (!lnm)
                    {
                        lnm = header;
                        longnames = cast(char*)buf + offset;
                        longnames_length = size;
                    }
                }
                else
                {
                    if (!slm)
                        return corrupt(__LINE__);
                    version (none)
                    {
                        // Microsoft Spec says longnames member must appear, but Microsoft Lib says otherwise
                        if (!lnm)
                            return corrupt(__LINE__);
                    }
                    auto om = new MSCoffObjModule();
                    // Include MSCoffLibHeader in base[0..length], so we don't have to repro it
                    om.base = cast(ubyte*)buf + offset - MSCoffLibHeader.sizeof;
                    om.length = cast(uint)(size + MSCoffLibHeader.sizeof);
                    om.offset = 0;
                    if (header.object_name[0] == '/')
                    {
                        /* Pick long name out of longnames[]
                         */
                        uint foff = cast(uint)strtoul(cast(char*)header.object_name + 1, &endptr, 10);
                        uint i;
                        for (i = 0; 1; i++)
                        {
                            if (foff + i >= longnames_length)
                                return corrupt(__LINE__);
                            char c = longnames[foff + i];
                            if (c == 0)
                                break;
                        }
                        char* oname = cast(char*)Mem.check(malloc(i + 1));
                        memcpy(oname, longnames + foff, i);
                        oname[i] = 0;
                        om.name = oname[0 .. i];
                        //printf("\tname = '%s'\n", om.name);
                    }
                    else
                    {
                        /* Pick short name out of header
                         */
                        char* oname = cast(char*)Mem.check(malloc(MSCOFF_OBJECT_NAME_SIZE));
                        int i;
                        for (i = 0; 1; i++)
                        {
                            if (i == MSCOFF_OBJECT_NAME_SIZE)
                                return corrupt(__LINE__);
                            char c = header.object_name[i];
                            if (c == '/')
                            {
                                oname[i] = 0;
                                break;
                            }
                            oname[i] = c;
                        }
                        om.name = oname[0 .. i];
                    }
                    om.file_time = strtoul(cast(char*)header.file_time, &endptr, 10);
                    om.user_id = cast(uint)strtoul(cast(char*)header.user_id, &endptr, 10);
                    om.group_id = cast(uint)strtoul(cast(char*)header.group_id, &endptr, 10);
                    om.file_mode = cast(uint)strtoul(cast(char*)header.file_mode, &endptr, 8);
                    om.scan = 0; // don't scan object module for symbols
                    objmodules.push(om);
                }
                offset += size;
            }
            if (offset != buflen)
                return corrupt(__LINE__);
            /* Scan the library's symbol table, and insert it into our own.
             * We use this instead of rescanning the object module, because
             * the library's creator may have a different idea of what symbols
             * go into the symbol table than we do.
             * This is also probably faster.
             */
            if (!slm)
                return corrupt(__LINE__);
            char* s = string_table;
            for (uint i = 0; i < number_of_symbols; i++)
            {
                const(char)[] name = s.toDString();
                s += name.length + 1;
                uint memi = indices[i] - 1;
                if (memi >= number_of_members)
                    return corrupt(__LINE__);
                uint moff = member_file_offsets[memi];
                for (size_t m = mstart; 1; m++)
                {
                    if (m == objmodules.dim)
                        return corrupt(__LINE__);       // didn't find it
                    MSCoffObjModule* om = objmodules[m];
                    //printf("\tom offset = x%x\n", (char *)om.base - (char *)buf);
                    if (moff == cast(char*)om.base - cast(char*)buf)
                    {
                        addSymbol(om, name, 1);
                        //if (mstart == m)
                        //    mstart++;
                        break;
                    }
                }
            }
            return;
        }
        /* It's an object module
         */
        auto om = new MSCoffObjModule();
        om.base = cast(ubyte*)buf;
        om.length = cast(uint)buflen;
        om.offset = 0;
        // remove path, but not extension
        om.name = global.params.preservePaths ? module_name : FileName.name(module_name);
        om.scan = 1;
        if (fromfile)
        {
            version (Posix)
                stat_t statbuf;
            version (Windows)
                struct_stat statbuf;
            int i = module_name.toCStringThen!(name => stat(name.ptr, &statbuf));
            if (i == -1) // error, errno is set
                return corrupt(__LINE__);
            om.file_time = statbuf.st_ctime;
            om.user_id = statbuf.st_uid;
            om.group_id = statbuf.st_gid;
            om.file_mode = statbuf.st_mode;
        }
        else
        {
            /* Mock things up for the object module file that never was
             * actually written out.
             */
            version (Posix)
            {
                __gshared uid_t uid;
                __gshared gid_t gid;
                __gshared int _init;
                if (!_init)
                {
                    _init = 1;
                    uid = getuid();
                    gid = getgid();
                }
                om.user_id = uid;
                om.group_id = gid;
            }
            version (Windows)
            {
                om.user_id = 0; // meaningless on Windows
                om.group_id = 0;        // meaningless on Windows
            }
            time_t file_time = 0;
            time(&file_time);
            om.file_time = cast(long)file_time;
            om.file_mode = (1 << 15) | (6 << 6) | (4 << 3) | (4 << 0); // 0100644
        }
        objmodules.push(om);
    }

    /*****************************************************************************/

    void addSymbol(MSCoffObjModule* om, const(char)[] name, int pickAny = 0)
    {
        static if (LOG)
        {
            printf("LibMSCoff::addSymbol(%s, %s, %d)\n", om.name.ptr, name, pickAny);
        }
        auto os = new MSCoffObjSymbol();
        os.name = xarraydup(name);
        os.om = om;
        objsymbols.push(os);
    }

private:
    /************************************
     * Scan single object module for dictionary symbols.
     * Send those symbols to LibMSCoff::addSymbol().
     */
    void scanObjModule(MSCoffObjModule* om)
    {
        static if (LOG)
        {
            printf("LibMSCoff::scanObjModule(%s)\n", om.name.ptr);
        }

        extern (D) void addSymbol(const(char)[] name, int pickAny)
        {
            this.addSymbol(om, name, pickAny);
        }

        scanMSCoffObjModule(&addSymbol, om.base[0 .. om.length], om.name.ptr, loc);
    }

    /*****************************************************************************/
    /*****************************************************************************/
    /**********************************************
     * Create and write library to libbuf.
     * The library consists of:
     *      !<arch>\n
     *      header
     *      1st Linker Member
     *      Header
     *      2nd Linker Member
     *      Header
     *      Longnames Member
     *      object modules...
     */
    protected override void WriteLibToBuffer(OutBuffer* libbuf)
    {
        static if (LOG)
        {
            printf("LibElf::WriteLibToBuffer()\n");
        }
        assert(MSCoffLibHeader.sizeof == 60);
        /************* Scan Object Modules for Symbols ******************/
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om = objmodules[i];
            if (om.scan)
            {
                scanObjModule(om);
            }
        }
        /************* Determine longnames size ******************/
        /* The longnames section is where we store long file names.
         */
        uint noffset = 0;
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om = objmodules[i];
            size_t len = om.name.length;
            if (len >= MSCOFF_OBJECT_NAME_SIZE)
            {
                om.name_offset = noffset;
                noffset += len + 1;
            }
            else
                om.name_offset = -1;
        }
        static if (LOG)
        {
            printf("\tnoffset = x%x\n", noffset);
        }
        /************* Determine string table length ******************/
        size_t slength = 0;
        for (size_t i = 0; i < objsymbols.dim; i++)
        {
            MSCoffObjSymbol* os = objsymbols[i];
            slength += os.name.length + 1;
        }
        /************* Offset of first module ***********************/
        size_t moffset = 8; // signature
        size_t firstLinkerMemberOffset = moffset;
        moffset += MSCoffLibHeader.sizeof + 4 + objsymbols.dim * 4 + slength; // 1st Linker Member
        moffset += moffset & 1;
        size_t secondLinkerMemberOffset = moffset;
        moffset += MSCoffLibHeader.sizeof + 4 + objmodules.dim * 4 + 4 + objsymbols.dim * 2 + slength;
        moffset += moffset & 1;
        size_t LongnamesMemberOffset = moffset;
        moffset += MSCoffLibHeader.sizeof + noffset; // Longnames Member size
        static if (LOG)
        {
            printf("\tmoffset = x%x\n", moffset);
        }
        /************* Offset of each module *************************/
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om = objmodules[i];
            moffset += moffset & 1;
            om.offset = cast(uint)moffset;
            if (om.scan)
                moffset += MSCoffLibHeader.sizeof + om.length;
            else
                moffset += om.length;
        }
        libbuf.reserve(moffset);
        /************* Write the library ******************/
        libbuf.write("!<arch>\n");
        MSCoffObjModule om;
        om.name_offset = -1;
        om.base = null;
        om.length = cast(uint)(4 + objsymbols.dim * 4 + slength);
        om.offset = 8;
        om.name = "";
        time_t file_time = 0;
        .time(&file_time);
        om.file_time = cast(long)file_time;
        om.user_id = 0;
        om.group_id = 0;
        om.file_mode = 0;
        /*** Write out First Linker Member ***/
        assert(libbuf.length == firstLinkerMemberOffset);
        MSCoffLibHeader h;
        MSCoffOmToHeader(&h, &om);
        libbuf.write((&h)[0 .. 1]);
        char[4] buf;
        Port.writelongBE(cast(uint)objsymbols.dim, buf.ptr);
        libbuf.write(buf[0 .. 4]);
        // Sort objsymbols[] in module offset order
        objsymbols.sort!(MSCoffObjSymbol.offset_pred);
        uint lastoffset;
        for (size_t i = 0; i < objsymbols.dim; i++)
        {
            MSCoffObjSymbol* os = objsymbols[i];
            //printf("objsymbols[%d] = '%s', offset = %u\n", i, os.name, os.om.offset);
            if (i)
            {
                // Should be sorted in module order
                assert(lastoffset <= os.om.offset);
            }
            lastoffset = os.om.offset;
            Port.writelongBE(lastoffset, buf.ptr);
            libbuf.write(buf[0 .. 4]);
        }
        for (size_t i = 0; i < objsymbols.dim; i++)
        {
            MSCoffObjSymbol* os = objsymbols[i];
            libbuf.writestring(os.name);
            libbuf.writeByte(0);
        }
        /*** Write out Second Linker Member ***/
        if (libbuf.length & 1)
            libbuf.writeByte('\n');
        assert(libbuf.length == secondLinkerMemberOffset);
        om.length = cast(uint)(4 + objmodules.dim * 4 + 4 + objsymbols.dim * 2 + slength);
        MSCoffOmToHeader(&h, &om);
        libbuf.write((&h)[0 .. 1]);
        Port.writelongLE(cast(uint)objmodules.dim, buf.ptr);
        libbuf.write(buf[0 .. 4]);
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om2 = objmodules[i];
            om2.index = cast(ushort)i;
            Port.writelongLE(om2.offset, buf.ptr);
            libbuf.write(buf[0 .. 4]);
        }
        Port.writelongLE(cast(uint)objsymbols.dim, buf.ptr);
        libbuf.write(buf[0 .. 4]);
        // Sort objsymbols[] in lexical order
        objsymbols.sort!(MSCoffObjSymbol.name_pred);
        for (size_t i = 0; i < objsymbols.dim; i++)
        {
            MSCoffObjSymbol* os = objsymbols[i];
            Port.writelongLE(os.om.index + 1, buf.ptr);
            libbuf.write(buf[0 .. 2]);
        }
        for (size_t i = 0; i < objsymbols.dim; i++)
        {
            MSCoffObjSymbol* os = objsymbols[i];
            libbuf.writestring(os.name);
            libbuf.writeByte(0);
        }
        /*** Write out longnames Member ***/
        if (libbuf.length & 1)
            libbuf.writeByte('\n');
        //printf("libbuf %x longnames %x\n", (int)libbuf.length, (int)LongnamesMemberOffset);
        assert(libbuf.length == LongnamesMemberOffset);
        // header
        memset(&h, ' ', MSCoffLibHeader.sizeof);
        h.object_name[0] = '/';
        h.object_name[1] = '/';
        size_t len = sprintf(h.file_size.ptr, "%u", noffset);
        assert(len < 10);
        h.file_size[len] = ' ';
        h.trailer[0] = '`';
        h.trailer[1] = '\n';
        libbuf.write((&h)[0 .. 1]);
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om2 = objmodules[i];
            if (om2.name_offset >= 0)
            {
                libbuf.writestring(om2.name);
                libbuf.writeByte(0);
            }
        }
        /* Write out each of the object modules
         */
        for (size_t i = 0; i < objmodules.dim; i++)
        {
            MSCoffObjModule* om2 = objmodules[i];
            if (libbuf.length & 1)
                libbuf.writeByte('\n'); // module alignment
            //printf("libbuf %x om %x\n", (int)libbuf.length, (int)om2.offset);
            assert(libbuf.length == om2.offset);
            if (om2.scan)
            {
                MSCoffOmToHeader(&h, om2);
                libbuf.write((&h)[0 .. 1]); // module header
                libbuf.write(om2.base[0 .. om2.length]); // module contents
            }
            else
            {
                // Header is included in om.base[0..length]
                libbuf.write(om2.base[0 .. om2.length]); // module contents
            }
        }
        static if (LOG)
        {
            printf("moffset = x%x, libbuf.length = x%x\n", cast(uint)moffset, cast(uint)libbuf.length);
        }
        assert(libbuf.length == moffset);
    }
}

/*****************************************************************************/
/*****************************************************************************/
struct MSCoffObjModule
{
    ubyte* base; // where are we holding it in memory
    uint length; // in bytes
    uint offset; // offset from start of library
    ushort index; // index in Second Linker Member
    const(char)[] name; // module name (file name) terminated with 0
    int name_offset; // if not -1, offset into string table of name
    long file_time; // file time
    uint user_id;
    uint group_id;
    uint file_mode;
    int scan; // 1 means scan for symbols
}

enum MSCOFF_OBJECT_NAME_SIZE = 16;

struct MSCoffLibHeader
{
    char[MSCOFF_OBJECT_NAME_SIZE] object_name;
    char[12] file_time;
    char[6] user_id;
    char[6] group_id;
    char[8] file_mode; // in octal
    char[10] file_size;
    char[2] trailer;
}

extern (C++) void MSCoffOmToHeader(MSCoffLibHeader* h, MSCoffObjModule* om)
{
    size_t len;
    if (om.name_offset == -1)
    {
        len = om.name.length;
        memcpy(h.object_name.ptr, om.name.ptr, len);
        h.object_name[len] = '/';
    }
    else
    {
        len = sprintf(h.object_name.ptr, "/%d", om.name_offset);
        h.object_name[len] = ' ';
    }
    assert(len < MSCOFF_OBJECT_NAME_SIZE);
    memset(h.object_name.ptr + len + 1, ' ', MSCOFF_OBJECT_NAME_SIZE - (len + 1));
    /* In the following sprintf's, don't worry if the trailing 0
     * that sprintf writes goes off the end of the field. It will
     * write into the next field, which we will promptly overwrite
     * anyway. (So make sure to write the fields in ascending order.)
     */
    len = sprintf(h.file_time.ptr, "%llu", cast(long)om.file_time);
    assert(len <= 12);
    memset(h.file_time.ptr + len, ' ', 12 - len);
    // Match what MS tools do (set to all blanks)
    memset(h.user_id.ptr, ' ', (h.user_id).sizeof);
    memset(h.group_id.ptr, ' ', (h.group_id).sizeof);
    len = sprintf(h.file_mode.ptr, "%o", om.file_mode);
    assert(len <= 8);
    memset(h.file_mode.ptr + len, ' ', 8 - len);
    len = sprintf(h.file_size.ptr, "%u", om.length);
    assert(len <= 10);
    memset(h.file_size.ptr + len, ' ', 10 - len);
    h.trailer[0] = '`';
    h.trailer[1] = '\n';
}
