import socket
from unittest.mock import patch

import pytest

from app.utils.url_validator import is_private_ip, is_safe_url, validate_url_or_raise


def fake_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, '', ('93.184.216.34', 0))]


# --- is_private_ip ---

class TestIsPrivateIp:
    def test_loopback(self):
        assert is_private_ip('127.0.0.1') is True

    def test_private_10(self):
        assert is_private_ip('10.0.0.1') is True

    def test_private_192(self):
        assert is_private_ip('192.168.1.1') is True

    def test_private_172(self):
        assert is_private_ip('172.16.0.1') is True

    def test_public(self):
        assert is_private_ip('93.184.216.34') is False

    def test_invalid_string(self):
        assert is_private_ip('not-an-ip') is False

    def test_ipv6_loopback(self):
        assert is_private_ip('::1') is True


# --- is_safe_url ---

class TestIsSafeUrl:
    # Pattern-matched blocks (no DNS needed)
    def test_localhost(self):
        safe, msg = is_safe_url('http://localhost')
        assert safe is False
        assert msg

    def test_127_0_0_1(self):
        safe, msg = is_safe_url('http://127.0.0.1')
        assert safe is False
        assert msg != ""

    def test_127_any(self):
        safe, msg = is_safe_url('http://127.5.5.5')
        assert safe is False
        assert msg != ""

    def test_0_0_0_0(self):
        safe, msg = is_safe_url('http://0.0.0.0')
        assert safe is False
        assert msg != ""

    def test_ipv6_loopback(self):
        safe, msg = is_safe_url('http://[::1]')
        assert safe is False
        assert msg != ""

    def test_aws_metadata(self):
        safe, msg = is_safe_url('http://169.254.169.254')
        assert safe is False
        assert msg != ""

    def test_gcp_metadata(self):
        safe, msg = is_safe_url('http://metadata.google.internal')
        assert safe is False
        assert msg != ""

    # Private IP direct (no DNS)
    def test_private_10(self):
        safe, msg = is_safe_url('http://10.0.0.1')
        assert safe is False
        assert msg != ""

    def test_private_192(self):
        safe, msg = is_safe_url('http://192.168.1.1')
        assert safe is False
        assert msg != ""

    def test_private_172(self):
        safe, msg = is_safe_url('http://172.16.0.1')
        assert safe is False
        assert msg != ""

    # No hostname
    def test_no_hostname(self):
        safe, msg = is_safe_url('http://')
        assert safe is False
        assert msg != ""

    # Invalid scheme
    def test_ftp_scheme(self):
        safe, msg = is_safe_url('ftp://example.com')
        assert safe is False
        assert msg != ""

    def test_file_scheme(self):
        safe, msg = is_safe_url('file:///etc/passwd')
        assert safe is False
        assert msg != ""

    # Safe URL (DNS mocked)
    def test_safe_https(self):
        with patch('app.utils.url_validator.socket.getaddrinfo', side_effect=fake_getaddrinfo):
            safe, msg = is_safe_url('https://example.com')
        assert safe is True
        assert msg == ""


# --- validate_url_or_raise ---

class TestValidateUrlOrRaise:
    def test_raises_on_unsafe(self):
        with pytest.raises(ValueError):
            validate_url_or_raise('http://localhost')

    def test_no_raise_on_safe(self):
        with patch('app.utils.url_validator.socket.getaddrinfo', side_effect=fake_getaddrinfo):
            validate_url_or_raise('https://example.com')  # should not raise
