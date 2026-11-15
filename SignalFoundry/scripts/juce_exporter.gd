class_name JuceExporter
extends RefCounted

const JUCE_COMMIT = "51a8a6d7aeae7326956d747737ccf1575e61e209" # JUCE 8.0.6

static func cpp_string(value: String) -> String:
	return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + '"'

static func cmake_string(value: String) -> String:
	return cpp_string(value).replace("$", "\\$").replace(";", "\\;")

static func generate(project: FoundryProject) -> Dictionary:
	var errors = project.validate_graph()
	if not errors.is_empty():
		return {"error": "\n".join(errors)}
	var chain = project.ordered_nodes()
	var fields = ""
	var smoothers = ""
	var initialise = ""
	var targets = ""
	var ticks = ""
	var stages = ""
	var layouts = ""
	var pointer_fields = ""
	var pointer_init = ""
	var parameter_reads = ""
	var expected = ""
	var stage_index = 0
	var filter_count = 0
	for node in chain:
		var spec: Dictionary = FoundryProject.DEFINITIONS[node.type].params
		for key in spec:
			var symbol: String = node.id + "_" + key
			var value = _float(node.params[key])
			fields += "    float %s = %s;\n" % [symbol, value]
			smoothers += "    Ramp %s;\n" % symbol
			var expression = "p." + symbol
			if key == "gain_db":
				expression = "std::pow(10.0f, p.%s / 20.0f)" % symbol
			elif key == "cutoff":
				expression = "std::exp(-6.283185307179586f * std::min(p.%s, float(sampleRate * 0.49)) / float(sampleRate))" % symbol
			initialise += "        %s.reset(%s);\n" % [symbol, expression]
			targets += "        %s.set(%s, rampSamples);\n" % [symbol, expression]
			ticks += "            const float v_%s = %s.next();\n" % [symbol, symbol]
			if node.exposed[key]:
				var label: String = FoundryProject.DEFINITIONS[node.type].name + " " + node.id.trim_prefix("n") + " · " + spec[key].label
				layouts += '        layout.add(std::make_unique<juce::AudioParameterFloat>(juce::ParameterID{%s, 1}, %s, juce::NormalisableRange<float>(%s, %s, %s%s), %s));\n' % [cpp_string(symbol), cpp_string(label), _float(spec[key].min), _float(spec[key].max), _float(spec[key].step), ", 0.3f" if key == "cutoff" else "", value]
				pointer_fields += "    std::atomic<float>* %s = nullptr;\n" % symbol
				pointer_init += "        %s = state.getRawParameterValue(%s);\n" % [symbol, cpp_string(symbol)]
				parameter_reads += "        p.%s = %s->load(std::memory_order_relaxed);\n" % [symbol, symbol]
		match node.type:
			"gain":
				stages += "                sample *= v_%s_gain_db;\n" % node.id
				expected += "    expected *= std::pow(10.0f, %s / 20.0f);\n" % _float(node.params.gain_db)
			"filter":
				filter_count += 1
				smoothers += "    float filter%d[2] = {0.0f, 0.0f};\n" % stage_index
				initialise += "        filter%d[0] = filter%d[1] = 0.0f;\n" % [stage_index, stage_index]
				stages += "                filter%d[channel] = (1.0f - v_%s_cutoff) * sample + v_%s_cutoff * filter%d[channel];\n                sample = filter%d[channel];\n" % [stage_index, node.id, node.id, stage_index, stage_index]
			"saturation":
				stages += "                sample += v_%s_mix * (std::tanh(v_%s_drive * sample) / std::tanh(v_%s_drive) - sample);\n" % [node.id, node.id, node.id]
				expected += "    expected += %s * (std::tanh(%s * expected) / std::tanh(%s) - expected);\n" % [_float(node.params.mix), _float(node.params.drive), _float(node.params.drive)]
		stage_index += 1
	var dsp = DSP_TEMPLATE.replace("@FIELDS@", fields).replace("@SMOOTHERS@", smoothers).replace("@INIT@", initialise).replace("@TARGETS@", targets).replace("@TICKS@", ticks).replace("@STAGES@", stages)
	var processor = PROCESSOR_TEMPLATE.replace("@LAYOUT@", layouts).replace("@POINTER_FIELDS@", pointer_fields).replace("@POINTER_INIT@", pointer_init).replace("@READS@", parameter_reads).replace("@TAIL@", str(filter_count * 0.15))
	var plugin: Dictionary = project.data.plugin
	var cmake = CMAKE_TEMPLATE.replace("@JUCE@", JUCE_COMMIT).replace("@NAME@", cmake_string(plugin.name)).replace("@COMPANY@", cmake_string(plugin.company)).replace("@MANUFACTURER@", plugin.manufacturer_code).replace("@CODE@", plugin.plugin_code)
	return {"files": {"CMakeLists.txt": cmake, "Source/GeneratedDSP.h": dsp, "Source/PluginProcessor.cpp": processor, "Tests/DSPTests.cpp": TEST_TEMPLATE.replace("@EXPECTED@", expected), "build-windows.ps1": BUILD_SCRIPT, "README.md": EXPORT_README, "project.signal.json": project.serialize()}}

