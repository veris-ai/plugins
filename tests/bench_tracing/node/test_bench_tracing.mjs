// bench_tracing.mjs sends a bench turn's model calls to Veris, and nothing else.
//
// Each case runs an unchanged copy of the module in a fresh process against a local
// listener, and checks the raw request bodies and headers it received. Run from this
// folder: `npm ci && npm test`.
import { spawn } from "node:child_process";
import { copyFileSync } from "node:fs";
import { createServer } from "node:http";

const here = new URL(".", import.meta.url).pathname;
copyFileSync(new URL("../../../bench/skills/add-your-hosted-agent/reference/bench_tracing.mjs", import.meta.url), `${here}_bench_tracing.mjs`);
const TRACE = Buffer.from("4bf92f3577b34da6a3ce929d0e0e4736", "hex");

let received = [];
let status = 200;
const server = createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    received.push({ headers: req.headers, body: Buffer.concat(chunks) });
    res.writeHead(status).end();
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/v1/traces`;

async function run(name, env = {}) {
  received = [];
  // Async, not spawnSync: a blocked event loop would stop this process's listener.
  const proc = await new Promise((resolve) => {
    const child = spawn(process.execPath, ["cases.mjs", name], {
      cwd: here,
      env: { ...process.env, BENCH_TRACE_KEY: "bench-key-XYZ", BENCH_TRACE_URL: url, ...env },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
  return { got: received, body: Buffer.concat(received.map((r) => r.body)), proc };
}

const results = [];
function check(name, ok, detail = "") {
  console.log(`${ok ? "ok  " : "FAIL"}  ${name}${ok ? "" : `: ${detail}`}`);
  results.push(ok);
}

let r = await run("bench", {
  OTEL_EXPORTER_OTLP_HEADERS: "x-honeycomb-team=CANARY-VENDOR-KEY",
  OTEL_EXPORTER_OTLP_TRACES_HEADERS: "dd-api-key=CANARY-VENDOR-KEY",
  OTEL_RESOURCE_ATTRIBUTES: "k8s.cluster.name=CANARY-RESOURCE",
  OTEL_SERVICE_NAME: "CANARY-SERVICE",
});
const headerNames = new Set(r.got.flatMap((g) => Object.keys(g.headers)));
check("a bench turn's model call is sent, in the bench trace", r.body.includes("CANARY-BENCH") && r.body.includes(TRACE), r.proc.stderr.slice(-500));
check("the turn span is sent", r.body.includes("bench.turn"));
check("only the bench key authorizes the export", r.got.length > 0 && r.got.every((g) => g.headers.authorization === "Bearer bench-key-XYZ"));
check("no OTEL_* header reaches Veris", !headerNames.has("x-honeycomb-team") && !headerNames.has("dd-api-key"), [...headerNames].join(","));
check("no OTEL_* resource attribute reaches Veris", !r.body.includes("CANARY-RESOURCE") && !r.body.includes("CANARY-SERVICE"));

r = await run("notBench");
check("a request without X-Veris-Traceparent sends nothing", !r.body.includes("CANARY-NO-HEADER"), r.proc.stderr.slice(-500));
check("fromBench false sends nothing", !r.body.includes("CANARY-NOT-FROM-BENCH"));
check("a model call outside any turn sends nothing", !r.body.includes("CANARY-OUTSIDE"));

r = await run("existing");
check("a request carrying only a live traceparent sends nothing", !r.body.includes("CANARY-TRACEPARENT-ONLY"), r.proc.stderr.slice(-500));
check("with the agent's provider, a bench model call is sent", r.body.includes("CANARY-BENCH"));
check("with the agent's provider, other spans in the turn are not sent", !r.body.includes("CANARY-DB"));
check("the agent's own exporter still gets every span", r.proc.stdout.includes("own spans 5"), r.proc.stdout);

r = await run("lazyWorker");
check("work that outlives the turn sends nothing", !r.body.includes("CANARY-LATER-USER") && r.body.includes("CANARY-BENCH"), r.proc.stderr.slice(-500));

r = await run("exception");
check("an exception's text is not sent", !r.body.includes("CANARY-PASSWORD") && r.body.includes("CANARY-BENCH"), r.proc.stderr.slice(-500));

for (const bad of ["http://bench.api.veris.ai/v1/traces", "https://collector.example.com/v1/traces", "https://veris.ai.example.com/v1/traces"]) {
  r = await run("badUrl", { BENCH_TRACE_URL: bad });
  check(`refuses BENCH_TRACE_URL ${bad}`, r.proc.code !== 0 && r.proc.stderr.includes("BENCH_TRACE_URL must be"), r.proc.stderr.slice(-300));
}

status = 503;
r = await run("refused");
status = 200;
check("a refused export doesn't crash the agent, nor log the key", r.proc.code === 0 && r.proc.stdout.includes("done") && !r.proc.stderr.includes("bench-key-XYZ"), r.proc.stderr.slice(-300));

r = await run("refused", { BENCH_TRACE_URL: "http://127.0.0.1:9/v1/traces" });
check("an unreachable Veris doesn't crash the agent", r.proc.code === 0 && r.proc.stdout.includes("done"), r.proc.stderr.slice(-300));

r = await run("noKey", { BENCH_TRACE_KEY: "" });
check("without BENCH_TRACE_KEY nothing is configured", r.proc.stdout.includes("configured false"), r.proc.stdout + r.proc.stderr.slice(-300));

server.close();
const failed = results.filter((ok) => !ok).length;
console.log(JSON.stringify({ passed: results.length - failed, failed }));
process.exit(failed ? 1 : 0);
