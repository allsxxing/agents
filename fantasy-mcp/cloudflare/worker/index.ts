/**
 * nfl-mcp edge auth worker.
 *
 * Fronts the nfl_mcp container with a bearer-token check so the MCP endpoint
 * is not open to the world. Every request is authenticated, including /health —
 * an unauthenticated probe must get 401, never 200.
 *
 * Shape verified against @cloudflare/containers 0.2.4 + current Containers docs:
 *   - the container is a Durable Object class extending `Container`
 *     (@cloudflare/containers), bound via [[durable_objects.bindings]]
 *   - a [[migrations]] entry with new_sqlite_classes is required to introduce it
 *   - runtime env for the *container process* must be set via the `envVars`
 *     property on the class; plain Worker vars do NOT reach the container.
 *
 * `envVars` is a getter so the base Container constructor stays untouched — the
 * base's `ctx: DurableObject['ctx']` (types from `cloudflare:workers`) can't be
 * reproduced with `@cloudflare/workers-types` alone. The getter reads `this.env`,
 * which the base sets before the container starts.
 */
import { Container, getContainer } from "@cloudflare/containers";

export interface Env {
  /** Bearer token clients must present. `wrangler secret put MCP_TOKEN`. */
  MCP_TOKEN: string;
  /** Comma-separated tool names to unregister. See fantasy-mcp/README.md. */
  NFL_MCP_DISABLED_TOOLS?: string;
  /** "1" enables advanced Sleeper enrichment. */
  NFL_MCP_ADVANCED_ENRICH?: string;
  /** Optional; without it the Vegas tools return neutral placeholders. */
  ODDS_API_KEY?: string;
  NFL_MCP: DurableObjectNamespace<NflMcpContainer>;
}

export class NflMcpContainer extends Container<Env> {
  /** nfl_mcp's uvicorn listener — see the repo Dockerfile (EXPOSE 9000). */
  defaultPort = 9000;

  /**
   * Scale-to-zero idle timeout. Keep this comfortably above draft-room question
   * cadence so back-to-back questions don't each eat a cold start.
   */
  sleepAfter = "20m";

  /**
   * Container-process environment, populated in the constructor from the
   * Worker's env. This is the ONLY path by which these reach the Python
   * process — Worker vars/secrets alone do not flow to the container.
   *
   * NFL_MCP_PREFETCH is intentionally omitted: its 900s background timer
   * fights scale-to-zero (it keeps the instance awake and bills for it).
   */
  envVars: Record<string, string> = {};

  // `ctx` is typed with `any` because the Container base declares it as
  // `DurableObject['ctx']` from `cloudflare:workers`, which is a different
  // TypeScript identity than `DurableObjectState` from `@cloudflare/workers-types`.
  // Reproducing the exact base type here requires generating `worker-configuration.d.ts`
  // via `wrangler types` first. The `any` is local to this constructor arg only.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  constructor(ctx: any, env: Env) {
    super(ctx, env);
    this.envVars = {
      NFL_MCP_DISABLED_TOOLS: env.NFL_MCP_DISABLED_TOOLS ?? "",
      NFL_MCP_ADVANCED_ENRICH: env.NFL_MCP_ADVANCED_ENRICH ?? "1",
      ...(env.ODDS_API_KEY ? { ODDS_API_KEY: env.ODDS_API_KEY } : {}),
    };
  }

  override onError(error: unknown) {
    console.error("nfl-mcp container error:", error);
  }
}

/**
 * Constant-time-ish comparison. Not a hardened primitive, but it avoids the
 * trivially-observable early exit of `===` on a secret-length string.
 */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function unauthorized(): Response {
  return new Response("Unauthorized", {
    status: 401,
    headers: { "WWW-Authenticate": "Bearer" },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Fail closed: a missing/blank secret must never mean "allow everyone".
    if (!env.MCP_TOKEN) {
      console.error("MCP_TOKEN is not configured; refusing all requests");
      return new Response("Server misconfigured", { status: 500 });
    }

    const auth = request.headers.get("Authorization") ?? "";
    const expected = `Bearer ${env.MCP_TOKEN}`;
    if (!safeEqual(auth, expected)) return unauthorized();

    // Single shared instance: one league-analytics backend, max_instances = 1.
    return getContainer(env.NFL_MCP, "nfl-mcp").fetch(request);
  },
};
