/// The released versions of the store's file format and the steps between them.
///
/// A migration is append-only: once a version ships, its SQL never changes, and a later version
/// adds a new step. Each step runs in its own write transaction together with the new
/// `user_version`, so an interrupted migration leaves the file at the previous version.
enum StoreSchema {
    /// `PRAGMA application_id`, "LABS", which marks a file as this store's.
    static let applicationID = 0x4C41_4253

    struct Migration: Sendable {
        let version: Int
        let sql: String
    }

    static let migrations = [
        Migration(version: 1, sql: version1),
        Migration(version: 2, sql: version2),
        Migration(version: 3, sql: version3),
        Migration(version: 4, sql: version4),
        Migration(version: 5, sql: version5),
        Migration(version: 6, sql: version6),
    ]

    static var currentVersion: Int { migrations[migrations.count - 1].version }

    /// Version 1: entities, receipts, and opaque `extras`, before namespaces.
    ///
    /// `extras` holds metadata this build does not interpret, as a JSON object. The store never
    /// rewrites it: an upsert leaves it in place and a migration carries it over unchanged.
    static let version1 = """
        CREATE TABLE collections (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            title TEXT NOT NULL,
            is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;

        CREATE TABLE items (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            collection_id TEXT NOT NULL REFERENCES collections (id),
            title TEXT NOT NULL,
            note TEXT NOT NULL,
            is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;

        CREATE INDEX items_by_collection ON items (collection_id);

        CREATE TABLE receipts (
            request_id TEXT PRIMARY KEY NOT NULL CHECK (length(request_id) = 36),
            operation_id TEXT NOT NULL UNIQUE,
            body TEXT NOT NULL CHECK (json_valid(body))
        ) STRICT;

        CREATE TRIGGER receipts_are_immutable BEFORE UPDATE ON receipts
        BEGIN SELECT RAISE(ABORT, 'lab-receipt: a recorded receipt never changes'); END;

        CREATE TRIGGER receipts_are_kept BEFORE DELETE ON receipts
        BEGIN SELECT RAISE(ABORT, 'lab-receipt: a recorded receipt never changes'); END;
        """

    /// Version 2: demo and user namespaces.
    ///
    /// Everything stored before namespaces existed becomes user data, so Reset Demo can never
    /// remove it. The triggers make the namespace rules hold for any writer of the file, not only
    /// for this module's code: an entity keeps its namespace, an item has its collection's
    /// namespace, and a user row is never deleted.
    static let version2 = """
        ALTER TABLE collections ADD COLUMN namespace TEXT NOT NULL DEFAULT 'user' CHECK (namespace IN ('user', 'demo'));
        ALTER TABLE items ADD COLUMN namespace TEXT NOT NULL DEFAULT 'user' CHECK (namespace IN ('user', 'demo'));

        CREATE INDEX collections_by_namespace ON collections (namespace);
        CREATE INDEX items_by_namespace ON items (namespace);

        CREATE TRIGGER collections_keep_their_namespace BEFORE UPDATE OF namespace ON collections
        WHEN NEW.namespace IS NOT OLD.namespace
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: an entity never changes namespace'); END;

        CREATE TRIGGER items_keep_their_namespace BEFORE UPDATE OF namespace ON items
        WHEN NEW.namespace IS NOT OLD.namespace
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: an entity never changes namespace'); END;

        CREATE TRIGGER items_join_their_collection_namespace BEFORE INSERT ON items
        WHEN NEW.namespace IS NOT (SELECT namespace FROM collections WHERE id = NEW.collection_id)
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: an item has its collection''s namespace'); END;

        CREATE TRIGGER items_stay_in_their_collection_namespace BEFORE UPDATE OF collection_id, namespace ON items
        WHEN NEW.namespace IS NOT (SELECT namespace FROM collections WHERE id = NEW.collection_id)
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: an item has its collection''s namespace'); END;

        CREATE TRIGGER user_collections_are_never_deleted BEFORE DELETE ON collections
        WHEN OLD.namespace = 'user'
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: user data is never deleted'); END;

        CREATE TRIGGER user_items_are_never_deleted BEFORE DELETE ON items
        WHEN OLD.namespace = 'user'
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: user data is never deleted'); END;
        """

