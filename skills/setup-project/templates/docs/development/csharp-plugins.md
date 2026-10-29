# Dataverse Plugin Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to plugins.

## Stack
- Target .NET Framework 4.6.2.
- Use SDK-style projects and deploy as Dataverse `.nupkg` plug-in packages.
- Do not strong-name assemblies. No `.snk`; `<SignAssembly>false</SignAssembly>`.
- Generate early-bound classes with `pac modelbuilder build --namespace {{project_name}}.Common.Generated --outdirectory src/PowerPlatform/Plugins/{{project_name}}.Common/Generated`. Without `--namespace` the classes land in the global namespace. Never edit generated files manually.
- Tests: MSTest + Moq, pinned per `docs/agents/development-standards.md`. Test projects target `net462`, like the plugin they reference.

## Projects
- All Power Platform code lives under `src/PowerPlatform/`, in `PowerPlatform.slnx`. Each top-level folder there (`Plugins`, `CustomAPIs`, `WebResources`) is also a solution folder in `PowerPlatform.slnx` of the same name, and every project is nested in the solution folder that matches its physical folder.
- One plugin project per table, grouped by the entity targeted by the trigger: plugins triggered on Account belong in the Account project: `src/PowerPlatform/Plugins/{{project_name}}.<Entity>/{{project_name}}.<Entity>.csproj`, e.g. `{{project_name}}.Account`. Each one is its own plug-in package. Do not use `pac plugin init`: it adds `.vscode/`, `.gitignore`, `PluginBase.cs` and `Plugin1.cs` that the project does not want. Write the `.csproj` as below, replacing `<Entity>`, and each `<latest stable>` with that package's version, and nothing else: the versions the other plugin projects already pin, or for the first project the latest stable release on NuGet, per "Versions" in `docs/agents/development-standards.md`; `Microsoft.PowerApps.MSBuild.Plugin` produces the `.nupkg` on `dotnet build`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net462</TargetFramework>
    <RootNamespace>{{project_name}}.<Entity></RootNamespace>
    <AssemblyName>{{project_name}}.<Entity></AssemblyName>
    <SignAssembly>false</SignAssembly>
    <AssemblyVersion>1.0.0.0</AssemblyVersion>
    <FileVersion>1.0.0.0</FileVersion>
    <PackageId>{{project_name}}.<Entity></PackageId>
    <Version>$(FileVersion)</Version>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.CrmSdk.CoreAssemblies" Version="<latest stable>" PrivateAssets="All" />
    <PackageReference Include="Microsoft.PowerApps.MSBuild.Plugin" Version="<latest stable>" PrivateAssets="All" />
    <PackageReference Include="Microsoft.NETFramework.ReferenceAssemblies" Version="<latest stable>" PrivateAssets="All" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{{project_name}}.Common\{{project_name}}.Common.csproj" />
  </ItemGroup>

