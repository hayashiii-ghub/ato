import { translations } from "./i18n";
import type { Language, TranslationKey, TranslationStrings } from "./i18n";
import { demoProviders, describeDemoRing, renderDemoRing } from "./widget";
import type { DemoState } from "./widget";

const providers = [...demoProviders];
const demoStates = ["normal", "low", "missing"] as const;
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

function renderDemo(state: DemoState = currentState): void {
  currentState = state;
  document.querySelectorAll<HTMLElement>('[data-widget="small"],[data-widget="medium"]').forEach(widget => {
    widget.innerHTML = providers.map(provider => renderDemoRing(provider, state, currentLanguage, widget.dataset.widget === "medium")).join("");
  });
  element("#preview-status").textContent = state === "missing" ? strings().allUnavailable : strings().samplePrefix
    + providers.map(provider => describeDemoRing(provider, state, currentLanguage)).join(currentLanguage === "ja" ? "。 " : ". ");
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
  renderSelection();
  const first = demoProviders[0];
  if (first) {
    for (const state of demoStates) {
      element(`[data-widget="state-${state}"]`).innerHTML = renderDemoRing(first, state, currentLanguage, true);
    }
  }
  element('[data-widget="install"]').innerHTML = demoProviders.map(provider => renderDemoRing(provider, "normal", currentLanguage)).join("");
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
document.querySelectorAll<HTMLInputElement>('input[name="widget-size"]').forEach(input => {
  input.addEventListener("change", () => {
    if (input.value !== "both" && input.value !== "small" && input.value !== "medium") return;
    element<HTMLElement>("#widget-preview").dataset.size = input.value;
    element<HTMLElement>(".small-example").hidden = input.value === "medium";
    element<HTMLElement>(".medium-example").hidden = input.value === "small";
  });
});
const appearanceButton = element<HTMLButtonElement>("#appearance");
appearanceButton.addEventListener("click", () => {
  const light = element("#widget-preview").classList.toggle("preview-light");
  appearanceButton.setAttribute("aria-pressed", String(light));
  updateControlLabels();
});
function renderSelection(): void {
  element('[data-widget="selection"]').innerHTML = providers.map(provider => renderDemoRing(provider, "normal", currentLanguage, true)).join("");
  document.querySelectorAll<HTMLSelectElement>("[data-service-slot]").forEach((select, index) => {
    select.value = providers[index]?.name ?? "";
    select.setAttribute("aria-label", `${strings().slotLabel} ${index + 1}`);
  });
}
document.querySelectorAll<HTMLSelectElement>("[data-service-slot]").forEach(select => {
  select.addEventListener("change", () => {
    const index = Number(select.dataset.serviceSlot);
    const next = demoProviders.find(provider => provider.name === select.value);
    const previous = providers[index];
    if (!next || !previous) return;
    const other = providers.findIndex(provider => provider.name === next.name);
    if (other >= 0) providers[other] = previous;
    providers[index] = next;
    renderSelection();
    renderDemo();
  });
});
applyLanguage(currentLanguage);
