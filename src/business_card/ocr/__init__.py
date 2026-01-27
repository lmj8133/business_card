"""OCR backends for text extraction from images."""

from business_card.ocr.base import OCRBackend, OCRResult
from business_card.ocr.paddle_ocr import PaddleOCRBackend

__all__ = ["OCRBackend", "OCRResult", "PaddleOCRBackend"]
