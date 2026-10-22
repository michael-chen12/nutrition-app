# Issue tracker: GitHub

Issues and specs live in `michael-chen12/nutrition-app`. Use the connected GitHub tools when available; use `gh` from this clone when authenticated.

## Conventions

- “Publish to the issue tracker” means create a GitHub issue.
- “Fetch the relevant ticket” means read its GitHub issue.
- Use native sub-issues and issue dependencies. If unavailable, put `Part of #<parent>` or `Blocked by: #<number>` at the top of the issue body.
- A bare `#<number>` may identify an issue or a pull request; check its type.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding

- The map is one issue labeled `wayfinder:map`.
- Tickets are its child issues, labeled `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`.
- Claim an available ticket by assigning it to the driving developer. Record the answer in a comment, close the ticket, and update the map’s decisions.
