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
