"""Isolated synthetic recovery drills; never connect this tool to a hosted project.

Requires PostgreSQL 17 client tools or the pinned disposable CI container. It only
backs up databases it creates itself, and never drops/resets a database.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import uuid


def restore_objects(source: Path, destination: Path, entries: list[dict]) -> None:
    """Copy only inventoried bytes. A final receipt distinguishes a complete recovery.

    Source and parent must be operator-owned/quiescent, not an active Storage volume.
    Existing destinations are refused, including incomplete prior attempts.
    """
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Expected a private object snapshot directory")
    parent = destination.parent.stat()
    if parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) & 0o077:
        raise ValueError("Recovery parent must be private and operator-owned")
    keys = set()
    for entry in entries:
        key = entry["key"]
        if not isinstance(key, str):
            raise ValueError("Invalid private object key")
        path = PurePosixPath(key)
        if (str(path) != key or path.is_absolute()
                or ".." in path.parts or "\\" in key or len(path.parts) < 2
                or path.parts[0] != "teamstats-private" or key in keys):
            raise ValueError("Invalid or repeated private object key")
        keys.add(key)
        if type(entry["bytes"]) is not int or not 0 < entry["bytes"] <= 10 * 1024 * 1024:
            raise ValueError("Invalid object byte count")
        item = source
        for part in path.parts:
            item = item / part
            if item.is_symlink():
                raise ValueError("Symlinked object paths are not supported")
        if not item.is_file() or item.stat().st_size != entry["bytes"]:
            raise ValueError("An inventoried object is missing or has the wrong size")
        if digest(item) != entry["sha256"]:
            raise ValueError("An inventoried object failed its digest check")
    # mkdir is exclusive: a concurrent or existing destination is never replaced.
    destination.mkdir(mode=0o700)
    (destination / "INCOMPLETE").write_text("Recovery is not usable until recovery-complete.json exists.\n")
    for entry in entries:
        target = destination / entry["key"]
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copyfile(source / entry["key"], target)
        target.chmod(0o600)
        if digest(target) != entry["sha256"]:
            raise ValueError("Copied object failed its digest check; recovery is incomplete")
    receipt = json.dumps({"schemaVersion": 1, "objects": entries}, sort_keys=True).encode()
    pending = destination / "receipt.pending"
    with pending.open("xb") as stream:
        stream.write(receipt)
        stream.flush()
        os.fsync(stream.fileno())
    pending.chmod(0o600)
    pending.rename(destination / "recovery-complete.json")
    (destination / "INCOMPLETE").unlink()  # This invocation's marker, never source bytes.


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class IsolatedPostgres:
    def __init__(self, output: Path, pg_bin: Path | None, container: str | None):
        if os.environ.get("PGHOST") not in ("127.0.0.1", "::1", "localhost"):
            raise ValueError("Only an explicitly configured isolated loopback server is allowed")
        if container and not re.fullmatch(r"[a-f0-9]{12,64}", container):
            raise ValueError("Expected the disposable service's container ID")
        self.output, self.pg_bin, self.container = output, pg_bin, container

    def run(self, tool: str, args: list[str], data: bytes | None = None) -> bytes:
        if self.container:
            command = ["docker", "exec", "-i"]
            for name in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD"):
                if name in os.environ:
                    command += ["-e", name]  # Names only; credentials never enter argv/logs.
            command += [self.container, tool]
        else:
            command = [str(self.pg_bin / tool)]
        result = subprocess.run(command + args, input=data, capture_output=True, timeout=120)
        if result.returncode:
            with (self.output / "diagnostics.local.log").open("ab") as log:
                log.write(result.stderr)
            raise RuntimeError(f"Synthetic {tool} failed; private diagnostics retained")
        return result.stdout

    def sql(self, database: str, text: str) -> str:
        return self.run("psql", ["-X", "-qAt", "-v", "ON_ERROR_STOP=1", "--dbname", database],
                        text.encode()).decode().strip()

    def snapshot(self, database: str) -> dict:
        tables = self.sql(database, """select quote_ident(schemaname)||'.'||quote_ident(tablename)
            from pg_tables where schemaname in
            ('public','auth','storage','team_private','supabase_migrations') order by 1""").splitlines()
        rows = {table: json.loads(self.sql(database,
                f"select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from {table} t"))
                for table in tables}
        policies = self.sql(database, """select coalesce(jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname),'[]')
            from pg_policies p where schemaname in ('public','storage','team_private','supabase_migrations')""")
        # Resolve default ACLs: pg_restore can represent explicit owner-only ACLs as NULL.
        # Compare effective grants, RLS flags and SECURITY DEFINER/search-path properties.
        security = self.sql(database, """select jsonb_build_object(
          'relations',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity,
            (select jsonb_agg(a::text order by a::text) from unnest(coalesce(c.relacl,
              acldefault((case when c.relkind='S' then 'S' else 'r' end)::"char",c.relowner))) a))
            order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname in ('public','auth','storage','team_private','supabase_migrations') and c.relkind in ('r','v','S')),
          'schemas',(select jsonb_agg(jsonb_build_array(nspname,
            (select jsonb_agg(a::text order by a::text) from unnest(coalesce(nspacl,acldefault('n',nspowner))) a))
            order by nspname) from pg_namespace
            where nspname in ('public','auth','storage','team_private','supabase_migrations')),
          'functions',(select jsonb_agg(jsonb_build_array(n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
            p.prosecdef,p.proconfig,(select jsonb_agg(a::text order by a::text)
              from unnest(coalesce(p.proacl,acldefault('f',p.proowner))) a))
            order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname in ('public','auth','team_private')))
        """)
        return {"rows": rows, "policies": json.loads(policies), "security": json.loads(security)}


def database_drill(pg: IsolatedPostgres, root: Path, initialize_roles: bool) -> dict:
    version = int(pg.sql("postgres", "show server_version_num"))
    client = pg.run("pg_dump", ["--version"]).decode().strip()
    if not 170000 <= version < 180000 or " 17." not in client:
        raise ValueError("This drill requires PostgreSQL 17 server and dump tools")
    # Source migrations can create cluster-wide roles. New databases are insufficient.
    # Refuse any nonfresh inventory before creating roles, memberships or databases.
    inventory=json.loads(pg.sql("postgres", """select jsonb_build_object(
      'databases',(select jsonb_agg(datname order by datname) from pg_database),
      'roles',(select jsonb_agg(rolname order by rolname) from pg_roles where rolname !~ '^pg_'),
      'memberships',(select count(*) from pg_auth_members m join pg_roles r on r.oid=m.member where r.rolname !~ '^pg_'),
      'objects',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema')
       +(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema'))"""))
    expected_roles={'postgres'} if initialize_roles else {'postgres','anon','authenticated','authenticator','service_role'}
    if (set(inventory.get('databases',[])) != {'postgres','template0','template1'}
            or set(inventory.get('roles',[])) != expected_roles
            or inventory.get('objects') != 0 or inventory.get('memberships') != 0):
        raise ValueError("Recovery migrations require a fresh synthetic cluster; no authority or data was changed")
    # This optional role creation is ONLY for the brand-new disposable CI cluster.
    roles = pg.sql("postgres", "select rolname from pg_roles where rolname in ('anon','authenticated','authenticator','service_role') order by 1")
    if initialize_roles:
        if not pg.container:
            raise ValueError("Role initialization is restricted to the disposable CI container")
        if roles:
            raise ValueError("Role initialization requires a fresh disposable test cluster")
        pg.sql("postgres", "create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; create role authenticator nologin noinherit;")
    elif roles.splitlines() != ["anon", "authenticated", "authenticator", "service_role"]:
        raise ValueError("Expected existing isolated test roles; no roles were changed")
    suffix = uuid.uuid4().hex
    source, restored = "teamstats_recovery_source_" + suffix, "teamstats_recovery_restored_" + suffix
    (pg.output / "plan.json").write_text(json.dumps({"source": source, "restored": restored,
        "syntheticOnly": True, "existingDatabasesExported": False}, indent=2) + "\n")
    for database in (source, restored):
        pg.run("createdb", ["--template", "template0", database])
    pg.sql(source, (root / "supabase/tests/recovery_platform.sql").read_text())
    migrations = []
    for file in sorted((root / "supabase/migrations").glob("*.sql")):
        pg.sql(source, file.read_text())
        migrations.append({"name": file.name, "sha256": digest(file)})
        literal = file.read_text().replace("'", "''")
        pg.sql(source, "insert into supabase_migrations.schema_migrations values ('" +
               file.name.split("_")[0] + "','" + file.stem + "',array['" + literal + "']);")
    pg.sql(source, (root / "supabase/tests/recovery_records.sql").read_text())
    before = pg.snapshot(source)
    archive = pg.run("pg_dump", ["--format=custom", "--no-owner", "--dbname", source])
    backup = pg.output / "synthetic-database.dump"
    backup.write_bytes(archive)
    backup.chmod(0o600)
    pg.run("pg_restore", ["--single-transaction", "--exit-on-error", "--no-owner", "--dbname", restored], archive)
    after = pg.snapshot(restored)
    if before != after:
        raise RuntimeError("Restored rows/relationships/policies differ from the synthetic source")
    pg.sql(restored, (root / "supabase/tests/recovery_assertions.sql").read_text())
    pg.sql(restored, (root / "supabase/tests/file_request_admission.sql").read_text())
    # New datasets/sessions/grants are never manufactured after restore to make checks pass.
    if after != pg.snapshot(restored) or before != pg.snapshot(source):
        raise RuntimeError("Recovery assertions unexpectedly changed a saved dataset")
    return {"source": source, "restored": restored, "migrations": migrations,
            "backupSHA256": digest(backup), "serverVersion": version, "dumpTool": client,
            "tablesCompared": len(before["rows"]),
            "restoredRowsAndPoliciesEqual": True, "permissionsChecked": True,
            "actualSupabaseAuthRecovery": False, "hostedRecovery": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    tools = parser.add_mutually_exclusive_group(required=True)
    tools.add_argument("--pg-bin", type=Path)
    tools.add_argument("--container")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--confirm-isolated-cluster", action="store_true", required=True)
    parser.add_argument("--initialize-test-roles", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(mode=0o700)  # Refuses occupied output; artifacts retained on failure.
    pg = IsolatedPostgres(args.output, args.pg_bin, args.container)
    receipt = database_drill(pg, Path(__file__).resolve().parents[1], args.initialize_test_roles)
    # File bytes are deliberately absent from the database archive.
    source = args.output / "object-source"
    key = "teamstats-private/synthetic-team/synthetic-version"
    (source / key).parent.mkdir(parents=True, mode=0o700)
    data = b"TEST ONLY independent recovery bytes\n"
    (source / key).write_bytes(data)
    entries = [{"key": key, "bytes": len(data), "sha256": digest(source / key)}]
    restore_objects(source, args.output / "object-backup", entries)
    restore_objects(args.output / "object-backup", args.output / "object-restored", entries)
    if (args.output / "object-restored" / key).read_bytes() != data:
        raise RuntimeError("Restored synthetic bytes differ")
    metadata = pg.sql(receipt["restored"], "select bucket_id||'/'||name from storage.objects")
    if metadata != key:
        raise RuntimeError("Restored database object identity does not match separate bytes")
    receipt["separateSyntheticObjectRecovery"] = entries
    receipt["outboundWorkersStarted"] = False
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"PASS: {len(receipt['migrations'])} migrations; synthetic database backup/restore, policies and separate object bytes")


if __name__ == "__main__":
    main()
