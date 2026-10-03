# LAB-032-B — Focus context construction during render qualification

Status: accepted 2026-10-02.

## Decision

The host's Focus predicate evaluates `SELF IN` the allowed lab identifiers against notification content's `filterCriteria` string. The reminder adapter sets that string to its existing lab notification identifier. Foreign identifiers are removed before constructing the predicate; an empty selection allows nothing.

## Rationale and consequences

The repeated render lifecycle test crashed in `LabFocusFilterIntent.appContext`, with `EXC_BREAKPOINT` / `SIGTRAP`, rather than in render expiration. Constructing that context directly reproduced signal 5 in a package regression. The old `request.identifier` key path describes a notification request, but Focus evaluates a string. Apple's [Focus example](https://developer.apple.com/videos/play/wwdc2022/10121/) uses `SELF` and `UNNotificationContent.filterCriteria`.

This is the smallest shared correction needed for the assigned render-host crash. It adds no permission, service, framework, or notification route. The render's lifecycle and domain operations are unchanged.

## Validation

`RespectfulAttentionTests.theFocusContextEvaluatesNotificationFilterCriteria` and `RenderSurvivesPhoneTests.theHostsFocusContextCanBeReadWhileQualifyingRenders` construct the real context and evaluate allowed, foreign, and empty selections. Commands and results belong to [LAB-032-B](../../tickets/LAB-032-B.md). Notification delivery and a person enabling Focus on a device remain unverified.
