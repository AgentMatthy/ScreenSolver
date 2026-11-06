import QtQuick
import Quickshell
import qs.config

// OpenRouter (OpenAI-compatible chat completions with image input).
Provider {
    id: root

    readonly property var cfg: Config.options.openrouter

    key: "openrouter"
    displayName: "OpenRouter"
    model: cfg.model

    readonly property string apiKey: cfg.apiKey || Quickshell.env("OPENROUTER_API_KEY") || ""

    property var _xhr: null

    function validate(): string {
        if (!root.apiKey)
            return `No OpenRouter API key set.\nAdd it to "openrouter.apiKey" in ${Paths.configFile}`;
        if (!root.cfg.model)
            return `No model set in "openrouter.model" (${Paths.configFile})`;
        return "";
    }

    function buildBody(req) {
        const messages = [];
        if (req.systemPrompt)
            messages.push({ role: "system", content: req.systemPrompt });
        messages.push({
            role: "user",
            content: [
                { type: "text", text: req.prompt },
                { type: "image_url", image_url: { url: `data:${req.mimeType};base64,${req.imageBase64}` } }
            ]
        });

        const body = { model: root.cfg.model, messages: messages };
        if (root.cfg.maxTokens > 0) body.max_tokens = root.cfg.maxTokens;
        if (root.cfg.temperature >= 0) body.temperature = root.cfg.temperature;

        const extra = root.cfg.extraBody;
        if (extra && typeof extra === "object")
            for (const k in extra) body[k] = extra[k];
        return body;
    }

    function solve(req) {
        root.cancel();

        const problem = root.validate();
        if (problem) {
            root.failed(problem);
            return;
        }

        const xhr = new XMLHttpRequest();
        root._xhr = xhr;
        root.busy = true;

        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || root._xhr !== xhr) return;
            root._xhr = null;
            root.busy = false;
            timeout.stop();
            root._handleResponse(xhr.status, xhr.responseText);
        };

        xhr.open("POST", root.cfg.endpoint);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Authorization", `Bearer ${root.apiKey}`);
        xhr.setRequestHeader("HTTP-Referer", "https://github.com/screensolver");
        xhr.setRequestHeader("X-Title", "ScreenSolver");
        xhr.send(JSON.stringify(root.buildBody(req)));

        timeout.interval = Math.max(1000, root.cfg.timeoutMs);
        timeout.restart();
    }

    function cancel() {
        timeout.stop();
        const xhr = root._xhr;
        root._xhr = null;
        root.busy = false;
        if (xhr) xhr.abort();
    }

    function _handleResponse(status, text) {
        let json = null;
        try {
            json = JSON.parse(text);
        } catch (e) {}

        if (status === 0) {
            root.failed("Network error: could not reach OpenRouter");
            return;
        }
        if (status < 200 || status >= 300 || json?.error) {
            let msg = json?.error?.message ?? (text || "no response body");
            if (status === 401) msg += `\nCheck "openrouter.apiKey" in ${Paths.configFile}`;
            root.failed(`OpenRouter error (${status}): ${msg}`);
            return;
        }

        const choice = json?.choices?.[0];
        let content = choice?.message?.content;
        // Some models return content as an array of parts.
        if (Array.isArray(content))
            content = content.map(p => p.text ?? "").join("");
        content = (content ?? "").trim();

        if (!content) {
            root.failed(`Empty response from model (finish reason: ${choice?.finish_reason ?? "unknown"})`);
            return;
        }
        root.succeeded(content);
    }

    property Timer _timeout: Timer {
        id: timeout
        repeat: false
        onTriggered: {
            if (!root._xhr) return;
            root.cancel();
            root.failed(`Request timed out after ${Math.round(interval / 1000)}s`);
        }
    }
}
