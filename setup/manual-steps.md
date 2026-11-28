# Manual steps

Some setup cannot be handled by the scripts in this repository.

## Apps

| Name           | Description                                       | Website                               |
| -------------- | ------------------------------------------------- | ------------------------------------- |
| **Essentials** |                                                   |                                       |
| Ventoy         | An open source tool to create bootable USB drives | [ventoy.net](https://www.ventoy.net/) |

## MCP sign-in

Coding agents reach Context7 through an OAuth MCP server. Sign-in happens once,
in the browser, and each agent stores its credentials outside this repository —
no API key belongs in the configs.

- In opencode, run `opencode mcp auth context7` and approve the browser sign-in.
- In Copilot CLI, reload the CLI and approve its sign-in prompt.

The headless e2e VM verifies that the entries are deployed but cannot complete
interactive OAuth sign-in.
