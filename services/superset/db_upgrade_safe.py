"""
db_upgrade_safe.py — Workaround for Superset 1.4.x cold-start boot bug.

Why this exists
---------------
The `apache/superset:latest` image pulled by this Dockerfile ships with
flask-appbuilder 5.0.2, which has two bugs that prevent Superset from
booting on a fresh database (or on any deploy where the schema needs
work):

1. `flask_appbuilder.models.sqla.base.SQLA.get_tables_for_bind(None)`
   calls `inspect(None)` and raises
   `sqlalchemy.exc.NoInspectionAvailable: No inspection system is available
   for object of type <class 'NoneType'>`.

2. The default `SignallingSession.get_bind` (from flask_sqlalchemy 2.5.x)
   has signature `(mapper=None, clause=None)` and rejects the `bind=`
   kwarg that SQLAlchemy 1.4+ passes in some call paths, raising
   `TypeError: SignallingSession.get_bind() got an unexpected keyword
   argument 'bind'`.

Without this script, the init loop dies with one of those errors on every
cold-start. After the script runs once successfully, the schema is at
head and the upstream `superset init`/`superset fab create-admin`
commands succeed cleanly on subsequent restarts.

Strategy
--------
Patch `flask_appbuilder.models.sqla.base.SQLA` BEFORE invoking Superset's
`create_app()`:

- Replace `SQLA.get_tables_for_bind` with a version that returns `[]` for
  `bind=None` and otherwise delegates to `sqlalchemy.inspect(...).get_table_names()`.
- Replace `db.create_session` (an instance method) with a bound version
  that sets `class_=_PatchedSignallingSession` in the sessionmaker kwargs.
  `_PatchedSignallingSession` extends `flask_sqlalchemy.SignallingSession`
  and accepts the `bind=` kwarg in `get_bind`.

Then call `create_app()` and run Alembic migrations via
`flask_migrate.upgrade()` inside an explicit app context.

CLI flags
---------
--upgrade-only   Run Alembic migrations only.
--init-only      Run `superset init` only.
--admin-only     Run `superset fab create-admin` only.
--all            Run upgrade + init + admin (default).

Exit codes
----------
0 success, 1 on unrecoverable error.
"""

from __future__ import annotations

import os
import sys
import traceback
from types import MethodType
from typing import Any


def _log(msg: str) -> None:
    print(f"[db_upgrade_safe] {msg}", flush=True)


def _install_patches() -> None:
    """Install the flask-appbuilder patches needed to boot Superset cleanly.

    These patches MUST be installed before Superset's `create_app()` is
    called. They are idempotent and only affect the FAB `SQLA` subclass
    used by `superset.extensions.db`.
    """
    import logging

    import sqlalchemy as _sa
    import sqlalchemy.orm as _orm
    from flask_appbuilder.models.sqla.base import SQLA as _FABSQLA
    from flask_sqlalchemy import SignallingSession as _FAS

    import superset.initialization as superset_init
    import superset.security as superset_security
    from superset.extensions import db, appbuilder

    # Patch 1: SQLA.get_tables_for_bind(None) returns [] instead of
    # raising NoInspectionAvailable.
    @staticmethod  # type: ignore[no-untyped-def]
    def patched_get_tables_for_bind(bind):
        if bind is None:
            return []
        return _sa.inspect(bind).get_table_names()

    _FABSQLA.get_tables_for_bind = patched_get_tables_for_bind

    # Patch 2: a SignallingSession subclass whose get_bind accepts
    # the bind= kwarg that SQLAlchemy 1.4+ may pass.
    class _PatchedSignallingSession(_FAS):
        def get_bind(  # type: ignore[override]
            self,
            mapper=None,
            clause=None,
            bind=None,
            **kwargs,
        ):
            return super().get_bind(mapper=mapper, clause=clause)

    # Patch 3: replace db.create_session (instance method) with one
    # that wires _PatchedSignallingSession into the sessionmaker.
    def _patched_create_session(self, options):  # type: ignore[no-untyped-def]
        options.setdefault("class_", _PatchedSignallingSession)
        options.setdefault("query_cls", db.Query)
        return _orm.sessionmaker(db=self, **options)

    db.create_session = MethodType(_patched_create_session, db)

    # Patch 4: rebuild db.session so the new session factory is used.
    # The session was built at __init__ time using the old (broken)
    # factory.
    if hasattr(db, "_make_scoped_session"):
        # flask-sqlalchemy 3.x
        db.session = db._make_scoped_session({})
    else:
        # flask-sqlalchemy 2.x
        db.session = db.create_scoped_session({})

    _log("Patched flask_appbuilder.SQLA: get_tables_for_bind + session factory")

    # Patch 5: wrap configure_fab to push an app context around
    # appbuilder.init_app, so that `current_app` is set when
    # SecurityManager.__init__ runs.
    SupersetAppInitializer = superset_init.SupersetAppInitializer
    SupersetSecurityManager = superset_security.SupersetSecurityManager
    SupersetIndexView = superset_init.SupersetIndexView

    def patched_configure_fab(self):  # type: ignore[no-untyped-def]
        if self.config["SILENCE_FAB"]:
            logging.getLogger("flask_appbuilder").setLevel(logging.ERROR)

        custom_sm = self.config["CUSTOM_SECURITY_MANAGER"] or SupersetSecurityManager
        if not issubclass(custom_sm, SupersetSecurityManager):
            raise Exception(
                """Your CUSTOM_SECURITY_MANAGER must now extend SupersetSecurityManager,
                 not FAB's security manager.
                 See [4565] in UPDATING.md"""
            )

        with self.superset_app.app_context():
            appbuilder.indexview = SupersetIndexView
            appbuilder.base_template = "superset/base.html"
            appbuilder.security_manager_class = custom_sm
            appbuilder.init_app(self.superset_app, db.session)

    SupersetAppInitializer.configure_fab = patched_configure_fab
    _log("Patched SupersetAppInitializer.configure_fab")


