# Dataverse Plugin Standards

Read `docs/agents/development-standards.md` first. This file only adds what is specific to plugins.

## Stack
- Target .NET Framework 4.6.2.
- Use SDK-style projects and deploy as Dataverse `.nupkg` plug-in packages.
- Do not strong-name assemblies. No `.snk`; `<SignAssembly>false</SignAssembly>`.
- Generate early-bound classes with `pac modelbuilder build --namespace {{project_name}}.Common.Generated --outdirectory src/PowerPlatform/Plugins/{{project_name}}.Common/Generated`. Without `--namespace` the classes land in the global namespace. Never edit generated files manually.
- Tests: xUnit 2.9.3 + FakeXrmEasy.Plugins.v9 2.9.4. Add FakeXrmEasy.Messages.v9 2.9.4 only when message/Custom API simulation requires it.

## Projects
- All Power Platform code lives under `src/PowerPlatform/`, in `PowerPlatform.sln`. Each top-level folder there (`Plugins`, `CustomAPIs`, `WebResources`) is also a solution folder in `PowerPlatform.sln` of the same name, and every project is nested in the solution folder that matches its physical folder.
- One plugin project per table: `src/PowerPlatform/Plugins/{{project_name}}.<Entity>/{{project_name}}.<Entity>.csproj`, e.g. `{{project_name}}.Account`. Each one is its own plug-in package. Do not use `pac plugin init`: it adds `.vscode/`, `.gitignore`, `PluginBase.cs` and `Plugin1.cs` that the project does not want. Write the `.csproj` as below, replacing `<Entity>`, and nothing else; `Microsoft.PowerApps.MSBuild.Plugin` produces the `.nupkg` on `dotnet build`:

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
    <PackageReference Include="Microsoft.CrmSdk.CoreAssemblies" Version="9.0.2.*" PrivateAssets="All" />
    <PackageReference Include="Microsoft.PowerApps.MSBuild.Plugin" Version="1.*" PrivateAssets="All" />
    <PackageReference Include="Microsoft.NETFramework.ReferenceAssemblies" Version="1.0.*" PrivateAssets="All" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{{project_name}}.Common\{{project_name}}.Common.csproj" />
  </ItemGroup>

</Project>
```
- Each plugin project has exactly one test project, next to it: `src/PowerPlatform/Plugins/{{project_name}}.<Entity>.Tests/`. There is no separate `tests/` tree.
- `src/PowerPlatform/Plugins/{{project_name}}.Common/` is the shared library: `PluginBase.cs`, the early-bound classes and helpers used by more than one project. It holds no plugin classes and is not registered in Dataverse.
- Add every new project to `PowerPlatform.sln` in its solution folder: `dotnet sln src/PowerPlatform/PowerPlatform.sln add <csproj> --solution-folder Plugins`.

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
- Plugin tests MUST execute the production `Execute` path using FakeXrmEasy; never test against a live Dataverse environment.
- Cover recursion and pipeline-depth behavior wherever the plugin can retrigger itself.
- After changes, build affected projects and run all affected tests.
- Build and test one project per command: `dotnet test <Project>.Tests.csproj` builds the plugin and `{{project_name}}.Common` it references. `dotnet build` accepts a single project or solution; to build everything, `dotnet build src/PowerPlatform/PowerPlatform.sln`.
