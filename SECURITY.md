# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through GitHub:
**[Report a vulnerability](https://github.com/KilatHost/artifact/security/advisories/new)**
(the repository's Security tab, then *Report a vulnerability*).

Do not open a public issue, pull request or discussion for a security problem,
and do not include working exploits against other people's data or real
credentials in any report.

Please include:

- The affected version (`VERSION`, the image tag or digest, or a commit).
- The component (web app, MCP endpoint, OAuth, artifact sandbox, PDF export, Compose setup).
- Steps to reproduce on your own instance, and the impact you observed.

Maintainers will acknowledge the report in the advisory, keep you updated
there while they investigate, and credit you in the advisory and changelog
unless you ask not to be named. Please give us a reasonable chance to release
a fix before you disclose the issue publicly.

## Supported versions

Security fixes are released for the latest `1.x` minor version. Upgrade with
the procedure in [deploy.md](deploy.md#upgrade-and-rollback) to receive them.

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Untagged `main` builds | Best effort; upgrade to a release |

## Scope

In scope: escaping the artifact sandbox or reading app cookies, storage or pages
from an artifact; access to another workspace's artifacts, versions, files,
design kits or connections; MCP scope or OAuth bypasses (for example `write`
acting as `publish`); private content reachable through public links after
unpublish; server-side request forgery or code execution, including through PDF
export; authentication and session flaws.

Out of scope: weaknesses that need a misconfigured deployment contrary to
[deploy.md](deploy.md) (for example exposed PostgreSQL or disabled host
checks); script execution inside an artifact's own sandbox, which is intended;
denial of service by volume; reports from automated scanners without a
demonstrated impact.

Test only against instances you run yourself.
