"""Tests for business card parser."""

import json
import pytest
from unittest.mock import Mock

from business_card.models.business_card import BusinessCard
from business_card.ocr.base import OCRBox, OCRResult
from business_card.parser import BusinessCardParser
from business_card.extractor.ollama import OllamaExtractor


class TestBusinessCardModels:
    """Test Pydantic models."""

    def test_business_card_minimal(self):
        """Test BusinessCard with minimal required fields."""
        card = BusinessCard(
            name="Test User",
            raw_text="OCR text here",
        )
        assert card.name == "Test User"
        assert card.raw_text == "OCR text here"
        assert card.confidence == 0.0
        assert card.company is None
        assert card.department is None
        assert card.title is None
        assert card.email is None

    def test_business_card_full(self):
        """Test BusinessCard with all fields."""
        card = BusinessCard(
            company="Tech Corp",
            name="John Doe",
            department="Engineering",
            title="Senior Engineer",
            email="john@techcorp.com",
            raw_text="Full OCR text",
            confidence=0.95,
        )
        assert card.name == "John Doe"
        assert card.company == "Tech Corp"
        assert card.department == "Engineering"
        assert card.title == "Senior Engineer"
        assert card.email == "john@techcorp.com"
        assert card.confidence == 0.95

    def test_business_card_json_serialization(self):
        """Test BusinessCard can be serialized to JSON."""
        card = BusinessCard(
            name="Test User",
            raw_text="Test",
        )
        json_str = card.model_dump_json()
        data = json.loads(json_str)
        assert data["name"] == "Test User"

    def test_business_card_confidence_bounds(self):
        """Test confidence field bounds validation."""
        # Valid confidence
        card = BusinessCard(name="Test", raw_text="text", confidence=0.5)
        assert card.confidence == 0.5

        # Boundary values
        card = BusinessCard(name="Test", raw_text="text", confidence=0.0)
        assert card.confidence == 0.0

        card = BusinessCard(name="Test", raw_text="text", confidence=1.0)
        assert card.confidence == 1.0


class TestBusinessCardParser:
    """Test BusinessCardParser controller."""

    def test_parse_success(self):
        """Test successful parsing with mocked backends."""
        # Mock OCR backend
        mock_ocr = Mock()
        mock_ocr.name = "mock-ocr"
        mock_ocr.extract.return_value = OCRResult(
            text="John Doe\nSoftware Engineer\njohn@example.com",
            confidence=0.95,
            boxes=[],
        )

        # Mock extractor
        mock_extractor = Mock()
        mock_extractor.name = "mock-extractor"
        mock_extractor.extract.return_value = BusinessCard(
            name="John Doe",
            title="Software Engineer",
            email="john@example.com",
            raw_text="John Doe\nSoftware Engineer\njohn@example.com",
            confidence=0.9,
        )

        parser = BusinessCardParser(ocr=mock_ocr, extractor=mock_extractor)
        result = parser.parse("dummy.jpg")

        assert result.name == "John Doe"
        assert result.title == "Software Engineer"
        assert result.email == "john@example.com"
        assert result.metadata is not None
        assert result.metadata.ocr_backend == "mock-ocr"
        assert result.metadata.extractor_backend == "mock-extractor"

    def test_parse_empty_ocr_raises(self):
        """Test that empty OCR result raises ValueError."""
        mock_ocr = Mock()
        mock_ocr.extract.return_value = OCRResult(text="", confidence=0.0, boxes=[])
        mock_extractor = Mock()

        parser = BusinessCardParser(ocr=mock_ocr, extractor=mock_extractor)

        with pytest.raises(ValueError, match="OCR extracted no text"):
            parser.parse("dummy.jpg")

    def test_parse_ocr_only(self):
        """Test OCR-only mode."""
        mock_ocr = Mock()
        mock_ocr.extract.return_value = OCRResult(
            text="Test OCR output",
            confidence=0.9,
            boxes=[],
        )
        mock_extractor = Mock()

        parser = BusinessCardParser(ocr=mock_ocr, extractor=mock_extractor)
        result = parser.parse_ocr_only("dummy.jpg")

        assert result == "Test OCR output"
        mock_extractor.extract.assert_not_called()


class TestOCRResult:
    """Test OCRResult dataclass."""

    def test_ocr_result_creation(self):
        """Test OCRResult can be created with OCRBox."""
        box = OCRBox(text="Hello", confidence=0.95, bbox=(0.0, 0.0, 100.0, 20.0))
        result = OCRResult(
            text="Hello World",
            confidence=0.95,
            boxes=[box],
        )
        assert result.text == "Hello World"
        assert result.confidence == 0.95
        assert len(result.boxes) == 1
        assert result.boxes[0].text == "Hello"


class TestOCRBox:
    """Test OCRBox dataclass."""

    def test_ocr_box_creation(self):
        """Test OCRBox can be created."""
        box = OCRBox(text="Test", confidence=0.9, bbox=(10.0, 20.0, 110.0, 50.0))
        assert box.text == "Test"
        assert box.confidence == 0.9
        assert box.bbox == (10.0, 20.0, 110.0, 50.0)

    def test_ocr_box_center_y(self):
        """Test OCRBox center_y property."""
        box = OCRBox(text="Test", confidence=0.9, bbox=(0.0, 100.0, 50.0, 140.0))
        assert box.center_y == 120.0  # (100 + 140) / 2

    def test_ocr_box_x_min(self):
        """Test OCRBox x_min property."""
        box = OCRBox(text="Test", confidence=0.9, bbox=(25.0, 100.0, 75.0, 140.0))
        assert box.x_min == 25.0


class TestOllamaExtractor:
    """Test OllamaExtractor methods."""

    def test_extract_json_from_code_block(self):
        """Test extracting JSON from markdown code blocks."""
        extractor = OllamaExtractor()

        text = '```json\n{"name": "Test"}\n```'
        result = extractor._extract_json(text)
        assert result == '{"name": "Test"}'

    def test_extract_json_raw(self):
        """Test extracting raw JSON object."""
        extractor = OllamaExtractor()

        text = 'Some text {"name": "Test"} more text'
        result = extractor._extract_json(text)
        assert result == '{"name": "Test"}'

    def test_extractor_name(self):
        """Test extractor name property."""
        extractor = OllamaExtractor(model="llama3.2")
        assert extractor.name == "ollama:llama3.2"

        extractor = OllamaExtractor(model="qwen2")
        assert extractor.name == "ollama:qwen2"

    def test_to_str_with_string(self):
        """Test _to_str returns string as-is."""
        extractor = OllamaExtractor()
        assert extractor._to_str("hello") == "hello"

    def test_to_str_with_none(self):
        """Test _to_str returns None for None input."""
        extractor = OllamaExtractor()
        assert extractor._to_str(None) is None

    def test_to_str_with_list(self):
        """Test _to_str takes first element from list."""
        extractor = OllamaExtractor()
        assert extractor._to_str(["first", "second"]) == "first"

    def test_to_str_with_empty_list(self):
        """Test _to_str returns None for empty list."""
        extractor = OllamaExtractor()
        assert extractor._to_str([]) is None

    def test_to_str_with_number(self):
        """Test _to_str converts number to string."""
        extractor = OllamaExtractor()
        assert extractor._to_str(123) == "123"
        assert extractor._to_str(0.95) == "0.95"
