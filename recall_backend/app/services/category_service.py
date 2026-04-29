"""
Category service for managing user-created categories.

Handles creation, updating, and deletion of user categories.
Also provides logic for auto-creating categories from AI suggestions.
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List, Optional
from app.models.user_category import UserCategory
from app.models.content_item import ContentItem
from app.core.exceptions import NotFoundError, ConflictError


class CategoryService:
    """Service for managing user categories."""

    @staticmethod
    async def create_category(
        db: AsyncSession,
        user_id: str,
        name: str,
        description: Optional[str] = None,
        color: Optional[str] = None
    ) -> UserCategory:
        """
        Create a new user category.

        Args:
            db: Database session
            user_id: User ID
            name: Category name
            description: Optional description
            color: Optional color (hex code)

        Returns:
            Created UserCategory

        Raises:
            ConflictError: If category with same name already exists for user
        """
        # Check if category with same name already exists
        result = await db.execute(
            select(UserCategory).where(
                UserCategory.user_id == user_id,
                func.lower(UserCategory.name) == name.lower()
            )
        )
        existing = result.scalar_one_or_none()

        if existing:
            raise ConflictError(f"Category '{name}' already exists")

        # Create new category
        category = UserCategory(
            user_id=user_id,
            name=name,
            description=description,
            color=color or "#6366F1"  # Default color
        )

        db.add(category)
        await db.commit()
        await db.refresh(category)

        return category

    @staticmethod
    async def get_user_categories(
        db: AsyncSession,
        user_id: str
    ) -> List[UserCategory]:
        """
        Get all categories for a user.

        Args:
            db: Database session
            user_id: User ID

        Returns:
            List of UserCategory objects
        """
        result = await db.execute(
            select(UserCategory).where(
                UserCategory.user_id == user_id
            ).order_by(
                UserCategory.usage_count.desc(),  # Most used first
                UserCategory.name.asc()  # Then alphabetically
            )
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_category(
        db: AsyncSession,
        category_id: str,
        user_id: str
    ) -> UserCategory:
        """
        Get a specific category by ID.

        Args:
            db: Database session
            category_id: Category ID
            user_id: User ID (for security)

        Returns:
            UserCategory

        Raises:
            NotFoundError: If category not found or doesn't belong to user
        """
        result = await db.execute(
            select(UserCategory).where(
                UserCategory.id == category_id,
                UserCategory.user_id == user_id
            )
        )
        category = result.scalar_one_or_none()

        if not category:
            raise NotFoundError("Category")

        return category

    @staticmethod
    async def update_category(
        db: AsyncSession,
        category_id: str,
        user_id: str,
        name: Optional[str] = None,
        description: Optional[str] = None,
        color: Optional[str] = None
    ) -> UserCategory:
        """
        Update a category.

        Args:
            db: Database session
            category_id: Category ID
            user_id: User ID (for security)
            name: New name (optional)
            description: New description (optional)
            color: New color (optional)

        Returns:
            Updated UserCategory

        Raises:
            NotFoundError: If category not found
            ConflictError: If new name conflicts with existing category
        """
        category = await CategoryService.get_category(db, category_id, user_id)

        # Check for name conflict if name is being changed
        if name and name.lower() != category.name.lower():
            result = await db.execute(
                select(UserCategory).where(
                    UserCategory.user_id == user_id,
                    UserCategory.id != category_id,
                    func.lower(UserCategory.name) == name.lower()
                )
            )
            existing = result.scalar_one_or_none()
            if existing:
                raise ConflictError(f"Category '{name}' already exists")

        # Update fields
        if name is not None:
            category.name = name
        if description is not None:
            category.description = description
        if color is not None:
            category.color = color

        await db.commit()
        await db.refresh(category)

        return category

    @staticmethod
    async def delete_category(
        db: AsyncSession,
        category_id: str,
        user_id: str
    ) -> None:
        """
        Delete a category.

        Args:
            db: Database session
            category_id: Category ID
            user_id: User ID (for security)

        Raises:
            NotFoundError: If category not found
        """
        category = await CategoryService.get_category(db, category_id, user_id)

        # Remove category from all content items (set to NULL)
        await db.execute(
            ContentItem.__table__.update().where(
                ContentItem.user_category_id == category_id
            ).values(user_category_id=None)
        )

        # Delete category
        await db.delete(category)
        await db.commit()

    @staticmethod
    async def update_usage_count(
        db: AsyncSession,
        category_id: str
    ) -> None:
        """
        Update the usage count for a category.

        Args:
            db: Database session
            category_id: Category ID
        """
        # Count content items using this category
        result = await db.execute(
            select(func.count(ContentItem.id)).where(
                ContentItem.user_category_id == category_id
            )
        )
        count = result.scalar()

        # Update category usage count
        result = await db.execute(
            select(UserCategory).where(UserCategory.id == category_id)
        )
        category = result.scalar_one_or_none()
        if category:
            category.usage_count = count
            await db.commit()

