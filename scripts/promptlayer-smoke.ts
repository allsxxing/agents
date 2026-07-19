/**
 * PromptLayer smoke test.
 *
 * Logs a single LLM request to PromptLayer so the onboarding screen flips to
 * "request received". It runs the "Example: page_title" prompt that PromptLayer
 * creates in every workspace at signup.
 *
 * Requires two secrets in the environment (kept out of git in `.dev.vars`):
 *   - PROMPTLAYER_API_KEY : your workspace API key
 *   - OPENAI_API_KEY      : the example prompt runs against gpt-4o
 *
 * Run with:  npm run promptlayer:smoke
 */
// `promptlayer` ships a CJS build that Node's ESM loader can't statically
// analyze for named exports, so import the default and destructure.
import promptlayer from "promptlayer";

const { PromptLayer } = promptlayer;

const apiKey = process.env.PROMPTLAYER_API_KEY;
if (!apiKey) {
  throw new Error(
    "PROMPTLAYER_API_KEY is not set (add it to .dev.vars at the repo root)."
  );
}

const pl = new PromptLayer({ apiKey, throwOnError: true });

const response = await pl.run({
  promptName: "Example: page_title",
  inputVariables: {
    topic: "Travel",
    article:
      "A curated list of 10 awe-inspiring travel destinations every adventurer should visit."
  }
});

const { request_id: requestId } = response as { request_id?: number | null };
if (requestId == null) {
  throw new Error(
    "No request_id returned — check PROMPTLAYER_API_KEY / OPENAI_API_KEY and provider auth."
  );
}

console.log("PromptLayer request_id:", requestId);
