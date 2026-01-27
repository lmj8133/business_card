"""Batch processing for multiple business card images."""

import csv
import io
import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from business_card.parser import BusinessCardParser


@dataclass
class BatchResult:
    """Result of batch processing multiple images."""

    results: list[dict] = field(default_factory=list)
    errors: list[dict] = field(default_factory=list)
    total_time_ms: float = 0.0

    @property
    def total(self) -> int:
        """Total number of processed images."""
        return len(self.results) + len(self.errors)

    @property
    def succeeded(self) -> int:
        """Number of successfully processed images."""
        return len(self.results)

    @property
    def failed(self) -> int:
        """Number of failed images."""
        return len(self.errors)


class BatchProcessor:
    """Process multiple business card images with error isolation."""

    # Supported image extensions
    IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

    def __init__(self, parser: BusinessCardParser):
        """
        Initialize batch processor.

        Args:
            parser: BusinessCardParser instance for processing individual cards.
        """
        self._parser = parser

    def process(self, image_paths: list[Path]) -> BatchResult:
        """
        Process multiple images, isolating errors per image.

        Args:
            image_paths: List of image paths to process.

        Returns:
            BatchResult with successful results and errors.
        """
        start_time = time.perf_counter()
        results: list[dict] = []
        errors: list[dict] = []

        for path in image_paths:
            try:
                card = self._parser.parse(path)
                result = card.model_dump(exclude={"metadata", "raw_text"})
                result["image_path"] = str(path)
                results.append(result)
            except Exception as e:
                errors.append({
                    "image_path": str(path),
                    "error": str(e),
                })

        elapsed_ms = (time.perf_counter() - start_time) * 1000

        return BatchResult(
            results=results,
            errors=errors,
            total_time_ms=round(elapsed_ms, 2),
        )

    def collect_images(self, inputs: list[Path]) -> list[Path]:
        """
        Collect image paths from files and directories.

        Args:
            inputs: List of file paths or directories.

        Returns:
            List of image file paths.
        """
        images: list[Path] = []

        for path in inputs:
            if path.is_dir():
                for ext in self.IMAGE_EXTENSIONS:
                    images.extend(path.glob(f"*{ext}"))
                    images.extend(path.glob(f"*{ext.upper()}"))
            elif path.is_file() and path.suffix.lower() in self.IMAGE_EXTENSIONS:
                images.append(path)

        # Sort for deterministic order
        return sorted(set(images))

    def to_json(self, result: BatchResult) -> str:
        """
        Format batch result as JSON.

        Args:
            result: BatchResult to format.

        Returns:
            JSON string with metadata, results, and errors.
        """
        output = {
            "metadata": {
                "total": result.total,
                "succeeded": result.succeeded,
                "failed": result.failed,
                "total_time_ms": result.total_time_ms,
            },
            "results": result.results,
            "errors": result.errors,
        }
        return json.dumps(output, indent=2, ensure_ascii=False)

    def to_csv(self, result: BatchResult) -> str:
        """
        Format batch result as CSV.

        Args:
            result: BatchResult to format.

        Returns:
            CSV string with all results and errors.
        """
        output = io.StringIO()
        fieldnames = [
            "image_path",
            "company",
            "name",
            "department",
            "title",
            "email",
            "confidence",
            "error",
        ]
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()

        # Write successful results
        for item in result.results:
            row = {k: item.get(k, "") for k in fieldnames}
            row["error"] = ""
            writer.writerow(row)

        # Write errors
        for item in result.errors:
            row = {k: "" for k in fieldnames}
            row["image_path"] = item["image_path"]
            row["error"] = item["error"]
            writer.writerow(row)

        return output.getvalue()
