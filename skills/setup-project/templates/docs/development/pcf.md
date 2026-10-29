# Power Apps Component Framework Standards (PCF)

Read `docs/agents/development-standards.md` first. This file only adds what is specific to PCF controls.

## Stack
- Applies to model-driven and canvas apps. Virtual controls are not supported on Power Pages; use `control-type="standard"` there instead.
- Use React PCF virtual controls (`control-type="virtual"`) with platform libraries.
- React and Fluent UI v9 (`@fluentui/react-components`) through platform libraries; do not bundle React or Fluent UI.
- A new control declares the React and Fluent platform-library versions Microsoft's PCF documentation currently lists as supported: check it when creating the control, never a newer version than it lists.
- Use the control's pinned TypeScript and `pcf-scripts` versions (`package.json`) and platform-library (React/Fluent) versions (`ControlManifest.Input.xml`); do not upgrade any of them independently of a reviewed change — a newer Fluent platform-library version than the platform supports has caused solution import failures.
- Tests: Vitest + Testing Library.

## Structure
- Each control is its own project in `src/PowerPlatform/WebResources/{{project_name}}.WebResources/PCFs/<ControlName>/`, with its own `package.json` and lint configuration.
- Scaffold new controls with `pac pcf init -ns {{project_name}} -n <ControlName> -t field -fw react -npm -o src/PowerPlatform/WebResources/{{project_name}}.WebResources/PCFs/<ControlName>` (use `-t dataset` for dataset-bound controls), and follow the structure it generates; avoid custom build architecture unless required.
- The PCF control owns lifecycle, context and platform integration; React components own UI rendering.
- `updateView` MUST return the React element representing the current control state.
- Keep PCF-specific concerns at the control boundary; pass required data and callbacks to React components through props.
- Pure business rules MUST NOT access PCF `context`, React state/refs or the DOM.
- Keep external dependencies minimal; prefer platform libraries and existing dependencies.
- Keep `ControlManifest.Input.xml` aligned with the implementation and declared platform libraries.

## Lifecycle
- Use `init` for one-time initialization; start any required resource/network setup without blocking the first render, surfacing a loading state in the component if needed.
- `updateView` MUST derive the rendered tree from the current context/state; do not perform side effects or unnecessary I/O there.
- `updateView` may be called for changes unrelated to the primary input; do not assume why it was invoked.
- Use `context.updatedProperties` when expensive work only needs to run for specific context changes.
- `destroy` MUST release subscriptions, timers, event handlers and other resources created by the control.
- Async operations MUST prevent stale results from overwriting current state.

## React
- Prefer functional components and hooks.
- Do not pass the PCF `context` into components when individual props are sufficient.
- Prefer deriving values during render over unnecessary `useEffect`.
- Effects MUST clean up resources they create.
- Do not duplicate props in state unless synchronization is required.
- Avoid direct DOM manipulation; use React/Fluent UI APIs.
- Use APIs compatible with the platform-library versions.

## Fluent UI
- Prefer Fluent components and design tokens over custom UI/CSS.
- Do not hard-code theme-dependent colors.
- Do not mix Fluent UI v8 and v9.
- Ensure any custom UI beyond Fluent's built-in components is keyboard-operable and exposes accessible names/roles; do not convey state through color alone.

## PCF / Dataverse Integration
- Use only APIs and capabilities available to the target host and declared in the manifest when required.
- Request only the data required by the control.
- Handle null/unavailable context values explicitly.
- Keep Dataverse/API calls outside rendering code.
- Prefer framework-provided data/context over redundant API calls.

## Performance
- Keep `updateView` and React rendering cheap.
- Avoid redundant React renders and Dataverse/API calls.
- Add memoization only when there is a clear performance benefit. A virtual control shares the platform's React render tree, so an unrelated control's refresh can trigger `updateView`: `React.memo` is the usual clear benefit there.

## Error Handling
- Never let an exception escape `init`, `updateView` or `destroy`. In a virtual control these run inside the host's shared React render tree, so an unhandled throw can break unrelated controls on the same form. Catch it, trace it, and render an error state in the component.

## Testing
- Test React components through observable UI behavior with Testing Library.
- Mock PCF context and framework APIs explicitly.
- Do not rely on the PCF test harness for unit tests.
