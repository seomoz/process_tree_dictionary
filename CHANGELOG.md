### 1.0.2 / 2017-06-15
[Full Changelog](https://github.com/seomoz/process_tree_dictionary/compare/v1.0.1...v1.0.2)

Bug Fixes:

* Fix all `ProcessTreeDictionary` operations to be tolerant of the
  process tree dictionary process no longer being up. When that happens,
  it logs a warning and the fallback callback is used.

### 1.0.1 / 2016-09-27
[Full Changelog](https://github.com/seomoz/process_tree_dictionary/compare/v1.0.0...v1.0.1)

Bug Fixes:

* Fix bug in `ProcessTreeDictionary.update!/2` that allowed it to crash
  when given an unrecognized key path.

### 1.0.0 / 2016-09-15

Initial release.
