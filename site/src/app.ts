import { translations } from "./i18n";
import type { Language, TranslationKey, TranslationStrings } from "./i18n";

type Provider = { name: string; asset: string };
type Reading = number | null;
type DemoState = "normal" | "low" | "missing";

const providers: readonly Provider[] = [
  { name: "Codex", asset: "codex.svg" },
  { name: "Claude", asset: "claude.svg" },
  { name: "Cursor", asset: "cursor.svg" },
  { name: "Grok", asset: "grokBot.svg" }
];
const samples: Record<DemoState, readonly Reading[]> = {
  normal: [82, 64, 48, 71],
  low: [18, 9, 26, 0],
  missing: [null, null, null, null]
};
const circumference = 2 * Math.PI * 44;
const languageStorageKey = "usage-rings-language";
let currentState: DemoState = "normal";

function element<T extends Element>(selector: string): T {
  const node = document.querySelector<T>(selector);
  if (!node) throw new Error(`Missing page element: ${selector}`);
  return node;
}

function isLanguage(value: string | undefined): value is Language {
  return value === "ja" || value === "en";
}

function isTranslationKey(value: string | undefined): value is TranslationKey {
  return value !== undefined && Object.hasOwn(translations.en, value);
}

function initialLanguage(): Language {
  try {
    const saved = localStorage.getItem(languageStorageKey) ?? undefined;
    if (isLanguage(saved)) return saved;
  } catch {}
  return (navigator.languages?.[0] || navigator.language || "").toLowerCase().startsWith("ja") ? "ja" : "en";
}

let currentLanguage = initialLanguage();
function strings(): TranslationStrings { return translations[currentLanguage]; }

function ring(provider: Provider, value: Reading, showNumber = false): string {
  const missing = value === null;
  const color = missing ? "" : value <= 10 ? "#fb7774" : value <= 20 ? "#edc969" : "";
  const reading = missing ? strings().unavailable : currentLanguage === "ja" ? "残り" + value + "%" : value + " percent remaining";
  return `<div class="ring-unit${missing ? " is-missing" : ""}" role="img" aria-label="${provider.name}: ${reading}"${color ? ` style="--ring-color:${color}"` : ""}><div class="ring-wrap"><svg viewBox="0 0 100 100" aria-hidden="true"><circle class="ring-track" cx="50" cy="50" r="44"/><circle class="ring-value" cx="50" cy="50" r="44" style="stroke-dashoffset:${circumference * (1 - (value ?? 0) / 100)}"/></svg><img src="assets/${provider.asset}" alt="" width="60" height="60">${missing && !showNumber ? '<span class="missing-badge" aria-hidden="true">—</span>' : ""}</div>${showNumber ? `<div class="ring-number" aria-hidden="true">${missing ? "—" : value + "%"}</div>` : ""}</div>`;
}

function renderDemo(state: DemoState = currentState): void {
  currentState = state;
  document.querySelectorAll<HTMLElement>('[data-widget="small"],[data-widget="medium"]').forEach(widget => {
    widget.innerHTML = providers.map((provider, index) => ring(provider, samples[state][index] ?? null, widget.dataset.widget === "medium")).join("");
  });
  element("#preview-status").textContent = state === "missing" ? strings().allUnavailable : strings().samplePrefix + providers.map((provider, index) => provider.name + " " + samples[state][index] + (currentLanguage === "ja" ? "%" : " percent")).join(currentLanguage === "ja" ? "、" : ", ") + (currentLanguage === "ja" ? "。" : ".");
}

function updateControlLabels(): void {
  const light = element("#widget-preview").classList.contains("preview-light");
  element("#appearance").textContent = light ? strings().darkPreview : strings().lightPreview;
}

function applyLanguage(language: string | undefined, persist = false): void {
  if (!isLanguage(language)) return;
  currentLanguage = language;
  if (persist) { try { localStorage.setItem(languageStorageKey, language); } catch {} }
  document.documentElement.lang = language;
  document.querySelectorAll<HTMLElement>("[data-i18n]").forEach(node => {
    const key = node.dataset.i18n;
    if (isTranslationKey(key)) node.innerHTML = strings()[key];
  });
  document.querySelectorAll<HTMLElement>("[data-i18n-aria]").forEach(node => {
    const key = node.dataset.i18nAria;
    if (isTranslationKey(key)) node.setAttribute("aria-label", strings()[key]);
  });
  document.querySelectorAll<HTMLElement>("[data-language]").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.language === language));
  });
  document.querySelectorAll<HTMLAnchorElement>("[data-apple-guidance]").forEach(link => {
    link.href = language === "ja" ? "https://support.apple.com/ja-jp/102445" : "https://support.apple.com/en-us/102445";
  });
  document.title = strings().title;
  const metadata: Record<string, TranslationKey> = {
    'meta[name="description"]': "description",
    'meta[property="og:title"]': "title",
    'meta[property="og:description"]': "ogDescription",
    'meta[property="og:image:alt"]': "ogImageAlt",
    'meta[name="twitter:title"]': "title",
    'meta[name="twitter:description"]': "ogDescription",
    'meta[name="twitter:image:alt"]': "ogImageAlt"
  };
  for (const [selector, key] of Object.entries(metadata)) element(selector).setAttribute("content", strings()[key]);
  renderDemo();
  element('[data-widget="feature"]').innerHTML = providers.map((provider, index) => ring(provider, samples.normal[index] ?? null)).join("");
  const first = providers[0];
  if (first) {
    element('[data-widget="fresh"]').innerHTML = ring(first, 82, true);
    element('[data-widget="expired"]').innerHTML = ring(first, null, true);
  }
  updateControlLabels();
}

document.querySelectorAll<HTMLButtonElement>("[data-language]").forEach(button => {
  button.addEventListener("click", () => applyLanguage(button.dataset.language, true));
});
document.querySelectorAll<HTMLInputElement>('input[name="demo-state"]').forEach(input => {
  input.addEventListener("change", () => {
    if (input.value === "normal" || input.value === "low" || input.value === "missing") renderDemo(input.value);
  });
});
const appearanceButton = element<HTMLButtonElement>("#appearance");
appearanceButton.addEventListener("click", () => {
  const light = element("#widget-preview").classList.toggle("preview-light");
  appearanceButton.setAttribute("aria-pressed", String(light));
  updateControlLabels();
});
applyLanguage(currentLanguage);
