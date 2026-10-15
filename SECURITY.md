# Security

## Reporting

Report vulnerabilities privately through
[GitHub security advisories](https://github.com/mikejhill/hotkit/security/advisories/new),
not public issues. Expect a response within a week; this is maintained by one person.

## Model

- The app runs as the signed-in user with no elevation and makes no network
  calls except the optional Bing wallpaper download.
- `config.json` and plugins are trusted code: actions such as `run` and `send`
  and any plugin execute with your privileges. Only install plugins you have read.
- Keep secrets out of `config.json`; it is plain text.
