"""One helper for "ask a model for a JSON list of items".

OpenAI first (OPENAI_API_KEY -- the key the voice already uses;
CONTENT_TEXT_MODEL picks the model), then Gemini (GEMINI_API_KEY, via
games.topic_gen's existing integration). Raises LLMError when neither
answers, so callers fall back to their bundled content.
"""

import json
import os
import urllib.request

_OPENAI_CHAT = "https://api.openai.com/v1/chat/completions"
_TIMEOUT = 45


class LLMError(Exception):
    """No model produced a usable JSON list."""


def configured() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY") or os.environ.get("GEMINI_API_KEY"))


def parse_items(text: str) -> list:
    text = (text or "").strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
    try:
        parsed = json.loads(text)
    except Exception as exc:
        raise LLMError(f"could not parse model JSON: {exc}")
    if isinstance(parsed, dict):
        parsed = parsed.get("items")
    if not isinstance(parsed, list):
        raise LLMError("model did not return a list of items")
    return parsed


def _openai(prompt: str, system: str) -> list:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise LLMError("OPENAI_API_KEY is not set")
    body = json.dumps({
        "model": os.environ.get("CONTENT_TEXT_MODEL", "gpt-4o-mini"),
        "temperature": 1.0,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": prompt}],
    }).encode("utf-8")
    req = urllib.request.Request(_OPENAI_CHAT, data=body, headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "User-Agent": "AuroraPlay/1.0 (content)",
    })
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        text = data["choices"][0]["message"]["content"]
    except Exception as exc:
        raise LLMError(f"OpenAI request failed: {exc}")
    return parse_items(text)


def _gemini(prompt: str, system: str) -> list:
    from games import topic_gen
    try:
        model = topic_gen._genai_model(temperature=1.0)
        text = model.generate_content(f"{system}\n\n{prompt}").text
    except topic_gen._GenError as exc:
        raise LLMError(str(exc))
    except Exception as exc:
        raise LLMError(f"Gemini request failed: {exc}")
    return parse_items(text)


def json_items(prompt: str,
               system: str = "You write content for family party games.") -> tuple[list, str]:
    """(raw items, provider). The prompt must ask for {"items": [...]}."""
    errors = []
    for name, call in (("openai", _openai), ("gemini", _gemini)):
        try:
            return call(prompt, system), name
        except LLMError as exc:
            errors.append(f"{name}: {exc}")
    raise LLMError("; ".join(errors))
