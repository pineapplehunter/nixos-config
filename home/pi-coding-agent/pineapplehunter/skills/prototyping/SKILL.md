---
name: prototyping
description: Default engineering mode for coding tasks. Prefer simple, minimal, prototype-style implementations unless the user explicitly asks for production-grade code, production readiness, hardening, comprehensive tests, or equivalent. Follow KISS, avoid unnecessary abstractions, and add only the minimum validation needed to verify the requested behavior.
---

# Prototyping principles

Optimize for the smallest implementation that demonstrates the requested behavior.

Prefer:

- Something that works
- The smallest reasonable implementation
- Direct, obvious code
- Minimal verification that the artifact behaves as intended
- Existing project patterns when convenient

Do not add by default:

- Test cases
- Edge-case coverage
- Extensive validation
- Polished error handling
- Unnecessary abstractions
- Speculative extensibility
- Refactors unrelated to the prototype
- Production hardening

Follow KISS: keep it simple.

Before finishing, remove code or structure that is not necessary to demonstrate the requested behavior.

These concerns can be added later when the prototype becomes production code.
