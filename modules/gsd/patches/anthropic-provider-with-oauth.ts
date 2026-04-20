// Lazy-loaded: Anthropic SDK (~500ms) is imported on first use, not at startup.
// This avoids penalizing users who don't use Anthropic models.
import type Anthropic from "@anthropic-ai/sdk";
import { getEnvApiKey } from "../env-api-keys.js";
import type {
	Context,
	Model,
	SimpleStreamOptions,
	StreamFunction,
} from "../types.js";
import { AssistantMessageEventStream } from "../utils/event-stream.js";

import { buildCopilotDynamicHeaders, hasCopilotVisionInput } from "./github-copilot-headers.js";
import { adjustMaxTokensForThinking, buildBaseOptions } from "./simple-options.js";
import {
	type AnthropicEffort,
	type AnthropicOptions,
	extractRetryAfterMs,
	mapThinkingLevelToEffort,
	processAnthropicStream,
	supportsAdaptiveThinking,
} from "./anthropic-shared.js";

// Re-export types used by other modules
export type { AnthropicEffort, AnthropicOptions };
export { extractRetryAfterMs };

/**
 * Resolve the base URL for Anthropic API requests.
 *
 * Resolution order:
 * 1. ANTHROPIC_BASE_URL environment variable (if set and non-empty after trim)
 * 2. model.baseUrl (from the model definition)
 *
 * This allows routing traffic through custom proxy endpoints (e.g. OpusMax,
 * local mirrors, corporate gateways) without modifying model definitions.
 */
export function resolveAnthropicBaseUrl(model: Model<"anthropic-messages">): string {
	const envBaseUrl = process.env.ANTHROPIC_BASE_URL?.trim();
	if (envBaseUrl) {
		return envBaseUrl;
	}
	return model.baseUrl;
}

let _AnthropicClass: typeof Anthropic | undefined;
async function getAnthropicClass(): Promise<typeof Anthropic> {
	if (!_AnthropicClass) {
		const mod = await import("@anthropic-ai/sdk");
		_AnthropicClass = mod.default;
	}
	return _AnthropicClass;
}

function mergeHeaders(...headerSources: (Record<string, string> | undefined)[]): Record<string, string> {
	const merged: Record<string, string> = {};
	for (const headers of headerSources) {
		if (headers) {
			Object.assign(merged, headers);
		}
	}
	return merged;
}

export function usesAnthropicBearerAuth(provider: Model<"anthropic-messages">["provider"]): boolean {
	return provider === "alibaba-coding-plan" || provider === "minimax" || provider === "minimax-cn";
}

function hasBearerAuthorizationHeader(model: Model<"anthropic-messages">): boolean {
	const authHeader = model.headers?.Authorization ?? model.headers?.authorization;
	return typeof authHeader === "string" && authHeader.trim().toLowerCase().startsWith("bearer ");
}

// [8sync-patch] Detect Claude Pro/Max OAuth access tokens. Upstream removed
// OAuth support in c2acb1fb4 (TOS compliance), but tokens issued before that
// still work if sent via Authorization: Bearer + oauth-2025-04-20 beta header.
// Format: sk-ant-oat01-... (length ~108).
function isAnthropicOAuthAccessToken(key: string | undefined | null): boolean {
	if (typeof key !== "string") return false;
	return key.startsWith("sk-ant-oat");
}

