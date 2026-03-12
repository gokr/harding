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
Harding load: "lib/web/Component.hrd".
Harding load: "lib/web/Html.hrd".
Harding load: "lib/web/Htmx.hrd".
Harding load: "lib/web/Daisy.hrd".
Harding load: "lib/web/Basecoat.hrd".
Harding load: "lib/web/todo/TodoRepository.hrd".
Harding load: "lib/web/todo/TodoComponents.hrd".
Harding load: "lib/web/todo/TodoApp.hrd".

TodoApp resetRepository.

TodoServer := HttpServer new.
TodoRouter := Router new.
TodoApp installRoutesOn: TodoRouter.
TodoServer router: TodoRouter.
TodoServer start: 8080.
```

Then open `http://127.0.0.1:8080` in a browser.

## Edit The App Live In Browser

Use Bona's System Browser and open these classes:

- `TodoApp`
- `TodoPageComponent`
- `TodoPanelComponent`
- `TodoItemComponent`
- `TodoRepository`

The most useful live-edit points are:

- `TodoApp class>>home:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>createTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>toggleTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoApp class>>deleteTodo:` in `lib/web/todo/TodoApp.hrd`
- `TodoPageComponent>>render` in `lib/web/todo/TodoComponents.hrd`
- `TodoPanelComponent>>render` in `lib/web/todo/TodoComponents.hrd`
- `TodoItemComponent>>render` in `lib/web/todo/TodoComponents.hrd`

For ordinary copy, markup, button labels, layout, and fragment rendering changes:

- save the method in Browser
- refresh the page or trigger the htmx action again

Those changes are picked up without restarting the server.

## When To Reinstall Routes

If you only change code inside existing handler methods like `home:`, `createTodo:`, `toggleTodo:`, or `deleteTodo:`, you usually just refresh the page.

If you change route declarations inside `TodoApp class>>installRoutesOn:` or `TodoApp>>installRoutes`, evaluate this in Workspace:

```smalltalk
TodoApp installRoutesOn: TodoRouter.
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

inside `TodoItemComponent>>render` updates the next fragment response right away.

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

- The Todo app currently uses direct `Harding load:` calls in Bona because that path is the most reliable for live request handlers right now.
- The UI uses DaisyUI-style class names with a bundled stylesheet, so the workflow stays htmx-friendly and does not require a Tailwind build step.
- The repository is in-memory. Replacing it with Bitbarrel or MySQL should mainly affect `TodoRepository`.
