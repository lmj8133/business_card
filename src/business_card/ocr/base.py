"""Abstract base class for OCR backends."""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class OCRBox:
    """Single OCR detection with position."""

    text: str
    """Detected text content."""

    confidence: float
    """Confidence score (0.0-1.0)."""

    bbox: tuple[float, float, float, float]
    """Bounding box as (x_min, y_min, x_max, y_max)."""

    @property
    def center_y(self) -> float:
        """Vertical center for line grouping."""
        return (self.bbox[1] + self.bbox[3]) / 2

    @property
    def x_min(self) -> float:
        """Left edge x coordinate."""
        return self.bbox[0]


@dataclass
class OCRResult:
    """Result from OCR processing."""

    text: str
    """Extracted text from the image."""

    confidence: float
    """Average confidence score (0.0-1.0)."""

    boxes: list[OCRBox] = field(default_factory=list)
    """List of detected text boxes with positions."""


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
