"""PaddleOCR backend implementation."""

import logging
import os
import tempfile
from pathlib import Path

import cv2
from paddleocr import PaddleOCR

from business_card.ocr.base import OCRBackend, OCRBox, OCRResult
from business_card.preprocessing import CardDetector

logger = logging.getLogger(__name__)


# Disable OneDNN/MKLDNN to avoid PIR compatibility issues with PaddlePaddle 3.x
# See: https://github.com/PaddlePaddle/PaddleOCR/discussions/17350
os.environ.setdefault("FLAGS_use_mkldnn", "0")


class PaddleOCRBackend(OCRBackend):
    """OCR backend using PaddleOCR."""

    def __init__(
        self,
        lang: str = "en",
        auto_crop: bool = True,
    ):
        """
        Initialize PaddleOCR backend.

        Args:
            lang: Language for OCR. Default is "en" for English.
            auto_crop: Enable automatic card region detection and cropping.
        """
        self._lang = lang
        self._auto_crop = auto_crop
        self._detector = CardDetector() if auto_crop else None
        self._ocr = PaddleOCR(lang=lang, enable_mkldnn=False)

    @property
    def name(self) -> str:
        return f"paddleocr:{self._lang}"

    def extract(self, image_path: str | Path) -> OCRResult:
        """Extract text from an image using PaddleOCR."""
        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Image not found: {path}")

        # Try auto-crop to reduce image size and focus on card region
        temp_path = None
        ocr_input = str(path)

        if self._detector:
            cropped = self._detector.detect(path, fallback_resize=True)
            if cropped is not None:
                # Save cropped image to temp file
                fd, temp_file = tempfile.mkstemp(suffix=".jpg")
                os.close(fd)
                temp_path = Path(temp_file)
                cv2.imwrite(str(temp_path), cropped)
                ocr_input = str(temp_path)
                logger.debug("Auto-cropped card region saved to: %s", temp_path)

        try:
            result = self._ocr.predict(ocr_input)
        finally:
            # Clean up temp file
            if temp_path and temp_path.exists():
                temp_path.unlink()

        if not result or not result[0]:
            return OCRResult(text="", confidence=0.0, boxes=[])

        # PaddleOCR 3.x returns OCRResult objects with rec_texts, rec_scores, rec_polys
        ocr_result = result[0]
        texts = ocr_result.get("rec_texts", [])
        scores = ocr_result.get("rec_scores", [])
        polys = ocr_result.get("rec_polys", [])

        if not texts:
            return OCRResult(text="", confidence=0.0, boxes=[])

        boxes = []
        for text, score, poly in zip(texts, scores, polys):
            # Convert polygon to bounding box (x_min, y_min, x_max, y_max)
            poly_list = poly.tolist() if hasattr(poly, "tolist") else poly
            xs = [p[0] for p in poly_list]
            ys = [p[1] for p in poly_list]
            bbox = (min(xs), min(ys), max(xs), max(ys))
            boxes.append(
                OCRBox(
                    text=text,
                    confidence=float(score),
                    bbox=bbox,
                )
            )

        avg_confidence = sum(scores) / len(scores) if scores else 0.0

        return OCRResult(
            text="\n".join(texts),
            confidence=float(avg_confidence),
            boxes=boxes,
        )
