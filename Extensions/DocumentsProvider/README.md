# Documents Provider (LAB-009)

Local-fixture File Provider extension sources for Documents Everywhere.

This folder is **not** attached to an Xcode target in LAB-009-A. File Provider is a
FrontierOptional capability ([BUILD_AND_DISTRIBUTION](../../docs/BUILD_AND_DISTRIBUTION.md)):
it must not enter CoreLocal or SystemSurfaces. The domain model
(`ProviderSession`, revision rules, eviction) is tested in `DocumentsEverywhereTests`. The
host keeps the provider disabled. LAB-009-B qualifies the available browser and fixture
model only; no FrontierOptional host exists to qualify. Embedding this extension and
registering a domain remain a separate owner decision and live-adapter qualification gate.
