#include "greeter.h"

namespace demo {

std::string Greeter::greet() const { return "Hello, " + name_ + "!"; }

} // namespace demo
