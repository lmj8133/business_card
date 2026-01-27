"""Abstract base class for OCR backends."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path


@dataclass
class OCRResult:
    """Result from OCR processing."""

    text: str
    """Extracted text from the image."""

    confidence: float
    """Average confidence score (0.0-1.0)."""

    boxes: list[dict]
    """List of detected text boxes with positions and text."""


class OCRBackend(ABC):
    """Abstract base class for OCR backends."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the name of this OCR backend."""
        ...

    @abstractmethod
    def extract(self, image_path: str | Path) -> OCRResult:
        """
        Extract text from an image.

        Args:
            image_path: Path to the image file.

        Returns:
            OCRResult containing extracted text and metadata.

        Raises:
            FileNotFoundError: If the image file does not exist.
            ValueError: If the image cannot be processed.
        """
        ...
