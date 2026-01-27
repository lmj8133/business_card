"""Main business card parser controller."""

import time
from pathlib import Path

from business_card.models.business_card import BusinessCard, Metadata
from business_card.ocr.base import OCRBackend
from business_card.extractor.base import Extractor


class BusinessCardParser:
    """Main controller for parsing business card images."""

    def __init__(self, ocr: OCRBackend, extractor: Extractor):
        """
        Initialize the parser with OCR and extractor backends.

        Args:
            ocr: OCR backend for text extraction.
            extractor: LLM extractor for structured data extraction.
        """
        self._ocr = ocr
        self._extractor = extractor

    def parse(self, image_path: str | Path) -> BusinessCard:
        """
        Parse a business card image and extract structured information.

        Args:
            image_path: Path to the business card image.

        Returns:
            BusinessCard with extracted information.

        Raises:
            FileNotFoundError: If the image file does not exist.
            ValueError: If OCR or extraction fails.
        """
        start_time = time.perf_counter()

        # Step 1: OCR
        ocr_result = self._ocr.extract(image_path)

        if not ocr_result.text.strip():
            raise ValueError("OCR extracted no text from the image")

        # Step 2: LLM extraction
        card = self._extractor.extract(ocr_result.text)

        # Step 3: Add metadata
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        card.metadata = Metadata(
            ocr_backend=self._ocr.name,
            extractor_backend=self._extractor.name,
            processing_time_ms=round(elapsed_ms, 2),
        )

        return card

    def parse_ocr_only(self, image_path: str | Path) -> str:
        """
        Run only OCR on the image, without LLM extraction.

        Useful for debugging or checking OCR quality.

        Args:
            image_path: Path to the business card image.

        Returns:
            Raw OCR text.
        """
        ocr_result = self._ocr.extract(image_path)
        return ocr_result.text
