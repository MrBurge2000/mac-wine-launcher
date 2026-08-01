## Summary

<!-- What changed and why? -->

## User impact

<!-- What will users notice? Include migration or compatibility concerns. -->

## Validation

- [ ] `swift test`
- [ ] `./scripts/package-app.sh`
- [ ] I tested destructive and shutdown behavior where relevant.
- [ ] I added or updated tests for changed behavior.
- [ ] I updated user-facing documentation.

## Safety checklist

- [ ] This change does not collect Steam credentials or secrets.
- [ ] Downloads are HTTPS-only, version-pinned, and checksum-verified.
- [ ] File deletion and process termination remain scoped to managed resources.
- [ ] This change does not bypass DRM, ownership, anti-cheat, or platform security.
