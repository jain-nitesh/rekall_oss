"""
Tests for app/utils/content_cleaner.py functions.
"""
import pytest
from app.utils.content_cleaner import (
    clean_title,
    clean_category,
    clean_source_app,
    clean_tags,
    clean_thumbnail_url,
)


class TestCleanTitle:
    """Tests for clean_title function."""

    def test_none_returns_untitled(self):
        """None should return 'Untitled'."""
        assert clean_title(None) == "Untitled"

    def test_empty_string_returns_untitled(self):
        """Empty string should return 'Untitled'."""
        assert clean_title("") == "Untitled"

    def test_whitespace_only_returns_untitled(self):
        """Whitespace-only string should return 'Untitled'."""
        assert clean_title("   ") == "Untitled"

    def test_truncates_to_512_chars(self):
        """513 character title should be truncated to exactly 512 chars."""
        long_title = "x" * 513
        result = clean_title(long_title)
        assert len(result) == 512
        assert result == "x" * 512

    def test_passthrough_normal_title(self):
        """Normal title should pass through unchanged."""
        assert clean_title("Hello World") == "Hello World"

    def test_strips_whitespace(self):
        """Title should have leading/trailing whitespace stripped."""
        assert clean_title("  Hello World  ") == "Hello World"

    def test_exactly_512_chars(self):
        """Title with exactly 512 chars should pass through."""
        title_512 = "x" * 512
        assert clean_title(title_512) == title_512


class TestCleanCategory:
    """Tests for clean_category function."""

    def test_tech_maps_to_technology(self):
        """'tech' should map to 'technology'."""
        assert clean_category("tech") == "technology"

    def test_unknown_returns_other(self):
        """Unknown category should return 'other'."""
        assert clean_category("unknown_xyz") == "other"

    def test_technology_passthrough(self):
        """Valid 'technology' should pass through."""
        assert clean_category("technology") == "technology"

    def test_design_passthrough(self):
        """Valid 'design' should pass through."""
        assert clean_category("design") == "design"

    def test_none_returns_other(self):
        """None should return 'other'."""
        assert clean_category(None) == "other"

    def test_empty_string_returns_other(self):
        """Empty string should return 'other'."""
        assert clean_category("") == "other"

    def test_case_insensitive(self):
        """Category should be case insensitive."""
        assert clean_category("TECHNOLOGY") == "technology"
        assert clean_category("Design") == "design"

    def test_productivity_tools_maps_to_productivity(self):
        """'productivity tools' should map to 'productivity'."""
        assert clean_category("productivity tools") == "productivity"

    def test_productivity_tools_hyphen_maps_to_productivity(self):
        """'productivity-tools' should map to 'productivity'."""
        assert clean_category("productivity-tools") == "productivity"

    def test_science_technology_maps_to_science(self):
        """'science & technology' should map to 'science'."""
        assert clean_category("science & technology") == "science"

    def test_entertainment_media_maps_to_entertainment(self):
        """'entertainment & media' should map to 'entertainment'."""
        assert clean_category("entertainment & media") == "entertainment"

    def test_business_passthrough(self):
        """Valid 'business' should pass through."""
        assert clean_category("business") == "business"

    def test_productivity_passthrough(self):
        """Valid 'productivity' should pass through."""
        assert clean_category("productivity") == "productivity"

    def test_education_passthrough(self):
        """Valid 'education' should pass through."""
        assert clean_category("education") == "education"

    def test_entertainment_passthrough(self):
        """Valid 'entertainment' should pass through."""
        assert clean_category("entertainment") == "entertainment"

    def test_whitespace_stripped(self):
        """Category should have whitespace stripped."""
        assert clean_category("  design  ") == "design"


