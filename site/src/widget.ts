import { translations } from "./i18n";
import type { Language } from "./i18n";

type Period = "5h" | "W";
type Allowance = { period: Period; normal: number; low: number };
type Provider = { name: string; asset: string; allowances: readonly Allowance[] };
export type DemoState = "normal" | "low" | "missing";

export const demoProviders: readonly Provider[] = [
  { name: "Codex", asset: "codex.svg", allowances: [
    { period: "5h", normal: 76, low: 9 }, { period: "W", normal: 64, low: 18 }
  ] },
  { name: "Claude", asset: "claude.svg", allowances: [
    { period: "5h", normal: 82, low: 19 }, { period: "W", normal: 58, low: 12 }
  ] },
  { name: "Grok", asset: "grokBot.svg", allowances: [
    { period: "W", normal: 41, low: 0 }
  ] },
  { name: "Gemini", asset: "gemini.svg", allowances: [
    { period: "5h", normal: 100, low: 26 }, { period: "W", normal: 53, low: 16 }
  ] }
];

const topArc = "M 6.96 40.85 A 44 44 0 0 1 93.04 40.85";

function renderArc(value: number | null, split: boolean): string {
  const shape = split ? `path d="${topArc}"` : 'circle cx="50" cy="50" r="44" transform="rotate(-90 50 50)"';
  const track = `<${shape} class="ring-track"/>`;
  if (value === null || value === 0) return track;
  const tone = value <= 10 ? " is-critical" : value <= 20 ? " is-low" : "";
  return `${track}<${shape} class="ring-value${tone}" pathLength="100" stroke-dasharray="${value} 100"/>`;
}

export function describeDemoRing(provider: Provider, state: DemoState, language: Language): string {
  if (state === "missing") return `${provider.name}: ${translations[language].unavailable}`;
  const readings = provider.allowances.map(({ period, [state]: value }) => {
    if (language === "ja") return `${period === "5h" ? "5時間枠" : "週枠"} 残り${value}%`;
    return `${period === "5h" ? "5-hour allowance" : "weekly allowance"}: ${value}% remaining`;
  });
  return `${provider.name}: ${readings.join(language === "ja" ? "、" : "; ")}`;
}

export function renderDemoRing(
  provider: Provider, state: DemoState, language: Language, showReadout = false
): string {
  const missing = state === "missing";
  const split = provider.allowances.length === 2;
  const arcs = provider.allowances.map((allowance, index) => {
    const arc = renderArc(missing ? null : allowance[state], split);
    return index === 0 ? arc : `<g transform="translate(0 100) scale(1 -1)">${arc}</g>`;
  }).join("");
  const rows = missing ? "" : provider.allowances.map(allowance =>
    `<span class="ring-period">${allowance.period}:</span><span class="ring-percent">${allowance[state]}%</span>`
  ).join("");
  const readout = showReadout ? `<div class="ring-readout" aria-hidden="true">${rows}</div>` : "";

  return `<div class="ring-unit${missing ? " is-missing" : ""}" role="img" aria-label="${describeDemoRing(provider, state, language)}">
    <div class="ring-wrap">
      <svg viewBox="0 0 100 100" aria-hidden="true">${arcs}</svg>
      <img src="assets/${provider.asset}" alt="" width="60" height="60">
    </div>${readout}
  </div>`;
}
