## 0.1.0 - 2024-01-12

### Added
- Introduced `EvalReference<T>` class for efficient management of typed references.
- Implemented `findOrCreateEval<T>` function for creating and retrieving `EvalReference` objects.
- Added comprehensive documentation for all public APIs and internal structures.

### Changed
- Renamed `createWeakMap` to `findOrCreateExpando` for better clarity of function purpose.
- Improved implementation of unmarked Expando creation using `EvalReference`.
- Enhanced type safety and efficiency in both marked and unmarked Expando management.

### Improved
- Optimized memory usage by implementing automatic cleanup of unused weak references in `findOrCreateEval`.
- Refined internal logic for better performance and resource management.

### Documentation
- Added detailed inline documentation for `EvalReference`, `findOrCreateEval`, and `findOrCreateExpando`.
- Improved clarity of usage instructions and internal workings in code comments.

### Notes
- This version represents a significant improvement in the package's API and internal implementation.
- While maintaining backwards compatibility, users are encouraged to update to the new `findOrCreateExpando` function.
- The package continues to be designed for internal use in odroe/odroe projects.

## 0.0.1 - 2024-01-11

### Added
- Initial release of the `_octr` package.
- Implemented `createWeakMap<T>` function for creating and managing `Expando` objects.
- Support for both marked and unmarked Expando containers.
- Basic type safety checks for marked containers.

### Features
- Create or retrieve type-specific Expando objects.
- Option to use custom marks for Expando identification.
- Weak reference management for unmarked Expando objects.

### Notes
- This is an internal package used by odroe/odroe projects.
- The implementation is designed for simplicity and does not include explicit thread-safety mechanisms.
