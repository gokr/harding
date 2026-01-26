# Contributing to Nimtalk

Thank you for your interest in contributing to Nimtalk! This document provides guidelines and instructions for contributing.

## Development Environment

1. **Nim**: Ensure you have Nim 2.2.6 or later installed
2. **Git**: Clone the repository and create a branch for your changes
3. **Build Tools**: Nimble for package management

## Development Workflow

1. **Fork and Branch**: Create a feature branch from `master`
2. **Make Changes**: Follow the coding guidelines in [CLAUDE.md](CLAUDE.md)
3. **Test**: Run `nim c -r tests/test_core.nim` to ensure tests pass
4. **Commit**: Write clear, descriptive commit messages
5. **Pull Request**: Submit a PR with explanation of changes

## Code Guidelines

See [CLAUDE.md](CLAUDE.md) for comprehensive Nim coding guidelines, including:

- **Style**: camelCase naming, proper exports
- **Memory Management**: Correct use of var, ref, ptr
- **Threading**: No asyncdispatch, use regular threading
- **Documentation**: Proper doc comments with examples
- **Testing**: All tests must pass, no compiler warnings

## Areas for Contribution

### High Priority
- **FFI Integration**: Calling Nim code from Nimtalk
- **Compiler**: Complete method compilation to Nim
- **Standard Library**: Basic collection objects and utilities

### Medium Priority
- **BitBarrel Integration**: Persistent object storage
- **Tooling**: Editor support, debugger, language server
- **Performance**: Optimizations for interpreter and compiler

### Documentation
- **Examples**: More .nt example files
- **Tutorials**: Step-by-step guides
- **API Documentation**: Generated docs from source

## Communication

- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussion**: GitHub Discussions for design questions
- **Pull Requests**: Code review and feedback

## Code Review Process

1. **Automated Checks**: Tests must pass
2. **Style Review**: Follow CLAUDE.md guidelines
3. **Design Review**: Architectural alignment with project goals
4. **Merge**: After approval, maintainers will merge

Thank you for contributing to making Nimtalk a better language!