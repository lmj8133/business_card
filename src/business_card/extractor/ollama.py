"""Ollama LLM extractor implementation."""

import json
import re
from typing import Any

import httpx

from business_card.extractor.base import Extractor
from business_card.models.business_card import BusinessCard

SYSTEM_PROMPT = """You are a business card information extractor.
Extract structured contact information from OCR text.

Return ONLY a valid JSON object with this structure (no markdown, no explanation):
{
  "company": "string or null",
  "name": "string (required)",
  "position": "string or null (combine department and title, e.g. 'Sales Dept, Manager')",
  "email": "string or null",
  "confidence": 0.0-1.0
}

Guidelines:
- Cross-validate company name with email domain (e.g., if email is "@algoltek.com", company is likely "Algoltek")
- Cross-validate name with email prefix (e.g., "jeff.fu@" suggests name is "Jeff Fu"; use to fix OCR errors like "Jeft Fu" -> "Jeff Fu")
- Cross-validate email prefix with name (e.g., if name is "Jeff Fu" but email shows "jeft.fu@", correct to "jeff.fu@")
- When name and email prefix conflict, prefer email (more reliable OCR) unless email is abbreviated or doesn't contain name info
- If multiple emails exist, pick the primary one (typically the person's own email)
- Split names by case transitions: "MJLi" -> "MJ Li", "JohnSmith" -> "John Smith"
- Common OCR confusions: L↔I, O↔0, 1↔l - use context to resolve
- Always return valid JSON"""

USER_PROMPT_TEMPLATE = """Extract business card information from this OCR text:

---
{ocr_text}
---

Return only the JSON object."""


class OllamaExtractor(Extractor):
    """Extractor using local Ollama LLM."""

    def __init__(
        self,
        model: str = "llama3.2",
        base_url: str = "http://localhost:11434",
        timeout: float = 60.0,
    ):
        """
        Initialize Ollama extractor.

        Args:
            model: Ollama model name (e.g., "llama3.2", "qwen2").
            base_url: Ollama API base URL.
            timeout: Request timeout in seconds.
        """
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

    @property
    def name(self) -> str:
        return f"ollama:{self._model}"

    def extract(self, ocr_text: str) -> BusinessCard:
        """Extract business card data using Ollama."""
        if not ocr_text.strip():
            raise ValueError("OCR text is empty")

        response = self._call_ollama(ocr_text)
        return self._parse_response(response, ocr_text)

    def _call_ollama(self, ocr_text: str) -> str:
        """Call Ollama API and return the response text."""
        url = f"{self._base_url}/api/generate"
        payload = {
            "model": self._model,
            "prompt": USER_PROMPT_TEMPLATE.format(ocr_text=ocr_text),
            "system": SYSTEM_PROMPT,
            "stream": False,
            "format": "json",
        }

        with httpx.Client(timeout=self._timeout) as client:
            try:
                resp = client.post(url, json=payload)
                resp.raise_for_status()
            except httpx.ConnectError as e:
                raise ValueError(
                    f"Cannot connect to Ollama at {self._base_url}. "
                    "Is Ollama running? Start it with: ollama serve"
                ) from e
            except httpx.HTTPStatusError as e:
                raise ValueError(f"Ollama API error: {e.response.text}") from e

        data = resp.json()
        return data.get("response", "")

    def _parse_response(self, response: str, ocr_text: str) -> BusinessCard:
        """Parse Ollama response into BusinessCard."""
        json_str = self._extract_json(response)

        try:
            data = json.loads(json_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON response from LLM: {e}") from e

        return BusinessCard(
            company=self._to_str(data.get("company")),
            name=self._to_str(data.get("name")) or "Unknown",
            position=self._to_str(data.get("position")),
            email=self._to_str(data.get("email")),
            raw_text=ocr_text,
            confidence=data.get("confidence", 0.0),
        )

    def _to_str(self, value: Any) -> str | None:
        """Convert value to string, handling lists by taking first element."""
        if value is None:
            return None
        if isinstance(value, list):
            return value[0] if value else None
        return str(value)

    def _extract_json(self, text: str) -> str:
        """Extract JSON from text, handling potential markdown code blocks."""
        # Try to find JSON in code blocks first
        code_block_match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
        if code_block_match:
            return code_block_match.group(1).strip()

        # Try to find raw JSON object
        json_match = re.search(r"\{[\s\S]*\}", text)
        if json_match:
            return json_match.group(0)

        return text.strip()
