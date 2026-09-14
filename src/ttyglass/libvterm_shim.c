#include "libvterm_shim.h"

#include <stdlib.h>

#include "../../vendor/libvterm/include/vterm.h"

struct TtyglassVTerm {
  VTerm *terminal;
  VTermState *state;
  VTermScreen *screen;
  VTermPos cursor;
  int cursor_visible;
};

static int ttyglass_move_cursor(
    VTermPos position,
    VTermPos old_position,
    int visible,
    void *user) {
  TtyglassVTerm *terminal = user;
  (void)old_position;
  terminal->cursor = position;
  terminal->cursor_visible = visible;
  return 1;
}

static int ttyglass_set_term_property(
    VTermProp property,
    VTermValue *value,
    void *user) {
  TtyglassVTerm *terminal = user;
  if (property == VTERM_PROP_CURSORVISIBLE) {
    terminal->cursor_visible = value->boolean;
    return 1;
  }
  return 0;
}

static const VTermScreenCallbacks ttyglass_screen_callbacks = {
    .movecursor = ttyglass_move_cursor,
    .settermprop = ttyglass_set_term_property,
};

TtyglassVTerm *ttyglass_vterm_new(int cols, int rows) {
  TtyglassVTerm *result = calloc(1, sizeof(TtyglassVTerm));
  if (result == NULL) {
    return NULL;
  }

  result->terminal = vterm_new(rows, cols);
  if (result->terminal == NULL) {
    free(result);
    return NULL;
  }

  result->cursor_visible = 1;
  vterm_set_utf8(result->terminal, 1);
  result->state = vterm_obtain_state(result->terminal);
  result->screen = vterm_obtain_screen(result->terminal);
  vterm_screen_set_callbacks(
      result->screen,
      &ttyglass_screen_callbacks,
      result);
  vterm_screen_enable_altscreen(result->screen, 1);
  vterm_screen_reset(result->screen, 1);
  vterm_state_get_cursorpos(result->state, &result->cursor);
  return result;
}

void ttyglass_vterm_free(TtyglassVTerm *terminal) {
  if (terminal == NULL) {
    return;
  }
  vterm_free(terminal->terminal);
  free(terminal);
}

void ttyglass_vterm_write(TtyglassVTerm *terminal, const char *bytes, size_t length) {
  if (terminal == NULL || bytes == NULL || length == 0) {
    return;
  }
  vterm_input_write(terminal->terminal, bytes, length);
  vterm_screen_flush_damage(terminal->screen);
  vterm_state_get_cursorpos(terminal->state, &terminal->cursor);
}

void ttyglass_vterm_resize(TtyglassVTerm *terminal, int cols, int rows) {
  if (terminal == NULL) {
    return;
  }
  vterm_set_size(terminal->terminal, rows, cols);
  vterm_screen_flush_damage(terminal->screen);
  vterm_state_get_cursorpos(terminal->state, &terminal->cursor);
}

void ttyglass_vterm_cursor(
    const TtyglassVTerm *terminal,
    int *row,
    int *col,
    int *visible) {
  if (terminal == NULL) {
    return;
  }
  *row = terminal->cursor.row;
  *col = terminal->cursor.col;
  *visible = terminal->cursor_visible;
}

int ttyglass_vterm_cell(
    const TtyglassVTerm *terminal,
    int row,
    int col,
    uint32_t *codepoints,
    int capacity,
    int *width) {
  VTermScreenCell cell;
  VTermPos position = {.row = row, .col = col};
  int count = 0;

  if (terminal == NULL || capacity <= 0 ||
      !vterm_screen_get_cell(terminal->screen, position, &cell)) {
    return 0;
  }

  *width = cell.width;
  while (count < capacity && count < VTERM_MAX_CHARS_PER_CELL &&
         cell.chars[count] != 0) {
    codepoints[count] = cell.chars[count];
    count++;
  }
  return count;
}
