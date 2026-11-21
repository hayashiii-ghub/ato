import { demoProviders, renderDemoRing } from "../src/widget";

const widget = document.querySelector('[data-widget="social"]');
if (widget) {
  widget.innerHTML = demoProviders.map(provider => renderDemoRing(provider, "normal", "en", true)).join("");
}