def _build_app() -> Any:
    """Build the real Superset Flask app with patches applied."""
    _install_patches()

    flask_app = os.environ.get("FLASK_APP", "superset.app:create_app()")
    if ":" not in flask_app:
        raise RuntimeError(
            f"FLASK_APP must be in module:attr form (got {flask_app!r})"
        )
    module_name, attr_name = flask_app.split(":", 1)
    attr_name = attr_name.rstrip("()")
    import importlib

    _log(f"Importing {module_name}.{attr_name}")
    factory = getattr(importlib.import_module(module_name), attr_name)
    _log("Creating Flask app via factory...")
    app = factory()
    _log(f"Flask app created: {app.name!r}")
    return app


def _run_alembic_upgrade(app: Any) -> None:
    """Run Alembic to head inside the real Superset app context."""
    from flask_migrate import upgrade as alembic_upgrade

    with app.app_context():
        from superset.extensions import db

        engine = db.engine
        _log(
            "SQLAlchemy engine: "
            f"{engine.url.render_as_string(hide_password=True)}"
        )

        _log("Running Alembic upgrade() to head...")
        alembic_upgrade()
        _log("Alembic upgrade() complete.")


def _run_superset_init(app: Any) -> None:
    """Seed roles and permissions.

    Equivalent to `superset init`. We bypass FlaskGroup (which fails on
    click 8.x with `app=` kwarg) and call the underlying logic directly
    inside an app context.
    """
    _log("Seeding roles and permissions (superset init)...")
    with app.app_context():
        from superset.extensions import appbuilder, security_manager

        appbuilder.add_permissions(update_perms=True)
        security_manager.sync_role_definitions()
    _log("`superset init` complete.")


def _run_fab_create_admin(app: Any) -> None:
    """Create the default admin user.

    Equivalent to `superset fab create-admin`. We bypass FlaskGroup (which
    fails on click 8.x with `app=` kwarg) and call SecurityManager.add_user
    directly inside an app context. Idempotent: add_user returns False
    for duplicate users, which we treat as success.
    """
    username = os.environ.get("ADMIN_USERNAME")
    password = os.environ.get("ADMIN_PASSWORD")
    email = os.environ.get("ADMIN_EMAIL")
    if not (username and password and email):
        _log(
            "ADMIN_USERNAME/ADMIN_PASSWORD/ADMIN_EMAIL not all set; "
            "skipping admin creation"
        )
        return

    firstname = os.environ.get("ADMIN_FIRSTNAME", "Superset")
    lastname = os.environ.get("ADMIN_LASTNAME", "Admin")
    _log(f"Creating admin user {username!r}...")
    with app.app_context():
        from superset.extensions import appbuilder

        sm = appbuilder.sm
        existing = sm.find_user(username=username)
        if existing:
            _log(f"Admin user {username!r} already exists; skipping.")
            return
        existing_by_email = sm.find_user(email=email)
        if existing_by_email:
            _log(
                f"User with email {email!r} already exists; skipping admin creation."
            )
            return
        role = sm.find_role(sm.auth_role_admin)
        roles = [role] if role else []
        result = sm.add_user(
            username=username,
            first_name=firstname,
            last_name=lastname,
            email=email,
            password=password,
            role=roles,
        )
        if result:
            _log(f"Admin user {username!r} created.")
        else:
            _log(f"Failed to create admin user {username!r}.")
def _parse_args(argv: list[str]) -> dict[str, bool]:
    flags = {
        "upgrade_only": False,
        "init_only": False,
        "admin_only": False,
        "all": False,
    }
    for arg in argv:
        if arg == "--upgrade-only":
            flags["upgrade_only"] = True
        elif arg == "--init-only":
            flags["init_only"] = True
        elif arg == "--admin-only":
            flags["admin_only"] = True
        elif arg == "--all":
            flags["all"] = True
    if not any(flags.values()):
        flags["all"] = True
    return flags


def main() -> int:
    flags = _parse_args(sys.argv[1:])
    try:
        # Build the app ONCE, reuse for all subsequent steps. Each
        # step pushes its own app context.
        app = _build_app()

        if flags["all"] or flags["upgrade_only"]:
            _run_alembic_upgrade(app)

        if flags["all"] or flags["init_only"]:
            try:
                _run_superset_init(app)
            except Exception as init_exc:
                _log(
                    f"WARNING: superset init seeding failed (non-fatal): "
                    f"{init_exc!r}"
                )

        if flags["all"] or flags["admin_only"]:
            _run_fab_create_admin(app)

        _log("OK")
        return 0
    except SystemExit as exc:
        return int(exc.code or 0)
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
