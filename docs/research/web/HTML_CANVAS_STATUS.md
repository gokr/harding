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

### Current Rendering Model

`Html` now renders directly. Caching belongs at the `Component` / `RenderCache` layer, not in `HtmlCanvas` itself.

```harding
Html render: [:h |
  h div: [ h h1: "Hello" ]
]
```

If output depends on tracked state, ordinary reads during component rendering are what register dependencies.

### What We No Longer Rely On

- template-structure caching in `Html`
- dynamic holes in cached Html templates (removed from the active design)
- auto-generated Html cache keys

Those ideas were replaced by component-level cached HTML plus tracked-state invalidation.

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

### Example 2: With Dynamic Data
```harding
MyComponent>>render [
  | title |
  title := self getTitle.
  html canvas: [:h |
    h div: [
      h h1: title
    ]
  ]
]
```

## Migration from Old Html DSL

**Old style:**
```harding
Html div: #{#class -> "container"} with: (
  Html h1: #{} text: "Title"
) & (
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
