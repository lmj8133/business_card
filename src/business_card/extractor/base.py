"""Abstract base class for LLM extractors."""

from abc import ABC, abstractmethod

from business_card.models.business_card import BusinessCard


class Extractor(ABC):
    """Abstract base class for LLM extractors."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the name of this extractor."""
        ...

    @abstractmethod
    def extract(self, ocr_text: str) -> BusinessCard:
        """
        Extract structured business card data from OCR text.

        Args:
            ocr_text: Raw text extracted from OCR.

        Returns:
            BusinessCard with extracted information.

        Raises:
            ValueError: If extraction fails or response is invalid.
        """
        ...
