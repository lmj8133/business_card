"""Ollama LLM extractor implementation."""

import json
import re

import httpx

from business_card.extractor.base import Extractor
from business_card.models.business_card import (
    BusinessCard,
    Name,
    Company,
    Phone,
    Contact,
    Address,
)

SYSTEM_PROMPT = """You are a business card information extractor.
Extract structured contact information from OCR text of a business card.

Return ONLY a valid JSON object with the following structure (no markdown, no explanation):
{
  "name": {
    "full_name": "string (required)",
    "first_name": "string or null",
    "last_name": "string or null"
  },
  "company": {
    "name": "string or null",
    "department": "string or null"
  },
  "title": "string or null",
  "contact": {
    "phones": [{"number": "string", "type": "office|mobile|fax|other"}],
    "emails": ["string"],
    "websites": ["string"]
  },
  "address": {
    "full_address": "string or null",
    "city": "string or null",
    "state": "string or null",
    "postal_code": "string or null",
    "country": "string or null"
  },
  "confidence": 0.0-1.0
}

Guidelines:
- Extract all visible information from the OCR text
- Normalize phone numbers (keep country codes if present)
- Identify phone types: mobile numbers typically start with cell prefixes, office phones have extensions
- For names, try to split into first/last name if possible
- Set confidence based on OCR text quality and completeness
- If information is unclear or missing, use null
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
        # Try to extract JSON from the response
        json_str = self._extract_json(response)

        try:
            data = json.loads(json_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON response from LLM: {e}") from e

        # Build BusinessCard from parsed data
        name_data = data.get("name", {})
        name = Name(
            full_name=name_data.get("full_name", "Unknown"),
            first_name=name_data.get("first_name"),
            last_name=name_data.get("last_name"),
        )

        company_data = data.get("company", {})
        company = Company(
            name=company_data.get("name"),
            department=company_data.get("department"),
        )

        contact_data = data.get("contact", {})
        phones = [
            Phone(
                number=p.get("number", ""),
                type=p.get("type", "other"),
            )
            for p in contact_data.get("phones", [])
            if p.get("number")
        ]
        contact = Contact(
            phones=phones,
            emails=contact_data.get("emails", []),
            websites=contact_data.get("websites", []),
        )

        address_data = data.get("address", {})
        address = Address(
            full_address=address_data.get("full_address"),
            city=address_data.get("city"),
            state=address_data.get("state"),
            postal_code=address_data.get("postal_code"),
            country=address_data.get("country"),
        )

        return BusinessCard(
            name=name,
            company=company,
            title=data.get("title"),
            contact=contact,
            address=address,
            raw_text=ocr_text,
            confidence=data.get("confidence", 0.0),
        )

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
