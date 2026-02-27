# Contributing to Harding

Thank you for your interest in contributing to Harding! This document provides guidelines and instructions for contributing.

## Development Environment

1. **Nim**: Ensure you have Nim 2.2.6 or later installed
2. **Git**: Clone the repository and create a branch for your changes
3. **Build Tools**: Nimble for package management and building

## Development Workflow

1. **Fork and Branch**: Create a feature branch from `main`
2. **Make Changes**: Follow the coding guidelines in [CLAUDE.md](CLAUDE.md)
3. **Test**: Run `nimble test` or relevant `tests/test_*.nim` files to ensure changes are covered
4. **Commit**: Write clear, descriptive commit messages
5. **Pull Request**: Submit a PR with explanation of changes

## Code Guidelines

See [CLAUDE.md](CLAUDE.md) for comprehensive Nim coding guidelines, including:

- **Style**: camelCase naming, proper exports
- **Memory Management**: Correct use of var, ref, ptr
- **Threading**: No asyncdispatch, use regular threading
- **Documentation**: Proper doc comments with examples
- **Testing**: All tests must pass, no compiler warnings
