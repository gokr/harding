# Multiple Inheritance and Conflict Resolution

Harding's class model supports multiple parents for flexible inheritance. This document explains how conflicts are detected and resolved.

## Multiple Parents

A class can have multiple parent classes:

```smalltalk
# Create two parent classes
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> bar [ ^ "bar2" ]

# Create a child that inherits from both
Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2

# Child now has access to both foo and bar
c := Child new
c foo  # Returns "foo1"
c bar  # Returns "bar2"
```

## Conflict Detection

When adding multiple parents (via `derive:` with multiple parents or `addSuperclass:`), Harding checks for two types of conflicts:

### Slot Name Conflicts

If any slot name (instance variable) exists in multiple parent hierarchies, an error is raised:

```smalltalk
Parent1 := Object derive: #(shared)
Parent2 := Object derive: #(shared)

Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2  # Error: Slot name conflict: 'shared' exists in multiple parents
```

### Method Selector Conflicts

If directly-defined method selectors conflict between parents, an error is raised:

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2  # Error: Method selector conflict: 'foo' exists in existing parent
```

**Important**: Only directly-defined methods on parents are checked for conflicts. Inherited methods (like `derive:` from Object) will not cause false conflicts.

## Resolving Conflicts with addSuperclass:

The `addSuperclass:` message allows adding a parent to an existing class. This is useful for resolving conflicts by overriding the conflicting method first:

```smalltalk
# Define two classes with conflicting methods
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

# Create a child class that overrides the conflicting method
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Add the conflicting parents - this works because child overrides
Child addSuperclass: Parent1
Child addSuperclass: Parent2

result := Child new foo  # Returns "child" (child's override takes precedence)
```

## addSuperclass: Behavior

The `addSuperclass:` message:

1. Checks if the parent is already added (if so, does nothing)
2. Checks for slot name conflicts (only directly-defined slots on the new parent)
3. Checks for method selector conflicts (only if child doesn't override)
4. Inherits instance methods from the new parent (unless child overrides)
5. Inherits class methods from the new parent (unless child overrides)
6. Inherits slot names from the new parent

## Method Lookup Order

When a message is sent to an instance:

1. Look up in the instance's class's `methods` (directly-defined methods)
2. Look up in the instance's class's `allMethods` (merged from all parents)
3. If both parents have the same method, the one from the most recently added parent takes precedence

However, a method defined directly on the child class always takes precedence over inherited methods.

## Example Program

See `examples/test_conflict_detection.harding` for a complete example demonstrating conflict detection and the use of `addSuperclass:` for resolution.

## See Also

- [SPECIFICATION.md](SPECIFICATION.md) - Full language specification
- [NIMTALK_FOR_SMALLTALKERS.md](NIMTALK_FOR_SMALLTALKERS.md) - Guide for Smalltalk developers
