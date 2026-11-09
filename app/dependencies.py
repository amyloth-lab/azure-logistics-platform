"""Auth dependencies live in app.security; this module keeps imports stable."""

from app.security import CurrentUser, get_current_user, is_manager, require_role

__all__ = ["CurrentUser", "get_current_user", "is_manager", "require_role"]
