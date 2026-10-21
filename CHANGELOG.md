# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html). Every merge to `main` is
published as release `v<version>-<build>`; this file lists changes by version.

<!-- textlint-disable -->

## [Unreleased]

### Added

- Open source project files based on the Cisco OSS template: license, code of
  conduct, contributing and security policies, issue and pull request templates,
  Dependabot, lint, dependency review and stale workflows.

## [1.0] - 2026-10-16

### Added

- Create, rename and delete keys and values of all common types, with editors
  for strings, multi-strings, DWORD/QWORD and binary data (#13).
- Find across key names, value names and data (#13).
- Export to and import from Windows `regedit` compatible `.reg` files (#13).
- Automatic backup of the database before the first change, live refresh when
  Office changes it, and a warning while Office apps are running (#13).
- Universal DMG built and published as a GitHub release on every merge to
  `main` (#15).

### Changed

- Rewrote the data layer and the SwiftUI interface (#13).
- Requires macOS 15 or later (#17).
- Migrated to Swift 6 and SQLite.swift 0.16.0 (#14).

### Fixed

- Hexadecimal rendering of QWORD values (#1).

[unreleased]: https://github.com/slidoapp/MacOfficeRegedit/compare/v1.0-7...HEAD
[1.0]: https://github.com/slidoapp/MacOfficeRegedit/releases/tag/v1.0-7

<!-- textlint-enable -->
