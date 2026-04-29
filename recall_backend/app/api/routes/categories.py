"""
Category management API endpoints.

Handles CRUD operations for user-created categories.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from pydantic import BaseModel
from uuid import UUID

from app.db.session import get_db
from app.models.user import User
from app.models.user_category import UserCategory
from app.api.routes.auth import get_current_user
from app.services.category_service import CategoryService
from app.core.exceptions import NotFoundError, ConflictError


router = APIRouter(prefix="/categories", tags=["Categories"])


class CategoryCreateRequest(BaseModel):
    """Request to create a category."""
    name: str
    description: Optional[str] = None
    color: Optional[str] = None


class CategoryUpdateRequest(BaseModel):
    """Request to update a category."""
    name: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None


class CategoryResponse(BaseModel):
    """Category response model."""
    id: UUID
    user_id: UUID
    name: str
    description: Optional[str] = None
    color: str
    usage_count: int
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


@router.post("", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_category(
    request: CategoryCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Create a new category.

    Example:
        POST /api/categories
        {
            "name": "Machine Learning",
            "description": "Articles about ML and AI",
            "color": "#FF5733"
        }

    Returns:
        Created CategoryResponse
    """
    try:
        category = await CategoryService.create_category(
            db=db,
            user_id=str(current_user.id),
            name=request.name,
            description=request.description,
            color=request.color
        )
        return CategoryResponse.model_validate(category)
    except ConflictError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(e)
        )


@router.get("", response_model=List[CategoryResponse])
async def get_categories(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get all categories for current user.

    Returns:
        List of CategoryResponse objects
    """
    categories = await CategoryService.get_user_categories(
        db=db,
        user_id=str(current_user.id)
    )
    return [CategoryResponse.model_validate(cat) for cat in categories]


@router.get("/{category_id}", response_model=CategoryResponse)
async def get_category(
    category_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get a specific category by ID.

    Returns:
        CategoryResponse

    Errors:
        404: Category not found
    """
    try:
        category = await CategoryService.get_category(
            db=db,
            category_id=category_id,
            user_id=str(current_user.id)
        )
        return CategoryResponse.model_validate(category)
    except NotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )


@router.patch("/{category_id}", response_model=CategoryResponse)
async def update_category(
    category_id: str,
    request: CategoryUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update a category.

    Example:
        PATCH /api/categories/{category_id}
        {
            "name": "Updated Name",
            "color": "#00FF00"
        }

    Returns:
        Updated CategoryResponse

    Errors:
        404: Category not found
        409: Category name conflict
    """
    try:
        category = await CategoryService.update_category(
            db=db,
            category_id=category_id,
            user_id=str(current_user.id),
            name=request.name,
            description=request.description,
            color=request.color
        )
        return CategoryResponse.model_validate(category)
    except NotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    except ConflictError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(e)
        )


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete a category.

    This will remove the category from all content items that use it.

    Errors:
        404: Category not found
    """
    try:
        await CategoryService.delete_category(
            db=db,
            category_id=category_id,
            user_id=str(current_user.id)
        )
    except NotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )

