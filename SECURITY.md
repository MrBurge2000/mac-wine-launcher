# Security policy

## Supported versions

Only the latest published SteamBridge release receives security fixes.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
**Security → Report a vulnerability** form for this repository. Include:

- the affected SteamBridge version and macOS version;
- clear reproduction steps;
- the expected and observed behavior;
- relevant logs with credentials, account names, and personal paths removed;
- whether the issue could delete data, execute code, expose credentials, or bypass a
  download-integrity check.

The maintainer will acknowledge a complete report when practical, investigate it
privately, and coordinate disclosure after a fix is available. Please do not test on
systems or accounts you do not own or have permission to use.

## Security design

- Managed runtime downloads use HTTPS, pinned versions, and SHA-256 checksums.
- Bottle deletion is restricted to SteamBridge's managed Bottles directory.
- Windows launch arguments are parsed without invoking a shell.
- Steam credentials are entered into Steam, never SteamBridge.
- Wine shutdown targets processes associated with both the managed bottle and its Wine
  engine, protecting unrelated native applications.

SteamBridge is not an anti-cheat bypass, DRM bypass, or credential-management tool.
