// imports.c: print the import table of a 64-bit Windows exe or dll.
// This only reads the regular import table, not delay-loaded imports.
//   cl imports.c
//   zig cc imports.c -o imports.exe
#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static const char *path;
static FILE *file;
static uint32_t section_count, sections;

static void die(const char *msg) {
    fprintf(stderr, "%s: %s\n", path, msg);
    exit(1);
}

static uint64_t read_le(uint32_t offset, int size) {
    uint8_t b[8];
    if (fseek(file, offset, SEEK_SET) != 0 || fread(b, 1, size, file) != (size_t)size)
        die("unexpected end of file");
    uint64_t value = 0;
    for (int i = size - 1; i >= 0; i--) value = value << 8 | b[i];
    return value;
}

// Tables in a PE file refer to each other by RVA, an offset from wherever the
// image gets loaded. The section headers say where each range is in the file.
static uint32_t rva_to_offset(uint32_t rva) {
    for (uint32_t i = 0; i < section_count; i++) {
        uint32_t section = sections + i * 40;
        uint32_t start = (uint32_t)read_le(section + 12, 4);
        uint32_t size = (uint32_t)read_le(section + 16, 4);
        if (rva >= start && rva < start + size)
            return (uint32_t)read_le(section + 20, 4) + rva - start;
    }
    die("RVA is outside of every section");
    return 0;
}

static void print_string(uint32_t offset) {
    if (fseek(file, offset, SEEK_SET) != 0) die("unexpected end of file");
    for (;;) {
        int c = fgetc(file);
        if (c == EOF) die("unexpected end of file");
        if (c == 0) break;
        putchar(c);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: imports FILE\n");
        return 1;
    }
    path = argv[1];
    file = fopen(path, "rb");
    if (!file) die("failed to open file");

    if (read_le(0, 2) != 0x5a4d) die("not a PE file (missing MZ)");
    uint32_t pe = (uint32_t)read_le(0x3c, 4);
    if (read_le(pe, 4) != 0x00004550) die("not a PE file (missing PE signature)");
    section_count = (uint32_t)read_le(pe + 6, 2);
    uint32_t optional = pe + 24;
    sections = optional + (uint32_t)read_le(pe + 20, 2);
    if (read_le(optional, 2) != 0x20b) die("not a 64-bit binary");

    if (read_le(optional + 108, 4) < 2) return 0; // no import directory
    uint32_t import_rva = (uint32_t)read_le(optional + 120, 4);
    if (import_rva == 0) return 0;

    // One 20-byte record per DLL, ending with a record of all zeros.
    for (uint32_t i = 0;; i++) {
        uint32_t record = rva_to_offset(import_rva + i * 20);
        uint32_t lookup = (uint32_t)read_le(record, 4);
        uint32_t name = (uint32_t)read_le(record + 12, 4);
        uint32_t address = (uint32_t)read_le(record + 16, 4);
        if (lookup == 0 && name == 0 && address == 0) break;

        print_string(rva_to_offset(name));
        putchar('\n');

        // One 8-byte entry per function, ending with a zero entry.
        uint32_t table = rva_to_offset(lookup ? lookup : address);
        for (uint32_t j = 0;; j++) {
            uint64_t entry = read_le(table + j * 8, 8);
            if (entry == 0) break;
            if (entry >> 63) {
                printf("    ordinal %u\n", (unsigned)(entry & 0xffff));
            } else {
                printf("    ");
                print_string(rva_to_offset((uint32_t)entry) + 2); // skip the hint
                putchar('\n');
            }
        }
    }
    return 0;
}