class TestCleanSourceApp:
    """Tests for clean_source_app function."""

    def test_none_with_url_extracts_domain(self):
        """None source_app with URL should extract domain from URL."""
        result = clean_source_app(None, "https://example.com/page")
        assert result == "example"

    def test_address_like_with_url_extracts_domain(self):
        """Address-like source_app with URL should extract domain from URL."""
        result = clean_source_app("123 Main St, City", "https://example.com/page")
        assert result == "example"

    def test_linkedin_normalized(self):
        """'linkedin' should be normalized to 'linkedin'."""
        assert clean_source_app("linkedin") == "linkedin"

    def test_twitter_normalized_lowercase(self):
        """'Twitter' should be normalized to lowercase 'twitter'."""
        assert clean_source_app("Twitter") == "twitter"

    def test_none_without_url_returns_other(self):
        """None source_app without URL should return 'other'."""
        assert clean_source_app(None) == "other"

    def test_empty_string_with_url_extracts_domain(self):
        """Empty string source_app with URL should extract domain."""
        result = clean_source_app("", "https://example.com/page")
        assert result == "example"

    def test_x_normalizes_to_twitter(self):
        """'x' should normalize to 'twitter'."""
        assert clean_source_app("x") == "twitter"

    def test_reddit_normalized(self):
        """'reddit' should normalize to 'reddit'."""
        assert clean_source_app("reddit") == "reddit"

    def test_medium_normalized(self):
        """'medium' should normalize to 'medium'."""
        assert clean_source_app("medium") == "medium"

    def test_youtube_normalized(self):
        """'youtube' should normalize to 'youtube'."""
        assert clean_source_app("youtube") == "youtube"

    def test_github_normalized(self):
        """'github' should normalize to 'github'."""
        assert clean_source_app("github") == "github"

    def test_product_hunt_normalized(self):
        """'product hunt' should normalize to 'productHunt'."""
        assert clean_source_app("product hunt") == "productHunt"

    def test_producthunt_normalized(self):
        """'producthunt' should normalize to 'productHunt'."""
        assert clean_source_app("producthunt") == "productHunt"

    def test_hacker_news_normalized(self):
        """'hacker news' should normalize to 'hackerNews'."""
        assert clean_source_app("hacker news") == "hackerNews"

    def test_hackernews_normalized(self):
        """'hackernews' should normalize to 'hackerNews'."""
        assert clean_source_app("hackernews") == "hackerNews"

    def test_long_text_without_url_extracts_first_word(self):
        """Long text without URL should extract first word."""
        result = clean_source_app("This is a very long source app name")
        assert result == "this"

    def test_domain_with_www_removes_www(self):
        """Domain extraction should remove 'www.' prefix."""
        result = clean_source_app(None, "https://www.example.com/page")
        assert result == "example"

    def test_domain_with_port_removes_port(self):
        """Domain extraction should remove port number."""
        result = clean_source_app(None, "https://example.com:8080/page")
        assert result == "example"

    def test_subdomain_extracts_main_domain(self):
        """Should extract main domain from subdomain."""
        result = clean_source_app(None, "https://api.example.com/page")
        # api is second-to-last part, but example is extracted as main domain
        assert result == "example"