</Project>
```
- Each plugin project has exactly one test project, next to it: `src/PowerPlatform/Plugins/{{project_name}}.<Entity>.Tests/`, and so does `{{project_name}}.Common` once it holds a helper with logic. There is no separate `tests/` tree. Its `.csproj` is the one above without `PackageId`, `Version` and the `Microsoft.PowerApps.MSBuild.Plugin` reference, with `<IsPackable>false</IsPackable>`, the `MSTest` metapackage and `Moq`, and project references to the project under test and to `{{project_name}}.Testing`.
- `src/PowerPlatform/Plugins/{{project_name}}.Common/` is the shared library: `PluginBase.cs`, the early-bound classes and helpers used by more than one project. It holds no plugin classes and is not registered in Dataverse.
- The first plugin or Custom API creates what does not exist yet:
  - `src/PowerPlatform/PowerPlatform.slnx` (`dotnet new sln --name PowerPlatform --format slnx`, .NET SDK 10 or later), with the solution folders above.
  - `{{project_name}}.Common.csproj`: the `.csproj` above with `{{project_name}}.Common` as `RootNamespace` and `AssemblyName`, and without `PackageId`, `Version`, the `Microsoft.PowerApps.MSBuild.Plugin` reference and the project reference. It is a class library, not a plug-in package.
  - `PluginBase.cs` in it: the `PluginBase`, `ILocalPluginContext` and `LocalPluginContext` that `pac plugin init` generates. Run `pac plugin init` in a temporary folder, copy only `PluginBase.cs`, change its namespace to `{{project_name}}.Common`, and delete the temporary folder.
  - `src/PowerPlatform/Plugins/{{project_name}}.Testing/`: a `net462` class library referenced by every test project and by no plugin, holding the helper that builds the mocked `IServiceProvider` described in "Testing". Add it to the `Plugins` solution folder.
- Add every new project to `PowerPlatform.slnx` in its solution folder: `dotnet sln src/PowerPlatform/PowerPlatform.slnx add <csproj> --solution-folder Plugins`.

## Structure
- All plugins MUST inherit `PluginBase` from `{{project_name}}.Common`; never resolve services directly from `IServiceProvider`.
- One plugin class = one business capability, not one entity. Split distinct behaviors into separate plugins/steps.
- Plugin classes SHOULD be `sealed`.
- Namespace: `{{project_name}}.<Entity>`, the same as the project. Class names describe the capability, e.g. `ValidateCreditLimitOnUpdate`.
- Run Dataverse calls as the user by default: `InitiatingUserService` for work done on the caller's behalf, `PluginUserService` for the registered step user. `AdminUserService` runs as SYSTEM and bypasses the caller's security roles: use it only when the operation must act regardless of that user's privileges (e.g. reading configuration the user cannot see, or maintaining a record the user does not own), never to make a permissions error go away. Every use carries a comment stating why the user's own context is not enough, and returns or writes only what the caller is entitled to.
- Keep plugins stateless: no mutable instance/static state. `static readonly` is allowed only for immutable compile-time values.
- Do not reference plugin classes from other plugins as an API; shared logic belongs in a shared internal library.

## Business Logic
- Dataverse-specific code (`IOrganizationService`, `IPluginExecutionContext`, `Entity`, etc.) belongs in the integration layer; pure rules use plain C# values and POCOs.
- The plugin class only wires: it takes from `ILocalPluginContext` the services and context values the capability needs and passes them to a service class, the services through its constructor. Service classes never receive `IServiceProvider` or `ILocalPluginContext`.

## Pipeline
- Prefer PreValidation for validation, PreOperation for modifying `Target`, and PostOperation when the operation requires persisted data.
- Prefer `Target`, registered images and execution context data over unnecessary `Retrieve` calls.
- Register filtering attributes only for attributes actually required by the plugin.
- Register required pre/post images explicitly. If required data is missing, fail fast with tracing.
- Keep outbound HTTP calls out of synchronous plugins unless the requirement explicitly needs one; then use strict timeouts and follow sandbox constraints. Move long-running or reliability-sensitive work to async processing or queues.
- Prevent recursive/self-triggering writes. Use `context.Depth` only when appropriate; never use a blanket `Depth > 1` guard as a substitute for correct trigger design.

## Error Handling & Tracing
- Expected business/validation failures: `InvalidPluginExecutionException` with a user-safe message.
- Use `ITracingService` for diagnostics: the trace is the only forensic record a synchronous plugin leaves behind.

## Testing
- Never test against a live Dataverse environment. Each layer is tested once, at its own level: pure rules directly, without mocks; service classes directly, with Moq doubles of the services they receive; plugin classes through their production `Execute`, covering only the wiring: the identity used, what is read from `Target` and the images, and the exception raised.
- Build the plugin's doubles with the helper in `{{project_name}}.Testing`. It returns the `IServiceProvider` the plugin receives, with a double for every service `PluginBase` resolves: an `IPluginExecutionContext` mock with distinct, non-empty `UserId` and `InitiatingUserId`, `Depth` 1, and real, empty `InputParameters`, `OutputParameters`, `SharedVariables`, `PreEntityImages` and `PostEntityImages`; and an `IOrganizationServiceFactory` that returns a separate `IOrganizationService` mock per user id (`UserId`, `InitiatingUserId`, `null` for SYSTEM), so a test can tell which identity made each call. Each test sets only what its case needs.
- Set the context as Dataverse sends it for the registered step: its message, stage and primary entity, a `Target` that carries only the attributes the operation sends, and only the images the step registers. A mock enforces none of the registration; the test is only as true as this context.
- `IOrganizationService` mocks use `MockBehavior.Strict`: set up every call the case expects, so an unexpected call fails the test instead of returning `null`.
- Assert what the caller sees: the `Target` after a PreOperation plugin, the `OutputParameters` of a Custom API, the `InvalidPluginExecutionException` and its message, with `Assert.ThrowsExactly<T>` (MSTest 4 has no `[ExpectedException]`). Assert a write with `Verify` on its table and the attributes that matter, not on call order or on calls the outcome does not depend on.
- Mocks do not run the pipeline: no test can show that one plugin triggers another. Wherever the plugin can retrigger itself, test the guard it relies on (`Depth`, a shared variable, a changed-attribute check) with the context the retriggered call would bring.
- Each test builds its own doubles, in the test or in `[TestInitialize]`; no static or shared mock state.
- After changes, build affected projects and run all affected tests.
- Build and test one project per command: `dotnet test <Project>.Tests.csproj` builds the plugin and `{{project_name}}.Common` it references. `dotnet build` accepts a single project or solution; to build everything, `dotnet build src/PowerPlatform/PowerPlatform.slnx`.
