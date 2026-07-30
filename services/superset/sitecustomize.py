"""
sitecustomize.py — Auto-loaded by Python at startup on this image.

flask-appbuilder 5.0.2 has two bugs that prevent Superset from booting
on a cold-start:

1. `flask_appbuilder.models.sqla.base.SQLA.get_tables_for_bind(None)`
   calls `inspect(None)` and raises
   `sqlalchemy.exc.NoInspectionAvailable: No inspection system is
   available for object of type <class 'NoneType'>`.

2. The default `SignallingSession.get_bind` (from flask_sqlalchemy
   2.5.x) has signature `(mapper=None, clause=None)` and rejects the
   `bind=` kwarg SQLAlchemy 1.4+ passes in some call paths, raising
   `TypeError: SignallingSession.get_bind() got an unexpected keyword
   argument 'bind'`.

Without persistent patches, the init script's `db_upgrade_safe.py`
runs once but the gunicorn workers (each a fresh Python process) crash
with the same exceptions.

This file is auto-loaded by Python's site initialization. Placing this
in `/usr/local/lib/python3.10/site-packages/sitecustomize.py` (or any
directory on sys.path after site initialization) ensures it runs at
every Python process startup.

Strategy:
- Patch the FAB SQLA class eagerly so `get_tables_for_bind(None)` is safe.
- Install an import hook on `builtins.__import__` that rebuilds
  `superset.extensions.db.session` with our patched session class after
  the first import of any `superset.*` module.

Idempotent: re-applying patches on already-patched classes is a no-op.
"""

from __future__ import annotations

import sys as _sys


def _patch_sqlalchemy_class():
    """Patch flask_appbuilder.models.sqla.base.SQLA.

    Returns the patched SignallingSession class on success, or None if
    flask_appbuilder isn't available yet.
    """
    try:
        import sqlalchemy as _sa
        from flask_appbuilder.models.sqla.base import SQLA as _FABSQLA
        from flask_sqlalchemy import SignallingSession as _FAS
    except Exception:
        return None

    if not getattr(_FABSQLA.get_tables_for_bind, "_superset_patched", False):
        @staticmethod  # type: ignore[no-untyped-def]
        def patched_get_tables_for_bind(bind):
            if bind is None:
                return []
            return _sa.inspect(bind).get_table_names()

        patched_get_tables_for_bind._superset_patched = True
        _FABSQLA.get_tables_for_bind = patched_get_tables_for_bind

    class _PatchedSignallingSession(_FAS):
        def get_bind(  # type: ignore[override]
            self,
            mapper=None,
            clause=None,
            bind=None,
            **kwargs,
        ):
            return super().get_bind(mapper=mapper, clause=clause)

    return _PatchedSignallingSession


_PatchedSignallingSession = _patch_sqlalchemy_class()


def _rebuild_db_session():
    """If `superset.extensions.db` is loaded, rebuild its session."""
    if getattr(_rebuild_db_session, "_fired", False):
        return True
    if _PatchedSignallingSession is None:
        return False

    mod = _sys.modules.get("superset.extensions")
    if mod is None:
        return False
    db = getattr(mod, "db", None)
    if db is None:
        return False

    if getattr(db.create_session, "_superset_patched", False):
        _rebuild_db_session._fired = True
        return True

    from types import MethodType
    import sqlalchemy.orm as _orm

    def _patched_create_session(self, options):  # type: ignore[no-untyped-def]
        options.setdefault("class_", _PatchedSignallingSession)
        options.setdefault("query_cls", db.Query)
        return _orm.sessionmaker(db=self, **options)

    _patched_create_session._superset_patched = True
    db.create_session = MethodType(_patched_create_session, db)

    if hasattr(db, "create_scoped_session"):
        db.session = db.create_scoped_session({})

    _rebuild_db_session._fired = True
    return True


_orig_import = (
    __builtins__.__import__
    if hasattr(__builtins__, "__import__")
    else __import__
)


def _patched_import(name, *args, **kwargs):
    """Drop-in replacement for builtins.__import__ that rebuilds
    `db.session` as soon as `superset.extensions` is loaded."""
    result = _orig_import(name, *args, **kwargs)
    if name.startswith("superset"):
        _rebuild_db_session()
    return result


try:
    import builtins as _b

    if not getattr(_b.__import__, "_superset_patched", False):
        _b.__import__ = _patched_import
        _b.__import__._superset_patched = True
except Exception:
    pass


# If `superset.extensions` is already loaded at site-init time, rebuild now.
_rebuild_db_session()