class TestCleanTags:
    """Tests for clean_tags function."""

    def test_duplicates_removed(self):
        """Duplicate tags should be removed."""
        result = clean_tags(["python", "python", "django"])
        assert result == ["python", "django"]

    def test_special_chars_stripped(self):
        """Special characters should be stripped from tags."""
        result = clean_tags(["hello", "world!", "test@123"])
        assert result == ["hello", "world", "test123"]

    def test_tags_less_than_2_chars_dropped(self):
        """Tags with less than 2 characters should be dropped."""
        result = clean_tags(["a", "ab", "abc"])
        assert result == ["ab", "abc"]

    def test_max_tags_limit(self):
        """Only max_tags (default 10) should be returned."""
        tags = ["tag"] * 15
        result = clean_tags(tags)
        assert len(result) == 1  # All are the same, so only one unique tag

    def test_max_tags_with_different_tags(self):
        """Only max_tags should be returned even with many different tags."""
        tags = [f"tag{i}" for i in range(15)]
        result = clean_tags(tags)
        assert len(result) == 10

    def test_none_returns_empty_list(self):
        """None should return empty list."""
        assert clean_tags(None) == []

    def test_empty_list_returns_empty_list(self):
        """Empty list should return empty list."""
        assert clean_tags([]) == []

    def test_case_insensitive(self):
        """Tags should be lowercased."""
        result = clean_tags(["PYTHON", "Django"])
        assert result == ["python", "django"]

    def test_whitespace_stripped(self):
        """Whitespace should be stripped from tags."""
        result = clean_tags(["  python  ", "  django  "])
        assert result == ["python", "django"]

    def test_hyphens_preserved(self):
        """Hyphens should be preserved in tags."""
        result = clean_tags(["machine-learning"])
        assert result == ["machine-learning"]

    def test_underscores_preserved(self):
        """Underscores should be preserved in tags."""
        result = clean_tags(["python_django"])
        assert result == ["python_django"]

    def test_max_tag_length_enforced(self):
        """Tags longer than max_tag_length should be dropped."""
        long_tag = "a" * 51
        result = clean_tags([long_tag, "short"])
        assert result == ["short"]

    def test_custom_max_tags_parameter(self):
        """Custom max_tags parameter should be respected."""
        tags = [f"tag{i}" for i in range(10)]
        result = clean_tags(tags, max_tags=5)
        assert len(result) == 5

    def test_custom_max_tag_length_parameter(self):
        """Custom max_tag_length parameter should be respected."""
        tags = ["short", "a" * 30]
        result = clean_tags(tags, max_tag_length=25)
        assert result == ["short"]

    def test_empty_strings_in_list_ignored(self):
        """Empty strings in tags list should be ignored."""
        result = clean_tags(["python", "", "django"])
        assert result == ["python", "django"]

    def test_normalizes_whitespace_in_tags(self):
        """Multiple spaces should be normalized to single space."""
        result = clean_tags(["hello  world"])
        assert result == ["hello world"]


class TestCleanThumbnailUrl:
    """Tests for clean_thumbnail_url function."""

    def test_non_url_returns_none(self):
        """Non-URL string should return None."""
        assert clean_thumbnail_url("not-a-url") is None

    def test_ftp_returns_none(self):
        """FTP URL should return None."""
        assert clean_thumbnail_url("ftp://example.com/img.jpg") is None

    def test_long_url_truncated_to_512(self):
        """URL longer than 512 chars should be truncated to 512."""
        long_url = "https://example.com/" + "x" * 513
        result = clean_thumbnail_url(long_url)
        assert len(result) == 512
        assert result == ("https://example.com/" + "x" * (512 - len("https://example.com/")))

    def test_valid_https_url_passthrough(self):
        """Valid HTTPS URL should pass through unchanged."""
        url = "https://example.com/image.jpg"
        assert clean_thumbnail_url(url) == url

    def test_valid_http_url_passthrough(self):
        """Valid HTTP URL should pass through unchanged."""
        url = "http://example.com/image.jpg"
        assert clean_thumbnail_url(url) == url

    def test_none_returns_none(self):
        """None should return None."""
        assert clean_thumbnail_url(None) is None

    def test_empty_string_returns_none(self):
        """Empty string should return None."""
        assert clean_thumbnail_url("") is None

    def test_whitespace_only_returns_none(self):
        """Whitespace-only string should return None."""
        assert clean_thumbnail_url("   ") is None

    def test_whitespace_stripped_before_validation(self):
        """Whitespace should be stripped before validation."""
        url = "  https://example.com/image.jpg  "
        assert clean_thumbnail_url(url) == "https://example.com/image.jpg"

    def test_exactly_512_chars_passthrough(self):
        """URL with exactly 512 chars should pass through."""
        url = "https://example.com/" + "x" * (512 - len("https://example.com/"))
        result = clean_thumbnail_url(url)
        assert len(result) == 512
        assert result == url

    def test_https_with_complex_path(self):
        """HTTPS URL with complex path should pass through."""
        url = "https://cdn.example.com/images/photos/2024/04/image.jpg?size=large&format=webp"
        assert clean_thumbnail_url(url) == url

    def test_http_with_port(self):
        """HTTP URL with port should pass through."""
        url = "http://example.com:8080/image.jpg"
        assert clean_thumbnail_url(url) == url