    /// Version 3: sessions (LAB-004 Surface Deck).
    ///
    /// A session is a running-or-paused flag with a revision. It is lab state, so its namespace is
    /// always `demo`: Reset Demo pauses it and never touches user data. Nothing earlier changes.
    static let version3 = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            is_running INTEGER NOT NULL CHECK (is_running IN (0, 1)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            namespace TEXT NOT NULL DEFAULT 'demo' CHECK (namespace = 'demo'),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;
        """

    /// Version 4: lab alerts (LAB-043 Respectful Attention).
    ///
    /// A row is one lab-owned reminder, Focus filter, or alarm. The namespace is always `demo`,
    /// so Reset Demo can remove these rows and can never remove a person's collections. The civil
    /// time keeps its time zone identifier; nothing here reads the device's current zone.
    static let version4 = """
        CREATE TABLE attentions (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            channel TEXT NOT NULL CHECK (channel IN ('reminder', 'focus-filter', 'alarm')),
            reason TEXT NOT NULL CHECK (length(reason) BETWEEN 1 AND 120),
            year INTEGER NOT NULL,
            month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
            day INTEGER NOT NULL CHECK (day BETWEEN 1 AND 31),
            hour INTEGER NOT NULL CHECK (hour BETWEEN 0 AND 23),
            minute INTEGER NOT NULL CHECK (minute BETWEEN 0 AND 59),
            time_zone TEXT NOT NULL CHECK (length(time_zone) BETWEEN 1 AND 80),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            namespace TEXT NOT NULL DEFAULT 'demo' CHECK (namespace = 'demo'),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;
        """

    /// Version 5: jobs (LAB-032 Render That Survives).
    ///
    /// A job is finite work a person started: its kind, title, phase, durable progress, and a
    /// revision. `detail` holds the phase with its payload (why it stopped, how it failed, or what
    /// it published) as JSON, and `phase` repeats the phase's name so the store can check it. A job
    /// keeps its namespace, and a user job is never deleted. Nothing earlier changes.
    static let version5 = """
        CREATE TABLE jobs (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 40),
            title TEXT NOT NULL,
            phase TEXT NOT NULL CHECK (phase IN ('running', 'interrupted', 'succeeded', 'failed', 'cancelled')),
            detail TEXT NOT NULL CHECK (json_valid(detail)),
            completed_units INTEGER NOT NULL CHECK (completed_units >= 0),
            total_units INTEGER CHECK (total_units IS NULL OR (total_units >= 1 AND completed_units <= total_units)),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            namespace TEXT NOT NULL CHECK (namespace IN ('user', 'demo')),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;

        CREATE INDEX jobs_by_kind ON jobs (kind);

        CREATE TRIGGER jobs_keep_their_namespace BEFORE UPDATE OF namespace ON jobs
        WHEN NEW.namespace IS NOT OLD.namespace
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: an entity never changes namespace'); END;

        CREATE TRIGGER jobs_keep_their_kind BEFORE UPDATE OF kind ON jobs
        WHEN NEW.kind IS NOT OLD.kind
        BEGIN SELECT RAISE(ABORT, 'lab-job: a job never changes kind'); END;

        CREATE TRIGGER user_jobs_are_never_deleted BEFORE DELETE ON jobs
        WHEN OLD.namespace = 'user'
        BEGIN SELECT RAISE(ABORT, 'lab-namespace: user data is never deleted'); END;
        """

    /// Version 6: lab-owned anchors (LAB-023 Tabletop Reality).
    ///
    /// An anchor is a fixture key, a title, and a pose in whole millimeters and degrees in its
    /// scene's own frame. It is lab state, so its namespace is always `demo`: Reset Demo removes
    /// every anchor and never touches user data. No column holds world coordinates, camera images,
    /// or mapping data. Nothing earlier changes.
    static let version6 = """
        CREATE TABLE anchors (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            fixture TEXT NOT NULL CHECK (length(fixture) BETWEEN 1 AND 40),
            title TEXT NOT NULL,
            x_mm INTEGER NOT NULL CHECK (x_mm BETWEEN -5000 AND 5000),
            y_mm INTEGER NOT NULL CHECK (y_mm BETWEEN -5000 AND 5000),
            z_mm INTEGER NOT NULL CHECK (z_mm BETWEEN -5000 AND 5000),
            yaw_degrees INTEGER NOT NULL CHECK (yaw_degrees BETWEEN 0 AND 359),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            namespace TEXT NOT NULL DEFAULT 'demo' CHECK (namespace = 'demo'),
            extras TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extras))
        ) STRICT;
        """
}
