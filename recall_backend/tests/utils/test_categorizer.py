"""
Tests for BasicCategorizer service.
"""
import pytest
from app.services.categorizer import BasicCategorizer


class TestDetectSourceApp:
    """Test source app detection from URLs."""

    def setup_method(self):
        """Initialize categorizer for each test."""
        self.categorizer = BasicCategorizer()

    def test_youtube_url(self):
        """Test YouTube URL detection."""
        assert self.categorizer.detect_source_app(
            "https://www.youtube.com/watch?v=abc"
        ) == "youtube"

    def test_github_url(self):
        """Test GitHub URL detection."""
        assert self.categorizer.detect_source_app(
            "https://github.com/user/repo"
        ) == "github"

    def test_hackernews_url(self):
        """Test Hacker News URL detection."""
        assert self.categorizer.detect_source_app(
            "https://news.ycombinator.com/item?id=123"
        ) == "hackerNews"

    def test_reddit_url(self):
        """Test Reddit URL detection."""
        assert self.categorizer.detect_source_app(
            "https://www.reddit.com/r/python"
        ) == "reddit"

    def test_twitter_url(self):
        """Test Twitter URL detection."""
        assert self.categorizer.detect_source_app(
            "https://twitter.com/user/status/123"
        ) == "twitter"

    def test_substack_url(self):
        """Test Substack URL detection (substack.com pattern)."""
        assert self.categorizer.detect_source_app(
            "https://somesubstack.substack.com/p/post"
        ) == "substack"

    def test_unknown_domain_extraction(self):
        """Test unknown domain extraction returns domain name, not 'other'."""
        assert self.categorizer.detect_source_app(
            "https://unknowndomain.io/article"
        ) == "unknowndomain"


class TestDetectCategory:
    """Test category detection from URL and text."""

    def setup_method(self):
        """Initialize categorizer for each test."""
        self.categorizer = BasicCategorizer()

    def test_technology_category_from_title(self):
        """Test technology category detection from title."""
        result = self.categorizer.detect_category(
            url="https://example.com",
            title="python programming tutorial",
            description=""
        )
        assert result == "technology"

    def test_productivity_category_from_title(self):
        """Test productivity category detection from title."""
        result = self.categorizer.detect_category(
            url="https://example.com",
            title="productivity tips",
            description=""
        )
        assert result == "productivity"

    def test_no_keyword_matches_returns_other(self):
        """Test that content with no keyword matches returns 'other'."""
        result = self.categorizer.detect_category(
            url="https://example.com",
            title="nothing here",
            description="no matches in this text"
        )
        assert result == "other"


class TestExtractBasicTags:
    """Test tag extraction with priority logic."""

    def setup_method(self):
        """Initialize categorizer for each test."""
        self.categorizer = BasicCategorizer()

    def test_og_tags_highest_priority(self):
        """Test that og_tags are used with highest priority."""
        tags = self.categorizer.extract_basic_tags(
            title="Some Title",
            description="Some Description",
            og_tags={"article_tags": ["python", "web-development", "fastapi"]}
        )
        # og_tags should be first
        assert tags[0] == "python"
        assert tags[1] == "web-development"
        assert tags[2] == "fastapi"

    def test_og_tags_fill_first_three_slots(self):
        """Test that og_tags fill first 3 slots, then meta_keywords fill remaining."""
        tags = self.categorizer.extract_basic_tags(
            title="FastAPI Tutorial",
            description="Learn FastAPI",
            og_tags={"article_tags": ["python", "web-development", "api"]},
            meta_keywords=["framework", "async"]
        )
        # First 3 should be from og_tags
        assert tags[0] == "python"
        assert tags[1] == "web-development"
        assert tags[2] == "api"
        # Next should be from meta_keywords
        assert tags[3] == "framework"
        assert tags[4] == "async"

    def test_meta_keywords_without_og_tags(self):
        """Test that meta_keywords are used when og_tags not present."""
        tags = self.categorizer.extract_basic_tags(
            title="Some Title",
            description="Some Description",
            meta_keywords=["keyword1", "keyword2", "keyword3"]
        )
        assert tags[0] == "keyword1"
        assert tags[1] == "keyword2"
        assert tags[2] == "keyword3"

    def test_capitalized_words_from_title_fallback(self):
        """Test that capitalized words from title are extracted as fallback."""
        tags = self.categorizer.extract_basic_tags(
            title="FastAPI Tutorial for Python Developers",
            description=""
        )
        # Should extract capitalized words
        assert "fastapi" in tags
        assert "tutorial" in tags or "python" in tags or "developers" in tags

    def test_max_five_tags_returned(self):
        """Test that maximum 5 tags are returned regardless of input size."""
        tags = self.categorizer.extract_basic_tags(
            title="One Two Three Four Five Six Seven Eight",
            description="Nine Ten Eleven Twelve Thirteen"
        )
        assert len(tags) <= 5

    def test_priority_order_og_then_meta(self):
        """Test complete priority: og_tags first, then meta_keywords, then title."""
        tags = self.categorizer.extract_basic_tags(
            title="Learning FastAPI Framework Development",
            description="Advanced topics in web development",
            meta_keywords=["async", "python"],
            og_tags={"article_tags": ["webdev", "programming"]}
        )
        # Should have og_tags first
        assert tags[0] == "webdev"
        assert tags[1] == "programming"
        # Then meta_keywords
        assert tags[2] == "async"
        assert tags[3] == "python"
        # Max 5 total
        assert len(tags) <= 5


class TestEstimateReadingTime:
    """Test reading time estimation."""

    def setup_method(self):
        """Initialize categorizer for each test."""
        self.categorizer = BasicCategorizer()

    def test_200_words_equals_one_minute(self):
        """Test that 200 words equals 1 minute."""
        text = " ".join(["word"] * 200)
        assert self.categorizer.estimate_reading_time(text) == 1

    def test_400_words_equals_two_minutes(self):
        """Test that 400 words equals 2 minutes."""
        text = " ".join(["word"] * 400)
        assert self.categorizer.estimate_reading_time(text) == 2

    def test_empty_string_minimum_one_minute(self):
        """Test that empty string returns minimum 1 minute."""
        assert self.categorizer.estimate_reading_time("") == 1

    def test_zero_words_minimum_one_minute(self):
        """Test that single word (below minimum) returns 1 minute."""
        assert self.categorizer.estimate_reading_time("word") == 1

    def test_rounding_up_behavior(self):
        """Test that reading time rounds up correctly."""
        # 201 words should round up to 2 minutes (not 1)
        text = " ".join(["word"] * 201)
        assert self.categorizer.estimate_reading_time(text) == 2

        # 199 words should round down to 1 minute
        text = " ".join(["word"] * 199)
        assert self.categorizer.estimate_reading_time(text) == 1
