# Tasks: cpuid

- [x] 1. `asm` wrappers for `cpuid`, `rdtsc`, `lfence; rdtsc` and the `keep`/`opaque` barriers
  - _Requirements: 5.4_
- [x] 2. Snapshot of the basic, hypervisor and extended leaves with their subleaves
  - _Requirements: 4.2_
- [x] 3. Decode vendor, brand, signature, hypervisor and address sizes
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
- [x] 4. Feature table and `--has`
  - _Requirements: 1.5, 2.1, 2.2, 2.3, 2.4_
- [x] 5. Cache decoding from leaf 4, 0x8000001D and the legacy AMD leaves
  - _Requirements: 3.1, 3.2, 3.3_
- [x] 6. Raw dump
  - _Requirements: 4.1_
- [x] 7. Benchmark kernels, TSC frequency, report
  - _Requirements: 5.1, 5.2, 5.3_
- [x] 8. Option parsing, help, version, usage errors
  - _Requirements: 6.1, 6.2, 6.3_
- [x] 9. Unit tests (native), end-to-end tests of the binary
  - _Requirements: all_
