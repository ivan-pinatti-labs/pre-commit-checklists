// Returns without freeing what it allocated: cppcheck reports memleak.
// Formatted to LLVM style, so the failure is cppcheck's and not
// clang-format's.
#include <stdlib.h>

int first(void) {
  int *values = calloc(4, sizeof *values);
  if (values == NULL) {
    return -1;
  }
  return values[0];
}