async function createClient(
	model: Model<"anthropic-messages">,
	apiKey: string,
	interleavedThinking: boolean,
	optionsHeaders?: Record<string, string>,
	dynamicHeaders?: Record<string, string>,
): Promise<{ client: Anthropic; isOAuthToken: boolean }> {
	const AnthropicClass = await getAnthropicClass();
	// Adaptive thinking models (Opus 4.6, Sonnet 4.6) have interleaved thinking built-in.
	// The beta header is deprecated on Opus 4.6 and redundant on Sonnet 4.6, so skip it.
	const needsInterleavedBeta = interleavedThinking && !supportsAdaptiveThinking(model.id);

	// Copilot: Bearer auth, selective betas (no fine-grained-tool-streaming)
	if (model.provider === "github-copilot") {
		const betaFeatures: string[] = [];
		if (needsInterleavedBeta) {
			betaFeatures.push("interleaved-thinking-2025-05-14");
		}

		const client = new AnthropicClass({
			apiKey: null,
			authToken: apiKey,
			baseURL: resolveAnthropicBaseUrl(model),
			dangerouslyAllowBrowser: true,
			defaultHeaders: mergeHeaders(
				{
					accept: "application/json",
					"anthropic-dangerous-direct-browser-access": "true",
					...(betaFeatures.length > 0 ? { "anthropic-beta": betaFeatures.join(",") } : {}),
				},
				model.headers,
				dynamicHeaders,
				optionsHeaders,
			),
		});

		return { client, isOAuthToken: false };
	}

	// Skip beta headers for providers that don't support them (e.g., Alibaba Coding Plan)
	const skipBetaHeaders = model.provider === "alibaba-coding-plan";
	const betaFeatures = skipBetaHeaders ? [] : ["fine-grained-tool-streaming-2025-05-14"];
	if (needsInterleavedBeta && !skipBetaHeaders) {
		betaFeatures.push("interleaved-thinking-2025-05-14");
	}

	// [8sync-patch] Detect Anthropic OAuth access tokens (sk-ant-oat01-...)
	// and route them via Bearer auth with the oauth-2025-04-20 beta header.
	// Upstream removed this path in c2acb1fb4 for TOS compliance; restored for
	// personal use on pre-existing Claude Pro/Max OAuth credentials.
	const isAnthropicOAuth =
		model.provider === "anthropic" && isAnthropicOAuthAccessToken(apiKey);

	// API key auth (or Bearer auth for Anthropic-compatible providers / OAuth tokens).
	const usesBearerAuth =
		isAnthropicOAuth ||
		usesAnthropicBearerAuth(model.provider) ||
		hasBearerAuthorizationHeader(model);

	// OAuth tokens need the oauth-2025-04-20 beta header; add it on top of
	// whatever beta features the caller already requested.
	const oauthBetas = isAnthropicOAuth ? ["oauth-2025-04-20"] : [];
	const finalBetas = [...betaFeatures, ...oauthBetas];

	const client = new AnthropicClass({
		apiKey: usesBearerAuth ? null : apiKey,
		authToken: usesBearerAuth ? apiKey : undefined,
		baseURL: model.baseUrl,
		dangerouslyAllowBrowser: true,
		defaultHeaders: mergeHeaders(
			{
				accept: "application/json",
				"anthropic-dangerous-direct-browser-access": "true",
				...(finalBetas.length > 0 ? { "anthropic-beta": finalBetas.join(",") } : {}),
			},
			model.headers,
			optionsHeaders,
		),
	});

	return { client, isOAuthToken: isAnthropicOAuth };
}

export const streamAnthropic: StreamFunction<"anthropic-messages", AnthropicOptions> = (
	model: Model<"anthropic-messages">,
	context: Context,
	options?: AnthropicOptions,
): AssistantMessageEventStream => {
	const stream = new AssistantMessageEventStream();

	(async () => {
		const apiKey = options?.apiKey ?? getEnvApiKey(model.provider) ?? "";

		let copilotDynamicHeaders: Record<string, string> | undefined;
		if (model.provider === "github-copilot") {
			const hasImages = hasCopilotVisionInput(context.messages);
			copilotDynamicHeaders = buildCopilotDynamicHeaders({
				messages: context.messages,
				hasImages,
			});
		}

		const { client, isOAuthToken: isOAuth } = await createClient(
			model,
			apiKey,
			options?.interleavedThinking ?? true,
			options?.headers,
			copilotDynamicHeaders,
		);

		processAnthropicStream(stream, {
			client,
			model,
			context,
			isOAuthToken: isOAuth,
			options,
			AnthropicSdkClass: _AnthropicClass,
		});
	})();

	return stream;
};

export const streamSimpleAnthropic: StreamFunction<"anthropic-messages", SimpleStreamOptions> = (
	model: Model<"anthropic-messages">,
	context: Context,
	options?: SimpleStreamOptions,
): AssistantMessageEventStream => {
	const apiKey = options?.apiKey || getEnvApiKey(model.provider);
	if (!apiKey) {
		throw new Error(`No API key for provider: ${model.provider}`);
	}

	const base = buildBaseOptions(model, options, apiKey);
	if (!options?.reasoning) {
		return streamAnthropic(model, context, { ...base, thinkingEnabled: false } satisfies AnthropicOptions);
	}

	// For Opus 4.6 and Sonnet 4.6: use adaptive thinking with effort level
	// For older models: use budget-based thinking
	if (supportsAdaptiveThinking(model.id)) {
		const effort = mapThinkingLevelToEffort(options.reasoning, model.id);
		return streamAnthropic(model, context, {
			...base,
			thinkingEnabled: true,
			effort,
		} satisfies AnthropicOptions);
	}

	const adjusted = adjustMaxTokensForThinking(
		base.maxTokens || 0,
		model.maxTokens,
		options.reasoning,
		options.thinkingBudgets,
	);

	return streamAnthropic(model, context, {
		...base,
		maxTokens: adjusted.maxTokens,
		thinkingEnabled: true,
		thinkingBudgetTokens: adjusted.thinkingBudget,
	} satisfies AnthropicOptions);
};
