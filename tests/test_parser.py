"""Tests for business card parser."""

import json
import pytest
from unittest.mock import Mock

from business_card.models.business_card import (
    BusinessCard,
    Name,
    Company,
    Phone,
    Contact,
    Address,
)
from business_card.ocr.base import OCRResult
from business_card.parser import BusinessCardParser


class TestBusinessCardModels:
    """Test Pydantic models."""

    def test_name_model_full(self):
        """Test Name model with all fields."""
        name = Name(full_name="John Doe", first_name="John", last_name="Doe")
        assert name.full_name == "John Doe"
        assert name.first_name == "John"
        assert name.last_name == "Doe"

    def test_name_model_minimal(self):
        """Test Name model with only required fields."""
        name = Name(full_name="John Doe")
        assert name.full_name == "John Doe"
        assert name.first_name is None
        assert name.last_name is None

    def test_phone_model_default_type(self):
        """Test Phone model default type."""
        phone = Phone(number="+1-234-567-8900")
        assert phone.number == "+1-234-567-8900"
        assert phone.type == "other"

    def test_phone_model_with_type(self):
        """Test Phone model with explicit type."""
        phone = Phone(number="+1-234-567-8900", type="mobile")
        assert phone.type == "mobile"

    def test_business_card_minimal(self):
        """Test BusinessCard with minimal required fields."""
        card = BusinessCard(
            name=Name(full_name="Test User"),
            raw_text="OCR text here",
        )
        assert card.name.full_name == "Test User"
        assert card.raw_text == "OCR text here"
        assert card.confidence == 0.0
        assert card.company.name is None
        assert card.contact.phones == []

    def test_business_card_full(self):
        """Test BusinessCard with all fields."""
        card = BusinessCard(
            name=Name(full_name="John Doe", first_name="John", last_name="Doe"),
            company=Company(name="Tech Corp", department="Engineering"),
            title="Senior Engineer",
            contact=Contact(
                phones=[Phone(number="+1-555-1234", type="office")],
                emails=["john@techcorp.com"],
                websites=["https://techcorp.com"],
            ),
            address=Address(
                full_address="123 Main St, SF, CA 94102",
                city="San Francisco",
                state="CA",
                postal_code="94102",
                country="USA",
            ),
            raw_text="Full OCR text",
            confidence=0.95,
        )
        assert card.name.full_name == "John Doe"
        assert card.company.name == "Tech Corp"
        assert card.title == "Senior Engineer"
        assert len(card.contact.phones) == 1
        assert card.contact.phones[0].type == "office"
        assert card.address.city == "San Francisco"
        assert card.confidence == 0.95

    def test_business_card_json_serialization(self):
        """Test BusinessCard can be serialized to JSON."""
        card = BusinessCard(
            name=Name(full_name="Test User"),
            raw_text="Test",
        )
        json_str = card.model_dump_json()
        data = json.loads(json_str)
        assert data["name"]["full_name"] == "Test User"


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
            name=Name(full_name="John Doe"),
            title="Software Engineer",
            contact=Contact(emails=["john@example.com"]),
            raw_text="John Doe\nSoftware Engineer\njohn@example.com",
            confidence=0.9,
        )

        parser = BusinessCardParser(ocr=mock_ocr, extractor=mock_extractor)
        result = parser.parse("dummy.jpg")

        assert result.name.full_name == "John Doe"
        assert result.title == "Software Engineer"
        assert "john@example.com" in result.contact.emails
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
        """Test OCRResult can be created."""
        result = OCRResult(
            text="Hello World",
            confidence=0.95,
            boxes=[{"box": [[0, 0], [100, 0], [100, 20], [0, 20]], "text": "Hello"}],
        )
        assert result.text == "Hello World"
        assert result.confidence == 0.95
        assert len(result.boxes) == 1
