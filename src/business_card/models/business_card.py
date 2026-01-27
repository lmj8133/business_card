"""Pydantic models for business card data."""

from pydantic import BaseModel, Field


class Metadata(BaseModel):
    """Processing metadata."""

    ocr_backend: str = Field(description="OCR backend used")
    extractor_backend: str = Field(description="LLM extractor used")
    processing_time_ms: float = Field(description="Total processing time in ms")


class BusinessCard(BaseModel):
    """Simplified business card information."""

    company: str | None = Field(default=None, description="Company name")
    name: str = Field(description="Person's full name")
    position: str | None = Field(
        default=None, description="Job position (department and/or title)"
    )
    email: str | None = Field(default=None, description="Email address")

    raw_text: str = Field(description="Raw OCR text for reference")
    confidence: float = Field(
        default=0.0, ge=0.0, le=1.0, description="Extraction confidence score"
    )
    metadata: Metadata | None = Field(default=None, description="Processing metadata")
