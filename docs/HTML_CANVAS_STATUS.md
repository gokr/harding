# HtmlCanvas DSL - Implementation Status

## Current Status: Phase 1 Complete

The HtmlCanvas DSL is **functional and working**. It provides a clean, Seaside-style API for generating HTML in Harding.

### What Works

**1. Basic DSL**
```harding
html canvas: [:h |
  h class: "container"; id: "main".
  h div: [
    h h1: "Title".
    h p: "Content"
  ]
]
# Returns: <div id="main" class="container"><h1>Title</h1><p>Content</p></div>
```

**2. Attribute Cascades**
- `class:` - accumulates multiple classes with space separator
- `id:` - sets element ID
- `style:` - sets inline style
- `attr:value:` - generic attributes
- Nil attributes automatically omitted

**3. Content Types**
- **Strings**: Auto-escaped text content
- **Blocks**: Dynamic content (evaluated immediately, not cached)
- **Raw**: `h << "raw HTML"` or `h raw: "..."`

**4. Supported Tags**
- Container tags: div, span, p, h1-h6, section, article, header, footer, main, aside, nav, ul, ol, li, form, button, label, a, strong, em, b, i, code, pre, blockquote
- Void tags: input, br, hr, img, meta, link (self-closing)

**5. Boolean Attributes**
- `disabled`, `checked`, `selected`, `readonly`, `required`, `autofocus`, `multiple`

### Current Caching (Limited)

The `canvas:with:` method caches the **output string**, not the template structure:

```harding
html canvas: #myTemplate with: [:h |
  h div: [ h h1: "Cached" ]
]
# First call: Builds HTML, caches result
# Subsequent calls: Returns cached HTML string (no re-rendering)
```

**Limitation**: Dynamic content in blocks is evaluated at cache creation time, not at render time.

### What's NOT Implemented (Phase 2)

**1. Template Structure Caching with Re-evaluable Dynamic Content**

The ideal implementation would:
- Cache the template structure (tag hierarchy)
- Store dynamic blocks as closures
- Re-evaluate blocks on each render with fresh data

```harding
# Desired API (NOT YET WORKING):
TodoItem>>renderWith: item [
  html canvas: #todoItem with: [:h |
    h div: [
      h h1: [ item title ].  # Block re-evaluated each render with current item
      h p: [ item description ]
    ]
  ] context: item
]
```

**2. Symbol Selectors for Context Access**

```harding
# Desired API:
html canvas: [:h |
  h div: [
    h h1: #title.  # Would call context title
    h p: #description
  ]
] context: self
```

**3. True Dynamic Content**

Currently, blocks are evaluated immediately when building the template. We need blocks that are stored and re-evaluated on each cached template reuse.

## Usage Examples

### Example 1: Simple Static Template
```harding
MyComponent>>render [
  html canvas: [:h |
    h class: "card"; id: "todo-panel".
    h div: [
      h h1: "Todo List".
      h p: "Welcome!"
    ]
  ]
]
```

### Example 2: With Dynamic Data (Current Limitation)
```harding
MyComponent>>render [
  | title |
  title := self getTitle.  # Must get data before canvas
  html canvas: [:h |
    h div: [
      h h1: title  # Static string used
    ]
  ]
]
```

### Example 3: Cached Template (Static Only)
```harding
MyComponent class>>cachedTemplate [
  CachedTemplate isNil ifTrue: [
    CachedTemplate := html canvas: #myView with: [:h |
      h div: [
        h h1: "Static Title"  # This is cached
      ]
    ]
  ].
  ^ CachedTemplate
]
```

## Migration from Old Html DSL

**Old style:**
```harding
Html div: #{#class -> "container"} with: (
  Html h1: #{} text: "Title"
) , (
  Html p: #{} text: "Content"
)
```

**New style:**
```harding
html canvas: [:h |
  h class: "container".
  h div: [
    h h1: "Title".
    h p: "Content"
  ]
]
```

## Next Steps for Phase 2

1. **Template Structure Caching**: Store tag hierarchy, not output string
2. **Re-evaluable Blocks**: Store closures and call them on each render
3. **Context Support**: Pass render context to evaluate blocks against
4. **Symbol Selectors**: Support `#selector` syntax for dynamic method dispatch

## Performance

**Current implementation**: Good for static templates, rebuilds HTML each call for dynamic content.

**With Phase 2**: Template structure cached once, only dynamic blocks re-evaluated - significant performance improvement for high-traffic pages.

---

*Last updated: 2026-03-17*
