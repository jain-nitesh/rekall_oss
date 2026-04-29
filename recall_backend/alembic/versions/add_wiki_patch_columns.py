from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'd5f7a1b3c9e2'
down_revision: Union[str, None] = 'c4e6f8a0b2d4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

def upgrade():
    op.add_column('wiki_pages', sa.Column('patch_count', sa.Integer(), server_default='0', nullable=False))
    op.add_column('wiki_pages', sa.Column('compilation_mode', sa.String(20), server_default='full', nullable=False))

def downgrade():
    op.drop_column('wiki_pages', 'compilation_mode')
    op.drop_column('wiki_pages', 'patch_count')
