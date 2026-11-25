# Contributing to cis_libs

Thank you for helping. Bug reports, reproductions and pull requests are all welcome.

## Before you open a pull request

`cis_libs` is source-available, not open source. Read `LICENSE.md` first. Section 4 holds the contributor terms: by opening a pull request you license your change to Cisoko so it can ship as part of `cis_libs`. We cannot merge a pull request whose author has not agreed to them.

To agree, put this line in the pull request description:

> I have read the contributor terms in LICENSE.md section 4 and I agree to them for this contribution.

Please do not submit code copied from another project, especially GPL or LGPL code such as ox_lib, qb-core, qbx_core or the ox resources. `cis_libs` is written from documentation and observed behaviour, not from their source.

## What makes a good pull request

- One fix or feature per pull request.
- A test under `test/` that fails before your change and passes after it.
- `npm run test:all` passes on Node 24 or newer.
- A change to the public surface also updates `api.lua`; `npm run test:api` and `npm run gen-types:check` catch a mismatch.
- If you change behaviour that users see, update `README.md`, `DOCUMENTATION.md` or `CHANGELOG.md` in the same pull request.

## Reporting a bug

Open an issue with:

- the FXServer artifact number and your OS;
- your framework, and the resource that made the call (redact player data);
- what you expected and what happened, with the console lines.

Security problems go through `SECURITY.md`, not a public issue.

## Sharing your changes

The license does not allow publishing a modified copy of `cis_libs`. If you built something useful on top of it, send it back as a pull request, or ship it as a separate resource that calls the `cis_libs` exports.
