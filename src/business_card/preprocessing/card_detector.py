"""Business card region detection and cropping."""

import logging
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger(__name__)


class CardDetector:
    """Detect and crop business card region from image.

    Uses edge detection and contour analysis to find the largest
    quadrilateral region, then applies perspective transform to
    produce a flat, cropped image of the card.

    When detection fails, can optionally return a resized version
    of the original image as fallback.
    """

    # Maximum dimension for processing (larger images are resized)
    MAX_PROCESS_DIM = 1500
    # Maximum dimension for OCR output (prevents memory issues)
    MAX_OCR_DIM = 2000

    def __init__(
        self,
        min_area_ratio: float = 0.05,
        max_area_ratio: float = 0.85,
        canny_low: int = 50,
        canny_high: int = 150,
        epsilon_factor: float = 0.02,
    ):
        """
        Initialize CardDetector.

        Args:
            min_area_ratio: Minimum card area as ratio of image area.
            max_area_ratio: Maximum card area as ratio of image area.
            canny_low: Lower threshold for Canny edge detection.
            canny_high: Upper threshold for Canny edge detection.
            epsilon_factor: Factor for contour approximation (relative to perimeter).
        """
        self._min_area_ratio = min_area_ratio
        self._max_area_ratio = max_area_ratio
        self._canny_low = canny_low
        self._canny_high = canny_high
        self._epsilon_factor = epsilon_factor

    def detect(
        self, image_path: Path, fallback_resize: bool = False
    ) -> np.ndarray | None:
        """
        Detect and crop business card from image.

        Args:
            image_path: Path to the input image.
            fallback_resize: If True, return resized original when detection fails.

        Returns:
            Cropped card image as numpy array (BGR), or None if not detected
            (unless fallback_resize is True).
        """
        img = cv2.imread(str(image_path))
        if img is None:
            logger.warning("Failed to read image: %s", image_path)
            return None

        return self.detect_from_array(img, fallback_resize=fallback_resize)

    def detect_from_array(
        self, img: np.ndarray, fallback_resize: bool = False
    ) -> np.ndarray | None:
        """
        Detect and crop business card from numpy array.

        Args:
            img: Input image as BGR numpy array.
            fallback_resize: If True, return resized original when detection fails.

        Returns:
            Cropped card image as numpy array (BGR), or None if not detected
            (unless fallback_resize is True).
        """
        if img is None or img.size == 0:
            return None

        # Resize large images for faster processing
        orig_h, orig_w = img.shape[:2]
        scale = 1.0
        if max(orig_h, orig_w) > self.MAX_PROCESS_DIM:
            scale = self.MAX_PROCESS_DIM / max(orig_h, orig_w)
            new_w, new_h = int(orig_w * scale), int(orig_h * scale)
            resized = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
        else:
            resized = img

        # Try multiple preprocessing strategies
        strategies = [
            self._preprocess_white_region,
            self._preprocess_adaptive,
            self._preprocess_canny,
            self._preprocess_morph,
        ]

        for strategy in strategies:
            edges = strategy(resized)
            contours, _ = cv2.findContours(
                edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
            )

            if contours:
                card_contour = self._find_card_contour(contours, resized.shape)
                if card_contour is not None:
                    # Scale contour back to original image size
                    if scale != 1.0:
                        card_contour = (card_contour.astype(np.float32) / scale).astype(
                            np.int32
                        )
                    logger.debug("Card detected using strategy: %s", strategy.__name__)
                    cropped = self._perspective_transform(img, card_contour)

                    # If cropped result is still too large, resize it
                    crop_h, crop_w = cropped.shape[:2]
                    if max(crop_h, crop_w) > self.MAX_OCR_DIM:
                        resize_scale = self.MAX_OCR_DIM / max(crop_h, crop_w)
                        new_w = int(crop_w * resize_scale)
                        new_h = int(crop_h * resize_scale)
                        logger.debug(
                            "Cropped image too large, resizing to %dx%d", new_w, new_h
                        )
                        cropped = cv2.resize(
                            cropped, (new_w, new_h), interpolation=cv2.INTER_AREA
                        )
                    return cropped

        logger.debug("No quadrilateral card contour found with any strategy")

        # Fallback: resize original image if requested
        if fallback_resize and max(orig_h, orig_w) > self.MAX_OCR_DIM:
            fallback_scale = self.MAX_OCR_DIM / max(orig_h, orig_w)
            new_w, new_h = int(orig_w * fallback_scale), int(orig_h * fallback_scale)
            logger.debug("Fallback: resizing image to %dx%d", new_w, new_h)
            return cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)

        return None

    def _preprocess_canny(self, img: np.ndarray) -> np.ndarray:
        """Standard Canny edge detection."""
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, self._canny_low, self._canny_high)
        kernel = np.ones((3, 3), np.uint8)
        return cv2.dilate(edges, kernel, iterations=2)

    def _preprocess_adaptive(self, img: np.ndarray) -> np.ndarray:
        """Adaptive thresholding - better for low contrast images."""
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)

        # Adaptive threshold to handle varying lighting
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )

        # Find edges from threshold
        edges = cv2.Canny(thresh, 50, 150)
        kernel = np.ones((5, 5), np.uint8)
        edges = cv2.dilate(edges, kernel, iterations=2)
        return cv2.erode(edges, kernel, iterations=1)

    def _preprocess_morph(self, img: np.ndarray) -> np.ndarray:
        """Morphological gradient - good for finding object boundaries."""
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (7, 7), 0)

        # Use morphological gradient to find edges
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        gradient = cv2.morphologyEx(blurred, cv2.MORPH_GRADIENT, kernel)

        # Threshold the gradient
        _, thresh = cv2.threshold(gradient, 30, 255, cv2.THRESH_BINARY)

        # Close gaps and clean up
        kernel = np.ones((5, 5), np.uint8)
        closed = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel, iterations=2)
        return cv2.dilate(closed, kernel, iterations=1)

    def _preprocess_white_region(self, img: np.ndarray) -> np.ndarray:
        """Detect white/light regions - good for white cards on darker backgrounds."""
        # Convert to LAB color space for better brightness detection
        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0]

        # Threshold to find bright regions (cards are usually white/light)
        _, bright_mask = cv2.threshold(l_channel, 180, 255, cv2.THRESH_BINARY)

        # Clean up the mask
        kernel = np.ones((7, 7), np.uint8)
        bright_mask = cv2.morphologyEx(bright_mask, cv2.MORPH_CLOSE, kernel, iterations=3)
        bright_mask = cv2.morphologyEx(bright_mask, cv2.MORPH_OPEN, kernel, iterations=2)

        # Find edges of the bright region
        edges = cv2.Canny(bright_mask, 50, 150)
        return cv2.dilate(edges, kernel, iterations=2)

    def _find_card_contour(
        self, contours: list, img_shape: tuple
    ) -> np.ndarray | None:
        """
        Find the contour most likely to be a business card.

        Args:
            contours: List of contours from cv2.findContours.
            img_shape: Shape of the original image (height, width, channels).

        Returns:
            The 4-point contour of the card, or None if not found.
        """
        img_area = img_shape[0] * img_shape[1]
        min_area = img_area * self._min_area_ratio
        max_area = img_area * self._max_area_ratio

        candidates = []

        for contour in contours:
            area = cv2.contourArea(contour)

            # Filter by area
            if area < min_area or area > max_area:
                continue

            # Approximate contour to polygon
            perimeter = cv2.arcLength(contour, True)
            epsilon = self._epsilon_factor * perimeter
            approx = cv2.approxPolyDP(contour, epsilon, True)

            # We want a quadrilateral (4 vertices)
            if len(approx) == 4:
                # Check if it's convex (business cards should be convex)
                if cv2.isContourConvex(approx):
                    candidates.append((area, approx))

        if not candidates:
            return None

        # Return the largest valid quadrilateral
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]

    def _perspective_transform(
        self, img: np.ndarray, contour: np.ndarray
    ) -> np.ndarray:
        """
        Apply perspective transform to get a flat card image.

        Args:
            img: Original image.
            contour: 4-point contour of the card.

        Returns:
            Perspective-corrected card image.
        """
        # Order points: top-left, top-right, bottom-right, bottom-left
        pts = contour.reshape(4, 2).astype(np.float32)
        ordered = self._order_points(pts)

        # Calculate output dimensions based on the card's actual size
        width = int(
            max(
                np.linalg.norm(ordered[0] - ordered[1]),
                np.linalg.norm(ordered[2] - ordered[3]),
            )
        )
        height = int(
            max(
                np.linalg.norm(ordered[0] - ordered[3]),
                np.linalg.norm(ordered[1] - ordered[2]),
            )
        )

        # Ensure minimum dimensions
        width = max(width, 100)
        height = max(height, 60)

        # Destination points for the transform
        dst = np.array(
            [
                [0, 0],
                [width - 1, 0],
                [width - 1, height - 1],
                [0, height - 1],
            ],
            dtype=np.float32,
        )

        # Compute and apply perspective transform
        matrix = cv2.getPerspectiveTransform(ordered, dst)
        warped = cv2.warpPerspective(img, matrix, (width, height))

        return warped

    def _order_points(self, pts: np.ndarray) -> np.ndarray:
        """
        Order points in consistent order: TL, TR, BR, BL.

        Args:
            pts: 4 points as (4, 2) array.

        Returns:
            Ordered points as (4, 2) float32 array.
        """
        rect = np.zeros((4, 2), dtype=np.float32)

        # Sum of coordinates: smallest = top-left, largest = bottom-right
        s = pts.sum(axis=1)
        rect[0] = pts[np.argmin(s)]  # top-left
        rect[2] = pts[np.argmax(s)]  # bottom-right

        # Difference of coordinates: smallest = top-right, largest = bottom-left
        d = np.diff(pts, axis=1)
        rect[1] = pts[np.argmin(d)]  # top-right
        rect[3] = pts[np.argmax(d)]  # bottom-left

        return rect
