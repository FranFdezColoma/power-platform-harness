# JavaScript Web Resource Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to web resources.

## Stack
- Author web resources as plain ES2020 JavaScript. No build, bundling or transpilation step: the file committed is the file deployed to Dataverse.
- Do not use syntax beyond ES2020 in deployed files.
- Tests: Vitest with the `node` environment. Form scripts reach the form only through `executionContext`, `formContext` and `Xrm`, which tests mock, so they need no browser DOM.
- Only a test that genuinely exercises browser APIs (an HTML web resource's own `document`, `localStorage`, `window.location`) runs under `jsdom`, opted into for that file alone with `// @vitest-environment jsdom` on its first line, adding `jsdom` as a pinned dev dependency when the first such test appears.
- Prefer manual mocks for simple form scenarios. Use `xrm-mock` when manual mocks become impractical.
- Lint: ESLint 10 (flat config), shared with the PCF projects.
- Pin exact versions in `package.json`.

## Structure
- One web resource per file, named `<TableOrDomain>Form.js` or `<TableOrDomain>Ribbon.js`, in a folder named after the table's logical name (or the domain, in lowercase): `{{publisher_prefix}}_/src/js/<table>/<TableOrDomain>Form.js`, e.g. `{{publisher_prefix}}_/src/js/account/AccountForm.js`. Never directly in `js/`.
- Dataverse name: the same path, e.g. `{{publisher_prefix}}_/src/js/account/AccountForm.js`, so the name in the solution always says where the file lives in the repository.
- Unit tests are co-located next to the file they cover: `<TableOrDomain>Form.test.js` or `<TableOrDomain>Ribbon.test.js`.
- `*.test.js` files are never web resources: never upload them or add them to a solution.
- Each web resource MUST use the Revealing Module Pattern, implemented with an IIFE and assigned directly to the global `{{project_name}}` namespace.
```js
globalThis.{{project_name}} = globalThis.{{project_name}} || {}; 
globalThis.{{project_name}}.<TableOrDomain>Form = (function () {
  "use strict"; 

  // Private implementation 

  function onLoad(executionContext) {
    const formContext = executionContext.getFormContext();
    formContext.data.entity.addOnSave(onSave);
    formContext.getAttribute("<attribute>")?.addOnChange(onChange<Attribute>);
  }
  
  return { 
    onLoad 
  }; 
})();
```
- Each web resource MUST expose exactly one form API object, under the namespace `{{project_name}}.<TableOrDomain>Form`. No other global namespace or API object.
- Register form event handlers with their fully qualified name, e.g. `{{project_name}}.<TableOrDomain>Form.onLoad`. Event handlers MUST NOT be exposed as standalone global functions.
- Deployed files MUST NOT contain module syntax: no `import`/`export`, no `require`/`exports`/`module.exports`. Test files may use ES modules — they are not deployed.
- Expose only the Dynamics event handlers the form registers, plus the minimal set of pure business-rule functions that need direct unit testing. Do not expose a pure function whose behavior is already covered through a public event handler.
- Keep private: infrastructure helpers, form-value readers, control setters, error-dialog wrappers and event-registration helpers.
- Functions exposed for testing are not a supported integration API; other web resources MUST NOT call them.

## Form Events
- Register only `OnLoad` in the form designer (maker portal), with **Pass execution context as first parameter** checked: `{{project_name}}.<TableOrDomain>Form.onLoad`. Never register `OnChange` or `OnSave` handlers in the form designer.
- When the script needs save or change behaviour, `onLoad` attaches it through the Client API: `formContext.data.entity.addOnSave(onSave)` for save, `formContext.getAttribute("<attribute>")?.addOnChange(<handler>)` for each attribute that drives a rule. Wiring lives in the code, where it is reviewed and tested, instead of in form XML.
- Use optional chaining on `getAttribute`: an attribute that is not on the form returns `null`, and the handler for it is simply not attached.
- Attached handlers are named functions, never inline closures, so they can be detached with `removeOnChange`/`removeOnSave`. Since the form never calls them by name, they need not be exposed; what the form API exposes follows the Structure rules above.
- Handlers attached this way still receive the execution context as their first argument; `onSave` blocks the save with `executionContext.getEventArgs().preventDefault()`.

## Business Logic
- Pure business rules MUST NOT access `executionContext`, `formContext`, `Xrm`, DOM APIs or mutable global state. Immutable constants and configuration are allowed.
- `executionContext`, `formContext` and `Xrm` stay in the form/integration layer, which may produce side effects through supported APIs.
- Use supported Dynamics Client APIs; never manipulate the DOM directly.

## Performance
- `onLoad` MUST NOT block form rendering. Defer work that is not needed to render the form.
- Never use synchronous Web API or `XMLHttpRequest` calls. Use the promise-based `Xrm.WebApi`.
- Prefer values already on the form (`formContext.getAttribute`) over retrieving the same data through `Xrm.WebApi`.
- Request only the columns needed (`$select`). Avoid unbounded queries in form scripts.
- Register `onChange` handlers only on the attributes that actually drive the rule, and keep handlers on high-frequency fields cheap.
- Read controls and attributes once into locals instead of repeating `getControl`/`getAttribute` lookups in loops.

## Error Handling
- Expected business/validation failures surface to the user through supported APIs (`Xrm.Navigation.openErrorDialog`, `formContext.ui.setFormNotification`).
- Every rejected promise from `Xrm.WebApi` or `Xrm.Navigation` MUST be handled; empty `catch` blocks are not allowed.
- Block save with `preventDefault()` only for genuine validation failures the user can act on.
- Do not leave `console.log` diagnostics in deployed web resources.

## Testing
- Vitest MUST load and execute the actual production web resource file.
- Tests access the implementation only through its exposed global form API.
- Test `onChange` and `onSave` behaviour by calling `onLoad` against a mocked form context, capturing the handlers it passes to `addOnChange`/`addOnSave`, and invoking them.
- Re-evaluate the production script for each test against a fresh global, so namespace state is reset between cases.
- Prefer manual mocks for simple form scenarios; use `xrm-mock` when manual mocks become impractical.
