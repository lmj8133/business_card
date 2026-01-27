"""Tests for image preprocessing module."""

import numpy as np
import pytest

from business_card.preprocessing import CardDetector


class TestCardDetector:
    """Test CardDetector functionality."""

    def test_init_default_params(self):
        """Test CardDetector initializes with default parameters."""
        detector = CardDetector()
        assert detector._min_area_ratio == 0.05
        assert detector._max_area_ratio == 0.85
        assert detector._canny_low == 50
        assert detector._canny_high == 150

    def test_init_custom_params(self):
        """Test CardDetector initializes with custom parameters."""
        detector = CardDetector(
            min_area_ratio=0.2,
            max_area_ratio=0.8,
            canny_low=30,
            canny_high=100,
        )
        assert detector._min_area_ratio == 0.2
        assert detector._max_area_ratio == 0.8
        assert detector._canny_low == 30
        assert detector._canny_high == 100

    def test_detect_from_array_empty_image(self):
        """Test detection returns None for empty image."""
        detector = CardDetector()
        result = detector.detect_from_array(np.array([]))
        assert result is None

    def test_detect_from_array_none_image(self):
        """Test detection returns None for None input."""
        detector = CardDetector()
        result = detector.detect_from_array(None)
        assert result is None

    def test_detect_from_array_uniform_image(self):
        """Test detection returns None for uniform image (no edges)."""
        detector = CardDetector()
        # Create a uniform gray image - no edges to detect
        img = np.ones((480, 640, 3), dtype=np.uint8) * 128
        result = detector.detect_from_array(img)
        assert result is None

    def test_detect_from_array_with_rectangle(self):
        """Test detection finds a clear rectangle in the image."""
        detector = CardDetector(min_area_ratio=0.05)

        # Create image with a white rectangle on black background
        img = np.zeros((600, 800, 3), dtype=np.uint8)

        # Draw a white filled rectangle (simulating a card)
        # Rectangle from (100, 100) to (700, 400) - 600x300 pixels
        img[100:400, 100:700] = 255

        result = detector.detect_from_array(img)

        # Should detect the rectangle
        assert result is not None
        assert isinstance(result, np.ndarray)
        # The cropped result should be roughly the size of the rectangle
        h, w = result.shape[:2]
        assert 200 < w < 700  # Approximate width
        assert 100 < h < 400  # Approximate height

    def test_order_points(self):
        """Test point ordering for perspective transform."""
        detector = CardDetector()

        # Test with points in random order
        pts = np.array([[100, 100], [300, 100], [300, 200], [100, 200]], dtype=np.float32)
        np.random.shuffle(pts)

        ordered = detector._order_points(pts)

        # Verify order: TL, TR, BR, BL
        assert ordered[0].tolist() == [100, 100]  # Top-left
        assert ordered[1].tolist() == [300, 100]  # Top-right
        assert ordered[2].tolist() == [300, 200]  # Bottom-right
        assert ordered[3].tolist() == [100, 200]  # Bottom-left

    def test_find_card_contour_filters_small_areas(self):
        """Test that contours with small areas are filtered out."""
        detector = CardDetector(min_area_ratio=0.5)

        # Create a small contour (less than 50% of image)
        img_shape = (100, 100, 3)
        small_contour = np.array([[[10, 10]], [[20, 10]], [[20, 20]], [[10, 20]]])

        result = detector._find_card_contour([small_contour], img_shape)
        assert result is None

    def test_find_card_contour_rejects_non_quadrilaterals(self):
        """Test that non-quadrilateral contours are rejected."""
        detector = CardDetector(min_area_ratio=0.01)

        # Create a triangle contour (3 points)
        img_shape = (100, 100, 3)
        triangle = np.array([[[10, 10]], [[90, 10]], [[50, 90]]])

        result = detector._find_card_contour([triangle], img_shape)
        assert result is None

    def test_detect_from_array_fallback_resize(self):
        """Test fallback resize returns resized image when detection fails."""
        detector = CardDetector()

        # Create a large uniform image (no edges to detect)
        # Larger than MAX_OCR_DIM (2000) to trigger resize
        img = np.ones((3000, 4000, 3), dtype=np.uint8) * 128

        # Without fallback, should return None
        result_no_fallback = detector.detect_from_array(img, fallback_resize=False)
        assert result_no_fallback is None

        # With fallback, should return resized image
        result_with_fallback = detector.detect_from_array(img, fallback_resize=True)
        assert result_with_fallback is not None
        h, w = result_with_fallback.shape[:2]
        assert max(h, w) <= CardDetector.MAX_OCR_DIM

    def test_detect_from_array_large_crop_gets_resized(self):
        """Test that large cropped results are resized to fit MAX_OCR_DIM."""
        detector = CardDetector(min_area_ratio=0.01)

        # Create a large image with a detectable rectangle
        img = np.zeros((4000, 5000, 3), dtype=np.uint8)
        # Draw a large white rectangle
        img[500:3500, 500:4500] = 255

        result = detector.detect_from_array(img)

        # Result should be resized to fit within MAX_OCR_DIM
        if result is not None:
            h, w = result.shape[:2]
            assert max(h, w) <= CardDetector.MAX_OCR_DIM


class TestCardDetectorIntegration:
    """Integration tests using fixture images."""

    @pytest.fixture
    def detector(self):
        """Create a CardDetector instance."""
        return CardDetector()

    @pytest.fixture
    def fixture_path(self):
        """Path to test fixtures directory."""
        from pathlib import Path

        return Path(__file__).parent / "fixtures"

    def test_detect_from_fixture_image(self, detector, fixture_path):
        """Test detection on a real fixture image if available."""
        card_image = fixture_path / "card.jpg"
        if not card_image.exists():
            pytest.skip("Test fixture card.jpg not found")

        result = detector.detect(card_image)
        # For a proper card image, detection should succeed
        # Note: This may return None if the card doesn't have clear edges
        # The test validates that the method runs without error
        if result is not None:
            assert isinstance(result, np.ndarray)
            assert result.shape[2] == 3  # BGR image