static func write_project(project: FoundryProject, directory: String) -> String:
	var result = generate(project)
	if result.has("error"):
		return result.error
	# Require an empty destination: never overwrite hand-edited generated projects.
	if DirAccess.dir_exists_absolute(directory):
		var existing = DirAccess.open(directory)
		if existing == null or not existing.get_files().is_empty() or not existing.get_directories().is_empty():
			return "Choose an empty export folder. Existing exports are never overwritten."
	if DirAccess.make_dir_recursive_absolute(directory.path_join("Source")) != OK or DirAccess.make_dir_recursive_absolute(directory.path_join("Tests")) != OK:
		return "Could not create export directories."
	for relative in result.files:
		var file = FileAccess.open(directory.path_join(relative), FileAccess.WRITE)
		if file == null:
			return "Could not write " + relative
		file.store_string(result.files[relative])
		file.flush()
		var error = file.get_error()
		file.close()
		if error != OK:
			return "Write failed for " + relative + ": " + error_string(error)
	return ""

static func _float(value: float) -> String:
	return "%.9ff" % value

const DSP_TEMPLATE = """// Generated by Signal Foundry. Independent of JUCE; C++17.
#pragma once
#include <algorithm>
#include <cmath>

namespace foundry {
struct Parameters {
@FIELDS@};

// Linear 10 ms ramps avoid discontinuous parameter steps. No allocation or locks.
class Ramp {
public:
    void reset(float value) noexcept { current = target = value; remaining = 0; }
    void set(float value, int samples) noexcept {
        if (std::abs(value - target) < 1.0e-7f) return;
        target = value; remaining = std::max(1, samples);
        increment = (target - current) / float(remaining);
    }
    float next() noexcept {
        if (remaining > 0) { current += increment; if (--remaining == 0) current = target; }
        return current;
    }
private:
    float current = 0.0f, target = 0.0f, increment = 0.0f;
    int remaining = 0;
};

class Engine {
public:
    void prepare(double rate, const Parameters& p) noexcept {
        sampleRate = std::max(1.0, rate);
        rampSamples = std::max(1, int(sampleRate * 0.01));
@INIT@    }
    void setParameters(const Parameters& p) noexcept {
@TARGETS@    }
    void process(float* const* channels, int numChannels, int numSamples) noexcept {
        for (int i = 0; i < numSamples; ++i) {
@TICKS@            for (int channel = 0; channel < std::min(numChannels, 2); ++channel) {
                float sample = channels[channel][i];
@STAGES@                channels[channel][i] = sample;
            }
        }
    }
private:
    double sampleRate = 44100.0;
    int rampSamples = 441;
@SMOOTHERS@};
} // namespace foundry
"""

