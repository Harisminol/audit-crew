#!/usr/bin/env node
// Minimal MCP stdio server for AuditCrew: one tool, `run_command`.
// Runs a bash command inside the repo root only, captures stdout/stderr
// and the exit code. No network, no extra dependencies.
import { execFile } from "node:child_process";
import readline from "node:readline";

const ROOT = process.env.AUDIT_CREW_ROOT || process.cwd();
const MAX_OUT = 200_000;

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  const { id, method, params } = msg;

  if (method === "initialize") {
    send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "audit-crew-shell", version: "0.1.0" },
      },
    });
  } else if (method === "notifications/initialized") {
    // No reply needed.
  } else if (method === "tools/list") {
    send({
      jsonrpc: "2.0",
      id,
      result: {
        tools: [
          {
            name: "run_command",
            description:
              "Run a bash command inside the AuditCrew repo. Returns exit code, stdout and stderr. Use it to run forge, cast, anvil, git, and other repo tooling.",
            inputSchema: {
              type: "object",
              properties: {
                command: { type: "string", description: "Bash command to run" },
                cwd: { type: "string", description: "Working directory (must be inside the repo root)" },
                timeout_ms: { type: "number", description: "Kill after this many ms (default 120000)" },
              },
              required: ["command"],
            },
          },
        ],
      },
    });
  } else if (method === "tools/call") {
    const { name, arguments: args } = params || {};
    if (name !== "run_command") {
      send({ jsonrpc: "2.0", id, error: { code: -32602, message: "unknown tool: " + name } });
      return;
    }
    const cwd = args.cwd || ROOT;
    if (!cwd.startsWith(ROOT)) {
      send({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: "cwd outside repo root — refused" }], isError: true },
      });
      return;
    }
    execFile(
      "bash",
      ["-c", args.command],
      { cwd, timeout: args.timeout_ms || 120000, maxBuffer: MAX_OUT },
      (err, stdout, stderr) => {
        const code = err ? (typeof err.code === "number" ? err.code : 1) : 0;
        const out = `exit: ${code}\n--- stdout ---\n${stdout}\n--- stderr ---\n${stderr}`;
        send({
          jsonrpc: "2.0",
          id,
          result: { content: [{ type: "text", text: out.slice(0, MAX_OUT) }] },
        });
      }
    );
  } else if (id !== undefined) {
    send({ jsonrpc: "2.0", id, error: { code: -32601, message: "method not found: " + method } });
  }
});
