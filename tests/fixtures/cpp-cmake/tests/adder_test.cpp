#include <cstdlib>

#include "adder.h"

int main() {
  if (add(2, 3) != 5) {
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
