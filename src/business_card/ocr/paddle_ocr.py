"""PaddleOCR backend implementation."""

import os
from pathlib import Path

from paddleocr import PaddleOCR

from business_card.ocr.base import OCRBackend, OCRResult


# Disable OneDNN/MKLDNN to avoid PIR compatibility issues with PaddlePaddle 3.x
# See: https://github.com/PaddlePaddle/PaddleOCR/discussions/17350
os.environ.setdefault("FLAGS_use_mkldnn", "0")


class PaddleOCRBackend(OCRBackend):
    """OCR backend using PaddleOCR."""

    def __init__(
        self,
        lang: str = "en",
    ):
        """
        Initialize PaddleOCR backend.

        Args:
            lang: Language for OCR. Default is "en" for English.
        """
        self._lang = lang
        self._ocr = PaddleOCR(lang=lang, enable_mkldnn=False)

    @property
    def name(self) -> str:
        return f"paddleocr:{self._lang}"

    def extract(self, image_path: str | Path) -> OCRResult:
        """Extract text from an image using PaddleOCR."""
        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Image not found: {path}")

        result = self._ocr.predict(str(path))

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
            boxes.append(
                {
                    "box": poly.tolist() if hasattr(poly, "tolist") else poly,
                    "text": text,
                    "confidence": float(score),
                }
            )

        avg_confidence = sum(scores) / len(scores) if scores else 0.0

        return OCRResult(
            text="\n".join(texts),
            confidence=float(avg_confidence),
            boxes=boxes,
        )
