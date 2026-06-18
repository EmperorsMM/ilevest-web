# @ilevest/contract — the API contract (source of truth)

This folder holds the **OpenAPI 3.1 contract** for the Ilevest API. It is the **single
source of truth**: the web app and the Android Oracle app both build against it (generated
types/clients), and CI validates it on every pull request.

- The real contract is authored in **Build Stage 2** (the next-but-one step).
- `openapi.yaml` here is a **valid placeholder** (no endpoints yet) so tooling and CI work.

> Decision flagged to the design team: the Android repo also needs this contract. For Phase 1
> it lives here as the source of truth and Android consumes the generated client. If the team
> prefers a standalone `ilevest-contract` repo, we can extract it — it is just a file.
