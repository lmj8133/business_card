"""LLM extractors for structured data extraction from OCR text."""

from business_card.extractor.base import Extractor
from business_card.extractor.ollama import OllamaExtractor

__all__ = ["Extractor", "OllamaExtractor"]
