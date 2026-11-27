// Reads one element past the end of the array: cppcheck reports
// arrayIndexOutOfBounds. Formatted to LLVM style, so the failure is
// cppcheck's and not clang-format's.
int last() {
  int values[4] = {1, 2, 3, 4};
  return values[4];
}
