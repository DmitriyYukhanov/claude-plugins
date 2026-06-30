# Demo Service — Companion

## Overview

Synthetic two-file C# project. `Service` depends on `IProvider`. `DefaultProvider` is the default implementation. The aim of this sample is to exercise the `codebase` archetype's "no user-authored docs → synthesize a companion" path.

## Map

- Entry: `src/Service.cs` — public `Service` class.
- Provider: `src/Provider.cs` — `IProvider` interface and `DefaultProvider` implementation.
- Sample README: `README.md`.

## Glossary

- **Service** — The high-level façade callers depend on.
- **Provider** — Pluggable strategy for transforming greetings.

## Where to look next

- Follow the constructor chain in `src/Service.cs:5` to see how `IProvider` is injected.
- `src/Provider.cs:9` is the only behavioural seam to swap.
