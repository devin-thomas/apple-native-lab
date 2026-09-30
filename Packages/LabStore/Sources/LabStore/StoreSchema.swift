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
}
