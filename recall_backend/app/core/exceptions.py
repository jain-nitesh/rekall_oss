"""
Custom exception classes for the application.

Provides structured error handling with proper HTTP status codes.
"""
from fastapi import HTTPException, status


class AppException(HTTPException):
    """Base exception class for application errors."""
    
    def __init__(self, detail: str, status_code: int = status.HTTP_400_BAD_REQUEST):
        super().__init__(status_code=status_code, detail=detail)


class ValidationError(AppException):
    """Raised when input validation fails."""
    
    def __init__(self, detail: str):
        super().__init__(detail=detail, status_code=status.HTTP_422_UNPROCESSABLE_ENTITY)


class NotFoundError(AppException):
    """Raised when a resource is not found."""
    
    def __init__(self, resource: str = "Resource"):
        super().__init__(detail=f"{resource} not found", status_code=status.HTTP_404_NOT_FOUND)


class UnauthorizedError(AppException):
    """Raised when authentication fails."""
    
    def __init__(self, detail: str = "Unauthorized"):
        super().__init__(detail=detail, status_code=status.HTTP_401_UNAUTHORIZED)


class ForbiddenError(AppException):
    """Raised when user doesn't have permission."""
    
    def __init__(self, detail: str = "Forbidden"):
        super().__init__(detail=detail, status_code=status.HTTP_403_FORBIDDEN)


class ConflictError(AppException):
    """Raised when a resource conflict occurs (e.g., duplicate email)."""
    
    def __init__(self, detail: str):
        super().__init__(detail=detail, status_code=status.HTTP_409_CONFLICT)

