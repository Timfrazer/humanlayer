import { anthropic } from '@ai-sdk/anthropic'
import { createOpenAI, openai } from '@ai-sdk/openai'
import type { LanguageModelV3 } from '@ai-sdk/provider'

/**
 * Self-host addition: route server-side inference through OpenRouter when
 * OPENROUTER_API_KEY is set. Without it, behavior is unchanged (Anthropic
 * primary, optional OpenAI fallback).
 *
 * OpenRouter speaks the OpenAI chat-completions protocol, so the provider keeps
 * the name `openai` and call-site `providerOptions.openai` still applies.
 *
 * Model slugs are overridable so the deployment can pick any OpenRouter model:
 *   OPENROUTER_MODEL_SONNET / OPENROUTER_MODEL_HAIKU            (primary)
 *   OPENROUTER_FALLBACK_MODEL_SONNET / OPENROUTER_FALLBACK_MODEL_HAIKU
 */
export type PrimaryModelAlias = 'sonnet' | 'haiku'

const openRouterApiKey = process.env.OPENROUTER_API_KEY?.trim()

export const isOpenRouterEnabled = Boolean(openRouterApiKey)

const openRouter = isOpenRouterEnabled
	? createOpenAI({
			apiKey: openRouterApiKey,
			baseURL: process.env.OPENROUTER_BASE_URL?.trim() || 'https://openrouter.ai/api/v1',
		})
	: null

const OPENROUTER_PRIMARY_IDS: Record<PrimaryModelAlias, string> = {
	sonnet: process.env.OPENROUTER_MODEL_SONNET?.trim() || 'anthropic/claude-sonnet-4.5',
	haiku: process.env.OPENROUTER_MODEL_HAIKU?.trim() || 'anthropic/claude-haiku-4.5',
}

const OPENROUTER_FALLBACK_IDS: Record<PrimaryModelAlias, string> = {
	sonnet: process.env.OPENROUTER_FALLBACK_MODEL_SONNET?.trim() || 'openai/gpt-5',
	haiku: process.env.OPENROUTER_FALLBACK_MODEL_HAIKU?.trim() || 'openai/gpt-5-mini',
}

const ANTHROPIC_IDS: Record<PrimaryModelAlias, string> = {
	sonnet: 'claude-sonnet-5',
	haiku: 'claude-haiku-4-5',
}

const OPENAI_IDS: Record<PrimaryModelAlias, string> = {
	sonnet: 'gpt-5',
	haiku: 'gpt-5-mini',
}

/** The primary model for an alias: OpenRouter when configured, else Anthropic. */
export function primaryModel(alias: PrimaryModelAlias): LanguageModelV3 {
	if (openRouter) return openRouter.chat(OPENROUTER_PRIMARY_IDS[alias])
	return anthropic(ANTHROPIC_IDS[alias])
}

/** The fallback model for an alias: a second OpenRouter model when configured, else OpenAI. */
export function fallbackModel(alias: PrimaryModelAlias): LanguageModelV3 {
	if (openRouter) return openRouter.chat(OPENROUTER_FALLBACK_IDS[alias])
	return openai(OPENAI_IDS[alias])
}