const PROCESSOR_TEMPLATE = """// Generated by Signal Foundry. JUCE 8 stereo VST3 effect.
#include <juce_audio_utils/juce_audio_utils.h>
#include "GeneratedDSP.h"

class FoundryProcessor final : public juce::AudioProcessor {
public:
    using juce::AudioProcessor::processBlock;
    FoundryProcessor()
        : AudioProcessor(BusesProperties().withInput("Input", juce::AudioChannelSet::stereo(), true)
                                          .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          state(*this, nullptr, "FoundryState", makeLayout()) {
@POINTER_INIT@    }
    const juce::String getName() const override { return JucePlugin_Name; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return @TAIL@; }
    bool isBusesLayoutSupported(const BusesLayout& layout) const override {
        return layout.getMainInputChannelSet() == juce::AudioChannelSet::stereo()
            && layout.getMainOutputChannelSet() == juce::AudioChannelSet::stereo();
    }
    void prepareToPlay(double rate, int) override { engine.prepare(rate, readParameters()); }
    void releaseResources() override {}
    void reset() override { engine.prepare(getSampleRate(), readParameters()); }
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) override {
        juce::ScopedNoDenormals noDenormals;
        for (int ch = getTotalNumInputChannels(); ch < buffer.getNumChannels(); ++ch) buffer.clear(ch, 0, buffer.getNumSamples());
        engine.setParameters(readParameters());
        engine.process(buffer.getArrayOfWritePointers(), buffer.getNumChannels(), buffer.getNumSamples());
    }
    bool hasEditor() const override { return true; }
    juce::AudioProcessorEditor* createEditor() override { return new juce::GenericAudioProcessorEditor(*this); }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    void getStateInformation(juce::MemoryBlock& destination) override {
        if (auto xml = state.copyState().createXml()) copyXmlToBinary(*xml, destination);
    }
    void setStateInformation(const void* data, int bytes) override {
        if (auto xml = getXmlFromBinary(data, bytes))
            if (xml->hasTagName(state.state.getType())) state.replaceState(juce::ValueTree::fromXml(*xml));
    }
private:
    static juce::AudioProcessorValueTreeState::ParameterLayout makeLayout() {
        juce::AudioProcessorValueTreeState::ParameterLayout layout;
@LAYOUT@        return layout;
    }
    foundry::Parameters readParameters() const noexcept {
        foundry::Parameters p;
@READS@        return p;
    }
    foundry::Engine engine;
    juce::AudioProcessorValueTreeState state;
@POINTER_FIELDS@    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(FoundryProcessor)
};

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new FoundryProcessor(); }
"""

const CMAKE_TEMPLATE = """cmake_minimum_required(VERSION 3.22)
project(FoundryPlugin VERSION 0.1.0 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
option(FOUNDRY_DSP_ONLY "Build independent DSP tests without JUCE or networking" OFF)
include(CTest)
if(BUILD_TESTING)
    add_executable(FoundryDSPTests Tests/DSPTests.cpp)
    add_test(NAME FoundryDSPTests COMMAND FoundryDSPTests)
endif()
if(FOUNDRY_DSP_ONLY)
    return()
endif()

# Use -DJUCE_SOURCE_DIR=/path/to/JUCE for an existing checkout, or fetch the exact revision.
set(JUCE_SOURCE_DIR "" CACHE PATH "Optional local JUCE checkout")
if(JUCE_SOURCE_DIR)
    add_subdirectory("${JUCE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/JUCE")
else()
    include(FetchContent)
    FetchContent_Declare(JUCE GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
        GIT_TAG @JUCE@)
    FetchContent_MakeAvailable(JUCE)
endif()
juce_add_plugin(FoundryPlugin
    COMPANY_NAME @COMPANY@
    PLUGIN_MANUFACTURER_CODE @MANUFACTURER@
    PLUGIN_CODE @CODE@
    BUNDLE_ID "com.signalfoundry.@MANUFACTURER@.@CODE@"
    FORMATS VST3
    PRODUCT_NAME @NAME@
    IS_SYNTH FALSE NEEDS_MIDI_INPUT FALSE NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE COPY_PLUGIN_AFTER_BUILD FALSE)
target_sources(FoundryPlugin PRIVATE Source/PluginProcessor.cpp)
if(MSVC)
    target_compile_options(FoundryPlugin PRIVATE /utf-8)
endif()
target_compile_definitions(FoundryPlugin PUBLIC JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0)
target_link_libraries(FoundryPlugin PRIVATE juce::juce_audio_utils
    PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_warning_flags)
"""

