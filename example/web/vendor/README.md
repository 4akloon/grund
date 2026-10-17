# Vendored third-party files

## htmx

- File: `htmx.min.js` (`dist/htmx.min.js` of the npm package `htmx.org`).
- Version: 2.0.11 (the 2.x line has `htmx.config.responseHandling`, which the
  example uses to swap `422` responses; htmx 4 is a different line).
- Source: <https://registry.npmjs.org/htmx.org/-/htmx.org-2.0.11.tgz>, checked
  against the registry's `dist.integrity`:
  `sha512-Thx/WtpeOQqSrqBCw/A1cwGJGg4UrVa3+sW0GmrM3p4gJgO89ecH4qtbnyzDDWFvBTqjnIMCgELTNt636dtamA==`.
- License: Zero-Clause BSD, in the `LICENSE` file next to this one.

The file is served unchanged by the example's `/static` route. To update it,
replace both files from a newer 2.x tarball, check its integrity the same way
and edit the version and hash above.
