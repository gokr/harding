# HtmlTemplate DSL Guide

The HtmlTemplate system in Harding provides a powerful DSL for generating HTML that separates static content from dynamic content while maintaining proper caching.

## Core Concepts

### Static vs Dynamic Content

The system automatically detects whether content is static or dynamic:

- **Static content**: String literals, numbers, booleans - rendered once and cached
- **Dynamic content**: Blocks `[ ... ]` and `HtmlDynamicValue` objects - evaluated on each render

### Template Caching

Templates are automatically cached when they contain no dynamic content:

```harding
-- This returns a cached static string
staticDiv := Html div: #{#class -> "container"} with: "Hello World".

-- This returns an HtmlTemplate that evaluates the block each time
dynamicDiv := Html div: #{#class -> "container"} with: [
  Counter := Counter + 1.
  "Count: " , Counter printString
].
```

## DSL Patterns

### 1. Static Templates (Fully Cached)

```harding
-- Returns a plain String, no template object created
container := Html div: #{#class -> "container"} with: (
  Html h1: #{} text: "Welcome"
) , (
  Html p: #{} text: "This is static content"
).
-- Result: <div class="container"><h1>Welcome</h1><p>This is static content</p></div>
```

### 2. Dynamic Content with Blocks

```harding
-- Block is evaluated each time the template renders
Counter := 0.
dynamicBadge := Html span: #{#class -> "badge"} with: [
  Counter := Counter + 1.
  "Views: " , Counter printString
].

-- Each render evaluates the block
output1 := dynamicBadge renderString.  -- "Views: 1"
output2 := dynamicBadge renderString.  -- "Views: 2"
```

### 3. Dynamic Attributes

```harding
-- Attributes can be dynamic too
toggleButton := Html button: #{
  #class -> [ self buttonClass ]
  #disabled -> [ self isDisabled ]
} text: [ self buttonLabel ].

-- nil attributes are automatically omitted
conditionalAttr := Html div: #{
  #data-active -> [ self isActive ifTrue: [ "yes" ] ifFalse: [ nil ] ]
} with: "Content".
```

### 4. Component-Level Template Caching

Components can cache their templates while still having dynamic parts:

```harding
MyComponent := Component derivePublic: #(name count).

-- Class-level template cache
MyComponent class>>cachedTemplate [
  | template |
  CachedTemplate isNil ifTrue: [
    CachedTemplate := Html div: #{#class -> "my-component"} with: (
      Html h2: #{} text: [ :component | component title ]
    ) , (
      Html p: #{} text: [ :component | component description ]
    ) , (
      Html span: #{#class -> "counter"} with: [ :component | 
        component::count printString 
      ]
    )
  ].
  ^ CachedTemplate
].

MyComponent>>render [
  ^ self class cachedTemplate
].

MyComponent>>title [
  ^ "Hello, " , name
].

MyComponent>>description [
  ^ "You have visited " , count printString , " times"
].
```

### 5. Using HtmlDynamicValue Helpers

```harding
-- textBlock: - block that returns text (escaped)
textContent := Html div: #{} with: (Html textBlock: [ self userName ]).

-- rawBlock: - block that returns raw HTML (not escaped)
rawContent := Html div: #{} with: (Html rawBlock: [ self renderedMarkdown ]).

-- fragmentBlock: - block that returns nested HtmlTemplate
nestedContent := Html div: #{} with: (Html fragmentBlock: [ self renderItems ]).

-- attrBlock: - block for dynamic attributes
styledDiv := Html div: (Html attrBlock: [ self computedAttrs ]) with: "Content".

-- With context access
textWithContext := Html div: #{} with: (Html textWith: [ :ctx | ctx::user::name ]).
```

### 6. Lists and Collections

```harding
-- Rendering lists
todoList := Html ul: #{#class -> "todo-list"} with: [
  | items |
  items := Array new.
  todos do: [:todo |
    items add: (Html li: #{#class -> "todo-item"} with: (
      Html span: #{} text: [ todo::title ]
    )).
  ].
  items
].

-- Or using collect:
todoList := Html ul: #{#class -> "todo-list"} with: (
  todos collect: [:todo |
    Html li: #{#class -> "todo-item"} with: (
      Html span: #{} text: [ todo::title ]
    )
  ]
).
```

## Best Practices

### 1. Cache at the Right Level

```harding
-- Good: Cache the outer structure
CardComponent class>>template [
  | template |
  CachedTemplate isNil ifTrue: [
    CachedTemplate := Html div: #{#class -> "card"} with: (
      Html div: #{#class -> "card-header"} with: [
        :component | component headerContent
      ]
    ) , (
      Html div: #{#class -> "card-body"} with: [
        :component | component bodyContent
      ]
    )
  ].
  ^ CachedTemplate
]

-- Bad: Don't create new templates in render
CardComponent>>render [
  -- This creates a new template every time!
  ^ Html div: #{} with: "Content"
]
```

### 2. Minimize Dynamic Content

```harding
-- Good: Static structure with specific dynamic parts
template := Html div: #{#class -> "user-profile"} with: (
  Html h1: #{} text: [ :user | user::name ]    -- Only this is dynamic
) , (
  Html p: #{} text: "Member since 2024"          -- Static, cached
).

-- Less ideal: Everything in one block
template := Html div: #{} with: [
  -- Everything re-evaluated each render
  "<h1>" , name , "</h1><p>Member since " , year , "</p>"
].
```

### 3. Use Render Context

```harding
-- Access the component from within blocks
MyComponent>>render [
  ^ Html div: #{} with: (
    Html textWith: [ :ctx | 
      -- ctx is the component instance
      ctx formatDate: ctx::createdAt
    ]
  )
]
```

### 4. Handle Nil Values

```harding
-- Nil attributes are automatically omitted
conditionalAttrs := Html div: #{
  #title -> [ self titleOrNil ]        -- If nil, attribute is omitted
  #data-id -> [ self idOrNil ]
} with: "Content".

-- Nil content renders as empty
optionalContent := Html div: #{} with: [
  self optionalData ifNil: [ "" ]
].
```

## Complete Example: Todo App with Caching

```harding
TodoApp := Object derive: #().
TodoApp>>renderPage [
  | repository panel page |
  repository := TodoRepository new.
  
  -- Panel uses cached template with dynamic blocks
  panel := TodoTemplatePanelComponent 
    repository: repository 
    routePrefix: "/todos"
    panelId: "todo-panel".
  
  -- Page component
  page := TodoTemplatePageComponent 
    repository: repository 
    routePrefix: "/todos"
    panelId: "todo-panel".
  
  ^ page renderString
]
```

The key insight is that the HtmlTemplate DSL automatically handles caching:
- Static parts are cached as strings
- Dynamic parts (blocks) are evaluated on each render
- Component-level caching allows complex templates to be efficient
