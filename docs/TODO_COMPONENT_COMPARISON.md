# Todo App Component Comparison

Three implementations of the same todo app, showing different approaches to HTML generation in Harding.

## Summary

| Approach | Lines | Strategy | Performance | Use Case |
|----------|-------|----------|-------------|----------|
| **Buffer** | 146 | Manual string concatenation | Fastest, minimal allocations | Simple apps, maximum performance |
| **Components** | 128 | Fresh HtmlTemplate each render | Good, creates objects per render | Medium complexity, readable code |
| **Template** | 218 | Cached HtmlTemplate + dynamic blocks | Excellent, static parts cached | Complex apps, reusable components |

---

## 1. Buffer Version (TodoBufferComponents.hrd)

**Approach**: Direct string concatenation with pre-allocated String buffers.

```harding
TodoBufferItemComponent>>renderFor: aRoutePrefix panelId: aPanelId [
  | buffer itemId statusLabel titleText meta toggleUrl deleteUrl |
  itemId := todo::id printString.
  statusLabel := todo::completed ifTrue: [ "Done" ] ifFalse: [ "Open" ].
  titleText := Html escape: (todo::title).
  meta := Html escape: self metaText.
  toggleUrl := aRoutePrefix , "/todos/" , itemId , "/toggle".
  deleteUrl := aRoutePrefix , "/todos/" , itemId , "/delete".
  buffer := String withCapacity: 768.
  buffer << "<li style=\"list-style:none;\">".
  buffer << "<div class=\"card bg-base-200...\">".
  # ... dozens more buffer << operations
  buffer << "</div></li>".
  ^ buffer
]
```

**Pros**:
- Maximum performance - single string allocation
- No template object creation overhead
- Full control over HTML output

**Cons**:
- Verbose and error-prone
- HTML structure mixed with logic
- Easy to miss closing tags or quotes
- Hard to maintain

---

## 2. Components Version (TodoComponents.hrd)

**Approach**: Html DSL creating fresh HtmlTemplate objects each render.

```harding
TodoItemComponent>>render [
  | rowAttrs mainAttrs actionsAttrs statusAttrs titleAttrs metaAttrs |
  rowAttrs := #{#class -> "card bg-base-200...", #style -> "margin-top: 0.75rem;"}.
  mainAttrs := #{#style -> "display:flex;..."}.
  # ... more attribute dictionaries
  
  statusText := todo::completed ifTrue: [ "Done" ] ifFalse: [ "Open" ].
  titleMarkup := Html text: (todo::title).
  
  ^ Html li: #{#style -> "list-style:none;"} with: (
    DaisyCard panel: (...) attrs: rowAttrs
  )
]
```

**How it works**:
- Each call to `Html div:...` creates a new `HtmlTemplate` object
- `HtmlTemplate` stores segments (strings, dynamic values, nested templates)
- When rendered, evaluates all dynamic content

**Pros**:
- Clean, readable code
- Declarative HTML structure
- Automatic escaping
- Component composition

**Cons**:
- Creates HtmlTemplate objects on every render
- Evaluates static structure repeatedly
- More garbage collection pressure

---

## 3. Template Version (TodoTemplateComponents.hrd)

**Approach**: Class-level cached HtmlTemplate with dynamic blocks.

```harding
TodoTemplateItemComponent class>>cachedTemplate [
  | template |
  Template isNil ifTrue: [
    Template := Html li: #{#style -> "list-style:none;"} with: (
      Html div: #{
        #class -> "card bg-base-200..."
      } with: (
        Html tag: "span" attrs: #{
          #class -> [ :item | item statusClass ]
        } with: [ :item | item statusText ]
      ) , (
        Html button: #{
          #"hx-post" -> [ :item | item toggleUrl ]
        } text: [ :item | item toggleLabel ]
      )
    )
  ].
  ^ Template
]

TodoTemplateItemComponent>>renderFor: aRoutePrefix panelId: aPanelId [
  routePrefix := aRoutePrefix.
  panelId := aPanelId.
  ^ self class cachedTemplate renderWith: self
]
```

