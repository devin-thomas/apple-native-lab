# Experiment template

## Identity

Stable ID, working title, category, milestone, implementation state, supported host targets, and source-review date.

## The moment

Describe one observable user payoff in two sentences. Explain why native integration makes it different from an ordinary standalone screen.

## Build contract

Name domain types, shared operations, platform adapters, required permissions, hardware gates, resource limits, and any extension/account setup. Identify which parts already exist and which are proposals.

## Interaction

Give the complete happy-path sequence from first action to inspectable result. Include reset and the point where a user authorizes a side effect.

## Acceptance

Write concrete tests for happy path, denied/unavailable path, malformed input, cancellation, duplicate/stale state, accessibility, and data cleanup. Separate physical-device proof from fixtures/simulator coverage.

## Fallback and boundaries

Define a useful alternate route. State what is not supported and what the experiment deliberately does not do.

## Delivery

Link the implementation and qualification tickets, dependencies, official references, and eventual evidence. Do not mark a claim verified until the named test was actually run.
