# Signal Foundry

A native Godot desktop application for visually authoring JUCE audio effects. This first milestone provides an end-to-end **graph → editable project → generated C++ → VST3 build** workflow. It is a development foundation, not a qualified production release or a complete HISE replacement.

## Run

Use **Godot 4.6.3 standard** (GDScript; .NET is not required).

```sh
godot --path SignalFoundry
```

Or import `SignalFoundry/project.godot` in the Godot editor and press F6/F5. Commands below assume the `SignalFoundry` directory.

On the cloud machine, initialize writable Godot paths before running:

```sh
export XDG_CONFIG_HOME=/workspace/.config
export XDG_CACHE_HOME=/workspace/.cache
export XDG_DATA_HOME=/workspace/.local/share
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
```

## First effect

1. The starter **Velvet Drive** effect connects stereo input → gain → saturation → stereo output.
2. Select a module to edit its parameters. The automation checkboxes determine which controls are exposed to the DAW; other values become constants.
3. Add modules from the library. Right-click a connected port to disconnect it, then drag between output and input ports to reconnect the chain. **Arrange** lays out connected modules in order. Select nodes and press Delete, or use **Remove module**.
4. **Audition** generates a low-level harmonic reference tone through the current graph. The waveform and peak meter show computed audio. This is a Godot design aid with a monitor limiter, not a JUCE host, live input, or offline renderer. Exported audio has no monitor limiter.
5. Use **Plugin** to set the name, company, and four-character manufacturer/plugin codes. Names must be safe Windows filenames. Choose unique codes before distribution and retain existing node IDs for automation compatibility.
6. **Save** writes a `.signal.json` project. **Open** validates the schema and connections before replacing the active document. New/Open/Close prompt before discarding edited work. Ctrl+S saves; Ctrl+Z and Ctrl+Shift+Z undo/redo. Text fields retain their normal text-editing shortcuts while focused.
7. **Export JUCE** writes into a **new, empty folder**. It produces source, CMake configuration, a Windows build script, standalone DSP tests, and a copy of the graph. It never overwrites an existing export.

Supported modules: stereo input/output, gain (-60 to +12 dB), one-pole low-pass (20 Hz–20 kHz), and normalized tanh saturation (drive and dry/wet). The graph is limited to a single stereo chain with at most 64 nodes. Feedback, branching, missing ports, and unused nodes are rejected for export. Incomplete projects can still be saved while editing.

## Build a Windows VST3

On **Windows x64**, install Visual Studio 2022 with **Desktop development with C++**, CMake 3.22+, and Git. In the exported directory:

```powershell
.\build-windows.ps1
```

CMake fetches JUCE **8.0.6**, pinned to commit `51a8a6d7aeae7326956d747737ccf1575e61e209`. An existing checkout can be provided using `-DJUCE_SOURCE_DIR=C:/path/to/JUCE` when configuring manually.

The plugin bundle appears under `build/FoundryPlugin_artefacts/Release/VST3/`. Copy the entire `.vst3` bundle into `%COMMONPROGRAMFILES%/VST3/` and rescan your DAW. The plugin uses JUCE's generic parameter editor; designing custom plugin skins is a future feature. Host automation uses stable node/parameter IDs and APVTS state recall. The exported audio callback uses preallocated filter state, cached parameter pointers, and 10 ms parameter ramps without locks or allocations.

## Build the Windows authoring application

Install matching **Godot 4.6.3 export templates** through Godot's template manager, then:

```powershell
.\build-windows-editor.ps1 -Godot "C:\path\to\Godot_v4.6.3-stable_win64_console.exe"
```

Or use the **Windows Desktop** export preset in Godot. Output is `build/windows/SignalFoundry.exe`, with its PCK embedded. This is an unsigned development build. Windows executable resource modification is disabled for portable cross-export; add release branding, an installer, and signing during release preparation. Include Godot license/third-party notices when distributing.

## Tests

```sh
godot --headless --editor --import
godot --headless --script res://tests/test_runner.gd -- --export-to=/absolute/path/to/a/new/empty/fixture
godot --headless --script res://tests/ui_smoke.gd
cmake -S /absolute/path/to/a/new/empty/fixture -B /tmp/foundry-dsp -DFOUNDRY_DSP_ONLY=ON
cmake --build /tmp/foundry-dsp
ctest --test-dir /tmp/foundry-dsp --output-on-failure
```

The model/export suite covers serialization, failed-load isolation, graph cycles and occupied ports, invalid parameters, automation exposure/IDs, unsafe plugin names, repeated saves, source generation, and refusal to overwrite exports. The UI suite loads the real scene and exercises inspector controls, palette addition, graph signal handlers, undo/redo, audition audio generation, and stopping audio when the graph becomes invalid. A graphical run can save a screenshot with `-- --screenshot=/absolute/path/image.png`.

See [the initial validation record](docs/VALIDATION.md) for executed checks and platform limits.

Generated C++ tests verify steady-state transfer, finite output, stereo symmetry, and reset/silence at 44.1, 48, and 96 kHz. For a full local JUCE build, omit `FOUNDRY_DSP_ONLY`; Linux requires the usual JUCE ALSA, X11, FreeType, fontconfig and OpenGL development dependencies. WebKit/curl are disabled.

`.github/workflows/signal-foundry.yml` is configured to run Godot tests, generate an all-module fixture, compile a Windows VST3, and retain a development artifact. The workflow must run on GitHub to establish Windows results; its presence alone is not validation.

## Structure and next milestones

| File | Responsibility |
| --- | --- |
| `scripts/project_model.gd` | Versioned JSON model, module definitions, validation, graph ordering, file persistence |
| `scripts/juce_exporter.gd` | C++ DSP/compiler templates, JUCE processor, CMake, Windows build script, generated tests |
| `scripts/main.gd` | Native editor UI, GraphEdit, history, inspector, dialogs |
| `scripts/preview_audio.gd` | Godot-only harmonic-tone design monitor |
| `tests/` | Model/export tests and real-scene UI smoke test |

The saved graph is the source of truth. The authoring app does not require JUCE to run; JUCE is required when compiling a generated plugin. Generated projects are independent and can be edited in C++, but C++ edits are not imported back into the graph.

Next development milestones: real audio-file audition and compiled-engine parity, a native build/diagnostics runner, a custom plugin UI designer, richer DSP and routing, and a tested instrument/MIDI path. Release qualification must cover Windows DAWs, state/automation compatibility, DSP stress and spectral quality (saturation currently has no oversampling), file recovery, performance, signing, and licensing. Review [JUCE's licensing](https://juce.com/legal/) before distributing JUCE plugins. Godot uses the MIT license; its dependencies have their own notices.
