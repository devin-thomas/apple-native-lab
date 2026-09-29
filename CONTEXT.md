# Context and product principles

The opportunity is compositional: a well-designed object can appear in a native app, an intent, a share workflow, a system surface, a continuation, and an authorized local-device session without duplicating its business behavior. The lab explores those compositions through bounded examples.

## Design values

**Demonstrate the mechanism.** Every impressive effect should have an inspectable input, operation, result, and failure mode. The app should be delightful both when it works and when it explains why a device cannot perform the live version.

**Local usefulness before infrastructure.** Original fixtures and local persistence create immediate value. Account setup, cloud sync, remote inference, and specialized entitlements are extensions rather than the foundation.

**Native rather than uniform.** The same domain behavior may use a keyboard command on Mac, an intent on iPhone, a short interaction on Watch, and a focused card on TV. Visual consistency does not justify unusable platform conventions.

**A truthful fallback is a feature.** Simulated peer sessions, manual data entry, and fixture playback are legitimate learning tools. Label them clearly and keep them behaviorally close to the real adapters.

**Prototype does not mean permissionless.** Consent, revocation, data minimization, asset rights, and destructive-action safety remain requirements even when the sample is small.

## Evidence posture

This package combines original product design with a dated Apple primary-source review. A reviewed document supports an API direction, not a successful compile or a device test. Reference-only links identify the next implementation research step. [SOURCE_INDEX](docs/SOURCE_INDEX.md) and [VERIFICATION_BOUNDARIES](docs/VERIFICATION_BOUNDARIES.md) preserve that distinction.
