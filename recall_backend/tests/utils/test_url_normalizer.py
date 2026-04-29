"""Tests for URL normalization utility."""
import pytest
from app.utils.url_normalizer import normalize_url


class TestTrackingParameterStripping:
    """Test removal of tracking/analytics parameters."""

    def test_utm_source_stripped_with_other_params(self):
        """utm_source stripped but other query params preserved."""
        url = "https://example.com/page?utm_source=google&q=test"
        result = normalize_url(url)
        assert result == "https://example.com/page?q=test"

    def test_utm_medium_stripped(self):
        """utm_medium stripped entirely."""
        url = "https://example.com/page?utm_medium=cpc"
        result = normalize_url(url)
        assert "utm_medium" not in result
        assert result == "https://example.com/page"

    def test_utm_campaign_stripped(self):
        """utm_campaign stripped entirely."""
        url = "https://example.com/page?utm_campaign=spring"
        result = normalize_url(url)
        assert "utm_campaign" not in result
        assert result == "https://example.com/page"

    def test_fbclid_stripped(self):
        """fbclid stripped entirely."""
        url = "https://example.com/page?fbclid=abc123"
        result = normalize_url(url)
        assert "fbclid" not in result
        assert result == "https://example.com/page"

    def test_gclid_stripped(self):
        """gclid stripped entirely."""
        url = "https://example.com/page?gclid=xyz"
        result = normalize_url(url)
        assert "gclid" not in result
        assert result == "https://example.com/page"


class TestWwwRemoval:
    """Test removal of www. prefix from hostname."""

    def test_www_prefix_removed(self):
        """www. prefix removed from hostname."""
        url = "https://www.example.com/page"
        result = normalize_url(url)
        assert result == "https://example.com/page"

    def test_no_www_unchanged(self):
        """URL without www. prefix unchanged."""
        url = "https://example.com/page"
        result = normalize_url(url)
        assert result == "https://example.com/page"


class TestTrailingSlashRemoval:
    """Test handling of trailing slashes."""

    def test_trailing_slash_removed_from_path(self):
        """Trailing slash removed from non-root path."""
        url = "https://example.com/page/"
        result = normalize_url(url)
        assert result == "https://example.com/page"

    def test_root_slash_preserved(self):
        """Root slash (/) preserved."""
        url = "https://example.com/"
        result = normalize_url(url)
        assert result == "https://example.com/"

    def test_multiple_trailing_slashes_removed(self):
        """Multiple trailing slashes removed."""
        url = "https://example.com/page///"
        result = normalize_url(url)
        assert result == "https://example.com/page"


class TestSPAFragmentHandling:
    """Test preservation of SPA-style fragments."""

    def test_fragment_starting_with_slash_preserved(self):
        """Fragment starting with / preserved (SPA route)."""
        url = "https://example.com/page#/app/home"
        result = normalize_url(url)
        assert result == "https://example.com/page#/app/home"

    def test_fragment_starting_with_exclamation_preserved(self):
        """Fragment starting with ! preserved (hashbang routes)."""
        url = "https://example.com/page#!/state"
        result = normalize_url(url)
        assert result == "https://example.com/page#!/state"

    def test_fragment_not_starting_with_slash_or_exclamation_stripped(self):
        """Fragment not starting with / or ! stripped."""
        url = "https://example.com/page#section"
        result = normalize_url(url)
        assert "#section" not in result
        assert result == "https://example.com/page"


class TestQueryParameterSorting:
    """Test alphabetical sorting of query parameters."""

    def test_query_params_sorted_alphabetically(self):
        """Query parameters sorted alphabetically."""
        url = "https://example.com/?b=2&a=1"
        result = normalize_url(url)
        assert result == "https://example.com/?a=1&b=2"

    def test_complex_param_sorting(self):
        """Complex query with multiple params sorted."""
        url = "https://example.com/?z=3&a=1&m=2"
        result = normalize_url(url)
        assert result == "https://example.com/?a=1&m=2&z=3"


class TestPortHandling:
    """Test omission of standard ports."""

    def test_http_port_80_omitted(self):
        """Port 80 omitted for HTTP."""
        url = "http://example.com:80/page"
        result = normalize_url(url)
        assert result == "http://example.com/page"

    def test_https_port_443_omitted(self):
        """Port 443 omitted for HTTPS."""
        url = "https://example.com:443/page"
        result = normalize_url(url)
        assert result == "https://example.com/page"

    def test_non_standard_http_port_preserved(self):
        """Non-standard port preserved for HTTP."""
        url = "http://example.com:8080/page"
        result = normalize_url(url)
        assert result == "http://example.com:8080/page"

    def test_non_standard_https_port_preserved(self):
        """Non-standard port preserved for HTTPS."""
        url = "https://example.com:8443/page"
        result = normalize_url(url)
        assert result == "https://example.com:8443/page"


class TestCombinedTransformations:
    """Test multiple transformations applied together."""

    def test_www_removal_and_tracking_stripping(self):
        """www. prefix and tracking params both removed."""
        url = "https://www.example.com/page?utm_source=google&q=test"
        result = normalize_url(url)
        assert result == "https://example.com/page?q=test"

    def test_all_transformations_combined(self):
        """All transformations applied: www, tracking, slash, fragment."""
        url = "https://www.example.com/page/?utm_source=google&b=2&a=1#section"
        result = normalize_url(url)
        assert result == "https://example.com/page?a=1&b=2"

    def test_www_port_tracking_combined(self):
        """www, port, and tracking parameters combined."""
        url = "https://www.example.com:443/page?utm_campaign=test&q=search"
        result = normalize_url(url)
        assert result == "https://example.com/page?q=search"


class TestCaseInsensitivity:
    """Test case handling in scheme and hostname."""

    def test_uppercase_scheme_lowercased(self):
        """Uppercase scheme converted to lowercase."""
        url = "HTTPS://example.com/page"
        result = normalize_url(url)
        assert result == "https://example.com/page"

    def test_uppercase_hostname_lowercased(self):
        """Uppercase hostname converted to lowercase."""
        url = "https://Example.COM/page"
        result = normalize_url(url)
        assert result == "https://example.com/page"


class TestEdgeCases:
    """Test edge cases and special scenarios."""

    def test_empty_query_after_tracking_removal(self):
        """Query becomes empty after tracking param removal."""
        url = "https://example.com/page?utm_source=google&utm_medium=cpc"
        result = normalize_url(url)
        assert result == "https://example.com/page"

    def test_root_url_with_tracking(self):
        """Root URL with tracking params."""
        url = "https://example.com/?utm_source=google"
        result = normalize_url(url)
        assert result == "https://example.com/"

    def test_complex_path_preserved(self):
        """Complex paths preserved during normalization."""
        url = "https://example.com/some/deep/path/to/resource?q=test"
        result = normalize_url(url)
        assert result == "https://example.com/some/deep/path/to/resource?q=test"

    def test_multiple_query_param_values_preserved(self):
        """Query params with multiple values preserved."""
        url = "https://example.com/?tag=a&tag=b"
        result = normalize_url(url)
        assert result == "https://example.com/?tag=a&tag=b"

    def test_blank_query_param_preserved(self):
        """Blank query params preserved."""
        url = "https://example.com/?q=test&empty="
        result = normalize_url(url)
        assert result == "https://example.com/?empty=&q=test"
