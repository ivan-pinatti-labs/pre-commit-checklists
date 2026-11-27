// A C++ class in a .h header. cppcheck parses .h as C unless told
// otherwise, and would report the namespace below as a syntaxError, so
// this file fails the suite if checklist-dev-cpp stops passing
// --language=c++ for headers.
#pragma once

#include <string>
#include <utility>

namespace demo {

class Greeter {
public:
  explicit Greeter(std::string name) : name_(std::move(name)) {}
  std::string greet() const;

private:
  std::string name_;
};

} // namespace demo
