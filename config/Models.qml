pragma Singleton
import QtQuick
import Quickshell

// Built-in catalog of vision-capable OpenRouter models offered out of the box.
// `openrouter.models` defaults to all of these; Settings → Models can re-add any
// that were removed. Names are only used for display — the id is what's sent.
Singleton {
    id: root

    readonly property var presets: [
        // Google
        { id: "google/gemini-4-argon",       name: "Gemini 4 Argon" },
        { id: "google/gemini-3.8-flash",     name: "Gemini 3.8 Flash" },
        { id: "google/gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite" },
        // Anthropic
        { id: "anthropic/claude-fable-5.1",  name: "Claude Fable 5.1" },
        { id: "anthropic/claude-opus-5.5",   name: "Claude Opus 5.5" },
        { id: "anthropic/claude-sonnet-5.5", name: "Claude Sonnet 5.5" },
        { id: "anthropic/claude-haiku-5.5",  name: "Claude Haiku 5.5" },
        // OpenAI
        { id: "openai/gpt-6-astra",          name: "GPT-6 Astra" },
        { id: "openai/gpt-6.1-sol",          name: "GPT-6.1 Sol" },
        { id: "openai/gpt-6.1-terra",        name: "GPT-6.1 Terra" },
        { id: "openai/gpt-6-luna",           name: "GPT-6 Luna" },
        // Others
        { id: "z-ai/glm-5.3-flash",          name: "GLM 5.3 Flash" },
        { id: "tencent/hy4",                 name: "Hy4" },
        { id: "moonshotai/kimi-k3.1-pro",    name: "Kimi K3.1 Pro" }
    ]

    readonly property var ids: presets.map(p => p.id)

    // Display name for an id; falls back to the part after the provider slash.
    function nameOf(id: string): string {
        const p = presets.find(p => p.id === id);
        return p ? p.name : id.slice(id.indexOf("/") + 1);
    }

    function providerOf(id: string): string {
        const i = id.indexOf("/");
        return i > 0 ? id.slice(0, i) : "";
    }
}
