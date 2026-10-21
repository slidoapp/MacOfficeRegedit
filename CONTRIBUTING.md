# How to Contribute

Thanks for your interest in contributing to MacOfficeRegedit! Here are a few
general guidelines on contributing and reporting bugs that we ask you to review.
Following these guidelines helps to communicate that you respect the time of the
contributors managing and developing this open source project. In return, they
should reciprocate that respect in addressing your issue, assessing changes, and
helping you finalize your pull requests. In that spirit of mutual respect, we
endeavor to review incoming issues and pull requests within 10 days, and will
close any lingering issues or pull requests after 60 days of inactivity.

Please note that all of your interactions in the project are subject to our
[Code of Conduct](/CODE_OF_CONDUCT.md). This includes creation of issues or pull
requests, commenting on issues or pull requests, and extends to all interactions
in any real-time space e.g., Slack, Discord, etc.

## Reporting Issues

Before reporting a new issue, please ensure that the issue was not already
reported or fixed by searching through our [issues
list](https://github.com/slidoapp/MacOfficeRegedit/issues).

When creating a new issue, please be sure to include a **title and clear
description**, as much relevant information as possible, and, if possible, a
test case. Include the app version, your macOS version and your Microsoft
Office version.

Never attach your Office registry (`MicrosoftRegistrationDB.reg`) or an
unredacted `.reg` export to an issue: it contains account details and other
personal settings. Reproduce the problem with a copy that holds only the keys
and values that matter, or describe them instead.

**If you discover a security bug, please do not report it through GitHub.
Instead, please see security procedures in [SECURITY.md](/SECURITY.md).**

## Sending Pull Requests

Before sending a new pull request, take a look at existing pull requests and
issues to see if the proposed change or fix has been discussed in the past, or
if the change was already implemented but not yet released.

We expect new pull requests to include tests for any affected behavior, and, as
we follow semantic versioning, we may reserve breaking changes until the next
major version release.

See [Development](README.md#development) in the README for how to build the app
and run the tests. Tests must never open the live Office registry: use the
temporary and fixture databases the existing tests create.

## Other Ways to Contribute

We welcome anyone that wants to contribute to MacOfficeRegedit to triage and
reply to open issues to help troubleshoot and fix existing bugs. Here is what
you can do:

- Help ensure that existing issues follows the recommendations from the
  _[Reporting Issues](#reporting-issues)_ section, providing feedback to the
  issue's author on what might be missing.
- Review existing pull requests, and testing patches against the registries of
  different Office versions.
- Write a test, or add a missing test case to an existing test.

Thanks again for your interest on contributing to MacOfficeRegedit!

:heart:
