"""Tests for batch processing."""

import json
from pathlib import Path
from unittest.mock import Mock

from business_card.batch import BatchProcessor, BatchResult
from business_card.models.business_card import BusinessCard


class TestBatchResult:
    """Test BatchResult dataclass."""

    def test_empty_result(self):
        """Test empty batch result."""
        result = BatchResult()
        assert result.total == 0
        assert result.succeeded == 0
        assert result.failed == 0

    def test_result_with_successes(self):
        """Test batch result with successful items."""
        result = BatchResult(
            results=[{"image_path": "a.jpg"}, {"image_path": "b.jpg"}],
            errors=[],
            total_time_ms=100.0,
        )
        assert result.total == 2
        assert result.succeeded == 2
        assert result.failed == 0

    def test_result_with_mixed(self):
        """Test batch result with mixed success/failure."""
        result = BatchResult(
            results=[{"image_path": "a.jpg"}],
            errors=[{"image_path": "bad.jpg", "error": "OCR failed"}],
            total_time_ms=200.0,
        )
        assert result.total == 2
        assert result.succeeded == 1
        assert result.failed == 1


class TestBatchProcessor:
    """Test BatchProcessor class."""

    def _mock_parser(self, success_cards: dict[str, BusinessCard] | None = None):
        """Create a mock parser."""
        mock_ocr = Mock()
        mock_ocr.name = "mock-ocr"

        mock_extractor = Mock()
        mock_extractor.name = "mock-extractor"

        mock_parser = Mock()

        def parse_side_effect(path):
            path_str = str(path)
            if success_cards and path_str in success_cards:
                return success_cards[path_str]
            if "bad" in path_str or "fail" in path_str:
                raise ValueError("OCR extracted no text")
            return BusinessCard(
                name="Test User",
                company="Test Corp",
                raw_text="test",
                confidence=0.9,
            )

        mock_parser.parse.side_effect = parse_side_effect
        return mock_parser

    def test_process_success(self):
        """Test processing multiple images successfully."""
        parser = self._mock_parser()
        processor = BatchProcessor(parser)

        result = processor.process([Path("a.jpg"), Path("b.jpg")])

        assert result.succeeded == 2
        assert result.failed == 0
        assert len(result.results) == 2
        assert result.results[0]["image_path"] == "a.jpg"
        assert result.results[1]["image_path"] == "b.jpg"

    def test_process_with_errors(self):
        """Test processing with some failures - errors are isolated."""
        parser = self._mock_parser()
        processor = BatchProcessor(parser)

        result = processor.process([Path("good.jpg"), Path("bad.jpg")])

        assert result.succeeded == 1
        assert result.failed == 1
        assert result.results[0]["image_path"] == "good.jpg"
        assert result.errors[0]["image_path"] == "bad.jpg"
        assert "OCR extracted no text" in result.errors[0]["error"]

    def test_collect_images_from_files(self, tmp_path):
        """Test collecting images from file list."""
        # Create test files
        (tmp_path / "a.jpg").touch()
        (tmp_path / "b.png").touch()
        (tmp_path / "c.txt").touch()  # Non-image, should be ignored

        processor = BatchProcessor(Mock())
        images = processor.collect_images([
            tmp_path / "a.jpg",
            tmp_path / "b.png",
            tmp_path / "c.txt",
        ])

        assert len(images) == 2
        assert all(p.suffix in (".jpg", ".png") for p in images)

    def test_collect_images_from_directory(self, tmp_path):
        """Test collecting images from directory."""
        (tmp_path / "card1.jpg").touch()
        (tmp_path / "card2.PNG").touch()  # Uppercase extension
        (tmp_path / "notes.txt").touch()

        processor = BatchProcessor(Mock())
        images = processor.collect_images([tmp_path])

        assert len(images) == 2

    def test_to_json(self):
        """Test JSON output format."""
        parser = self._mock_parser()
        processor = BatchProcessor(parser)

        result = BatchResult(
            results=[{"image_path": "a.jpg", "name": "Test", "confidence": 0.9}],
            errors=[{"image_path": "bad.jpg", "error": "Failed"}],
            total_time_ms=123.45,
        )

        json_str = processor.to_json(result)
        data = json.loads(json_str)

        assert data["metadata"]["total"] == 2
        assert data["metadata"]["succeeded"] == 1
        assert data["metadata"]["failed"] == 1
        assert data["metadata"]["total_time_ms"] == 123.45
        assert len(data["results"]) == 1
        assert len(data["errors"]) == 1

    def test_to_csv(self):
        """Test CSV output format."""
        parser = self._mock_parser()
        processor = BatchProcessor(parser)

        result = BatchResult(
            results=[{
                "image_path": "a.jpg",
                "name": "John Doe",
                "company": "Tech Corp",
                "confidence": 0.9,
            }],
            errors=[{"image_path": "bad.jpg", "error": "OCR failed"}],
            total_time_ms=100.0,
        )

        csv_str = processor.to_csv(result)
        lines = csv_str.strip().split("\n")

        # Header + 2 data rows
        assert len(lines) == 3
        assert "image_path" in lines[0]
        assert "a.jpg" in lines[1]
        assert "John Doe" in lines[1]
        assert "bad.jpg" in lines[2]
        assert "OCR failed" in lines[2]
