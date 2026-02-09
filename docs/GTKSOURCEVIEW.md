# GtkSourceView Syntax Highlighting for Harding

## Overview

Harding includes a syntax highlighting file for GtkSourceView (used by GNOME applications like Gedit, GNOME Text Editor, and the Harding IDE). This provides syntax highlighting for `.harding` files.

## Installation

### System-wide Installation (requires sudo)

To make Harding syntax highlighting available to all users and applications:

**For GtkSourceView 5 (latest, used by GNOME 45+):**

```bash
sudo cp lib/harding/syntax/harding.lang /usr/share/gtksourceview-5/language-specs/
```

**For GtkSourceView 4 (GNOME 40-44):**

```bash
sudo cp lib/harding/syntax/harding.lang /usr/share/gtksourceview-4/language-specs/
```

For older systems using GtkSourceView 3:

```bash
sudo cp lib/harding/syntax/harding.lang /usr/share/gtksourceview-3.0/language-specs/
```

### User Installation (no sudo required)

To install only for your user:

**For GtkSourceView 5 (latest):**

```bash
mkdir -p ~/.local/share/gtksourceview-5/language-specs/
cp lib/harding/syntax/harding.lang ~/.local/share/gtksourceview-5/language-specs/
```

**For GtkSourceView 4:**

```bash
mkdir -p ~/.local/share/gtksourceview-4/language-specs/
cp lib/harding/syntax/harding.lang ~/.local/share/gtksourceview-4/language-specs/
```

For GtkSourceView 3:

```bash
mkdir -p ~/.local/share/gtksourceview-3.0/language-specs/
cp lib/harding/syntax/harding.lang ~/.local/share/gtksourceview-3.0/language-specs/
```

### Verifying Installation

After installation, restart your text editor. Open a `.harding` file and verify:

1. Comments (`# comment`) are highlighted
2. Strings (`"hello"`) are highlighted
3. Symbols (`#foo`, `#bar:`) are highlighted
4. Keywords (`ifTrue:`, `at:put:`) are highlighted

## Syntax File Location

The syntax file is located at:

```
lib/harding/syntax/harding.lang
```

## Features

The syntax definition provides highlighting for:

| Construct | Example |
|-----------|---------|
| Comments | `# This is a comment` |
| Strings | `"hello world"` |
| Symbols | `#foo`, `#bar:baz:` |
| Numbers | `42`, `3.14` |
| Booleans | `true`, `false` |
| Nil | `nil` |
| Self/Super | `self`, `super` |
| Keywords | `ifTrue:`, `at:put:` |
| Assignment | `:=` |
| Return | `^` |
| Method def | `>>` |
| Arrays | `#(1 2 3)` |
| Tables | `#{"key" -> "value"}` |

## Troubleshooting

**Syntax highlighting not working:**
- Verify the file is in the correct directory for your GtkSourceView version
- Restart your text editor after installation
- Check that the file extension is `.harding`

**Find your GtkSourceView version:**

```bash
pkg-config --modversion gtksourceview-5
```

or for version 4:

```bash
pkg-config --modversion gtksourceview-4
```

or for version 3:

```bash
pkg-config --modversion gtksourceview-3.0
```

## Integration with Harding IDE

The Harding IDE (`bona`) uses GtkSourceView for its source code editor component. The IDE includes:

- **Syntax highlighting** - Automatically uses the `harding.lang` definition when editing `.harding` files
- **Line numbers** - Can be toggled via `showLineNumbers:` method
- **Configurable tab width** - Set via `setTabWidth:` method
- **Do It** (Ctrl+D) - Evaluate selected code and display result in Transcript
- **Print It** (Ctrl+P) - Evaluate and insert result in editor after selection (Smalltalk-style)
  - The result is automatically selected so you can press Delete to remove it
- **Selected text** - Get selected text or current line if nothing selected

To see the IDE in action, run:

```bash
nimble gui
./bona
```