const BUILD_SCRIPT = """# Requires Windows, Visual Studio 2022 Desktop development with C++, CMake 3.22+, Git.
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    cmake -S . -B build -G "Visual Studio 17 2022" -A x64
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed" }
    cmake --build build --config Release --parallel 2
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
    ctest --test-dir build -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw "DSP tests failed" }
    Write-Host "VST3: build/FoundryPlugin_artefacts/Release/VST3/"
} finally { Pop-Location }
"""

const TEST_TEMPLATE = """#include "../Source/GeneratedDSP.h"
#include <cmath>
#include <iostream>
#include <vector>

int main() {
    foundry::Parameters parameters;
    foundry::Engine engine;
    for (double rate : {44100.0, 48000.0, 96000.0}) {
        const int count = int(rate);
        std::vector<float> left(count, 0.25f), right(count, -0.25f);
        float* channels[] = {left.data(), right.data()};
        engine.prepare(rate, parameters);
        engine.setParameters(parameters);
        engine.process(channels, 2, count);
        float expected = 0.25f;
@EXPECTED@        for (int i = 0; i < count; ++i) {
            if (!std::isfinite(left[i]) || !std::isfinite(right[i]) || std::abs(left[i] + right[i]) > 0.0001f) {
                std::cerr << "Non-finite output or stereo mismatch at " << rate; return 1;
            }
        }
        if (std::abs(left.back() - expected) > 0.001f) {
            std::cerr << "Steady-state transfer mismatch at " << rate << ": " << left.back() << " != " << expected; return 1;
        }
        engine.prepare(rate, parameters);
        std::fill(left.begin(), left.end(), 0.0f); std::fill(right.begin(), right.end(), 0.0f);
        engine.process(channels, 2, count);
        for (float sample : left) if (sample != 0.0f) { std::cerr << "Reset/silence failed"; return 1; }
    }
    std::cout << "PASS: transfer, stereo symmetry, finite output and reset at 44.1/48/96 kHz" << std::endl;
}
"""

const EXPORT_README = """# Generated JUCE effect

This is C++ source, not a compiled plugin. The graph is compiled into a fixed stereo DSP chain.
Exposed parameters appear in JUCE's generic editor, host automation, and saved plugin state.
Unexposed parameters are baked constants. Parameters ramp over 10 ms; filter state is independent per channel.
There is no custom plugin skin, MIDI, instrument synthesis, branching, oversampling, latency compensation, or VST2 support.
The editor's reference-tone audition is a design aid; validate the compiled plugin with real audio.

## Windows VST3

Install Visual Studio 2022 with Desktop development with C++, CMake 3.22+, and Git.
In PowerShell: `powershell -ExecutionPolicy Bypass -File .\\build-windows.ps1`
The first CMake configure fetches pinned JUCE 8.0.6 from GitHub. Offline: configure with
`-DJUCE_SOURCE_DIR=C:/path/to/JUCE` using that revision.
The VST3 bundle is under `build/FoundryPlugin_artefacts/Release/VST3/`.
Copy the entire .vst3 bundle to `%COMMONPROGRAMFILES%/VST3/` and rescan your DAW.
Do not copy a Linux-built plugin into Windows. Build on the target platform.

## DSP checks without JUCE

`cmake -S . -B build-dsp -DFOUNDRY_DSP_ONLY=ON`
`cmake --build build-dsp --config Release`
`ctest --test-dir build-dsp -C Release --output-on-failure`

## Before distributing

Use unique four-character manufacturer/plugin codes. Changing codes or parameter IDs can break DAW sessions.
Review JUCE's current licensing terms at https://juce.com/legal/ before distributing.
Test automation, state recall, sample-rate changes, audio correctness, CPU use, and DAW compatibility on Windows.
Use a plugin validator such as pluginval as part of release qualification. Sign release artifacts as appropriate.
Generated source is an initial implementation; an export does not certify production readiness.
Keep project.signal.json as the editable graph. Re-export into a new empty folder to preserve manual C++ changes.
"""