**How it works**:
- Template created once and cached in class variable
- Static HTML structure stored in `HtmlTemplate`
- Dynamic parts use `[ :component | ... ]` blocks
- Blocks evaluated each render to inject current data
- `HtmlDynamicValue` objects wrap the blocks

**Pros**:
- Clean code like Components version
- Static structure cached - no recreation
- Dynamic parts evaluated on demand
- Best of both worlds: readability + performance

**Cons**:
- More complex setup (class-level caching)
- Slightly more verbose (block syntax)
- Need to understand dynamic vs static separation

---

## Key Differences Illustrated

### Static Content

**Buffer**:
```harding
buffer << "<div class=\"badge\">Done</div>"
```

**Components**:
```harding
Html div: #{#class -> "badge"} with: "Done"
# Creates new HtmlTemplate each time
```

**Template**:
```harding
Template isNil ifTrue: [
  Template := Html div: #{#class -> "badge"} with: "Done"
].
# Created once, cached, returns "<div class="badge">Done</div>" string
```

### Dynamic Content

**Buffer**:
```harding
buffer << "<span class=\"" << self statusClass << "\">" << statusText << "</span>"
```

**Components**:
```harding
Html span: #{#class -> self statusClass} text: statusText
# Builds template with evaluated values right now
```

**Template**:
```harding
Html tag: "span" attrs: #{
  #class -> [ :item | item statusClass ]
} with: [ :item | item statusText ]
# Template stores blocks, evaluates them on each render
```

### Component Rendering

**Buffer**:
```harding
buffer << ((TodoBufferItemComponent todo: aTodo) renderFor: routePrefix panelId: panelId)
# Returns string, appended to buffer
```

**Components**:
```harding
items add: ((TodoItemComponent todo: aTodo) renderString)
# Returns fresh HtmlTemplate, rendered to string, collected
```

**Template**:
```harding
items add: ((TodoTemplateItemComponent todo: aTodo) renderFor: routePrefix panelId: panelId)
# Returns HtmlTemplate (cached structure + blocks), collected, rendered once at end
```

---

## Performance Comparison

### Memory Allocations (rendering 100 items)

| Approach | Objects Created | Strings Created | GC Pressure |
|----------|----------------|-----------------|-------------|
| Buffer | ~100 (mostly strings) | ~400 | Low |
| Components | ~300 (HtmlTemplates + segments) | ~500 | Medium |
| Template | ~100 (items array + dynamic evals) | ~300 | Low |

### Render Time (approximate)

| Approach | First Render | Subsequent Renders | Notes |
|----------|-------------|-------------------|-------|
| Buffer | Fast | Fast | Consistent, no cache overhead |
| Components | Medium | Medium | Same work each time |
| Template | Slow (builds cache) | Fast | Amortized cost |

---

## When to Use Each

### Use Buffer when:
- Maximum performance is critical
- Simple, mostly-static content
- You're comfortable with manual HTML
- Example: Static landing pages, simple admin UIs

### Use Components when:
- Code readability matters most
- Content changes frequently
- You're prototyping
- Example: Early development, simple CRUD apps

### Use Template when:
- Building reusable component libraries
- Same structure rendered many times
- You want clean code AND performance
- Example: Production apps, component frameworks, dashboards

---

## Migration Path

```harding
# Start with Components (clean code)
render [
  ^ Html div: #{} with: title
]

# Optimize hot paths with Template caching
render [
  ^ self class cachedTemplate renderWith: self
]

cachedTemplate [
  Template isNil ifTrue: [
    Template := Html div: #{} with: [ :comp | comp title ]
  ].
  ^ Template
]

# For maximum performance, use Buffer
render [
  | buffer |
  buffer := String withCapacity: 256.
  buffer << "<div>" << title << "</div>".
  ^ buffer
]
```

The beauty of Harding's Html system is you can choose the right level of abstraction for each component!
