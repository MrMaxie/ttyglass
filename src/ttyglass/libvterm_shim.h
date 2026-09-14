#ifndef TTYGLASS_LIBVTERM_SHIM_H
#define TTYGLASS_LIBVTERM_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef struct TtyglassVTerm TtyglassVTerm;

TtyglassVTerm *ttyglass_vterm_new(int cols, int rows);
void ttyglass_vterm_free(TtyglassVTerm *terminal);
void ttyglass_vterm_write(TtyglassVTerm *terminal, const char *bytes, size_t length);
void ttyglass_vterm_resize(TtyglassVTerm *terminal, int cols, int rows);
void ttyglass_vterm_cursor(
    const TtyglassVTerm *terminal,
    int *row,
    int *col,
    int *visible);
int ttyglass_vterm_cell(
    const TtyglassVTerm *terminal,
    int row,
    int col,
    uint32_t *codepoints,
    int capacity,
    int *width);

#endif
