# Bona Todo Workflow

This walkthrough starts the live-editable Todo app inside Bona and uses the Browser to change handler and component methods while the MummyX server keeps running.

## Build Bona With MummyX

```bash
nimble bona_mummyx
./bona
```

## Start The Todo App In A Workspace

Open a Workspace and evaluate the contents of `examples/web_todo_bona.hrd`:

```smalltalk
Harding load: "lib/mummyx/Bootstrap.hrd".
Harding load: "lib/web/Bootstrap.hrd".
Harding load: "lib/web/todo/Bootstrap.hrd".

TodoApp resetRepository.

TodoApp startOn: 8080.
```

`startOn:` is the non-blocking/background form, which is appropriate from a Bona workspace.

For a terminal/CLI session use the blocking form instead:

```smalltalk
TodoApp serveForeverOn: 8080.
```

or simply:

```smalltalk
TodoApp serve.
```

Then open `http://127.0.0.1:8080` in a browser.

This load path matters for Bona Browser visibility: it creates named `Web` and `WebTodo` libraries, so the loaded classes appear in the Browser instead of only existing as top-level globals.

## Edit The App Live In Browser

Use Bona's System Browser and open these classes:

- `Web` library
- `WebTodo` library
- `TodoApp`
- `TodoPageComponent`
- `TodoPanelComponent`
- `TodoItemComponent`
- `TodoItem`
- `TodoRepository`

If the Browser was already open when you evaluated the Workspace code, Bona refreshes open Browser windows after a successful evaluation. You can also use the Browser's `Refresh` button.

The most useful live-edit points are:

- `TodoApp class>>home:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>createTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>toggleTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>deleteTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoPageComponent>>bodyMarkup` in `lib/web/todo/TodoComponents.hrd`
- `TodoPanelComponent>>render` in `lib/web/todo/TodoComponents.hrd`
- `TodoItemComponent>>render` in `lib/web/todo/TodoComponents.hrd`
- `TodoItem>>title:` / `TodoItem>>toggleCompleted` in `lib/web/todo/TodoItem.hrd`

For ordinary copy, markup, button labels, layout, and fragment rendering changes:

- save the method in Browser
- refresh the page or trigger the htmx action again

Those changes are picked up without restarting the server.

## When To Reinstall Routes

If you only change code inside existing handler methods like `home:`, `createTodo:`, `toggleTodo:`, or `deleteTodo:`, you usually just refresh the page.

If you change route declarations inside `TodoApp class>>installRoutesOn:` or `TodoApp>>installRoutes`, evaluate this in Workspace:

```smalltalk
TodoApp reloadRoutes.
```

That reapplies the router table to the already-running server.

## Typical Editing Loop

1. Start the app from Workspace.
2. Open the Browser on `TodoItemComponent>>render`.
3. Change button text, copy, badges, or row structure.
4. Save in Browser.
5. Reload the page or click a Todo action.
6. See the new HTML immediately.

For example, changing:

```smalltalk
"Active - edit this method in Bona and refresh."
```

inside `TodoItemComponent>>metaText` updates the next fragment response right away.

## Stop The Server

Evaluate this in Workspace:

```smalltalk
TodoServer stop.
```

If you want a fresh data set on the next launch, also run:

```smalltalk
TodoApp resetRepository.
```

## Current Notes

- The Bona workflow uses `lib/web/Bootstrap.hrd` and `lib/web/todo/Bootstrap.hrd` so Browser libraries stay in sync with the loaded web code.
- The UI serves a vendored DaisyUI stylesheet from `TodoApp`.
- Rendering now uses tracked state in `lib/reactive/` plus web-specific external caching in `RenderCache`.
- The repository is still in-memory. Replacing it with Bitbarrel or MySQL should mainly affect `TodoRepository` and `TodoItem` construction.
