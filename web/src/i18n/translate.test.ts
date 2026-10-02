import { describe, expect, it } from "vitest";
import { translate } from "./i18n";

describe("translate", () => {
  const strings = { WebItemsCount: "{0} items", WebItemsCount_one: "{0} item" };

  it("uses the singular form when the count calls for it", () => {
    const t = translate(strings, "en-US");
    expect(t("WebItemsCount", 1)).toBe("1 item");
    expect(t("WebItemsCount", 0)).toBe("0 items");
    expect(t("WebItemsCount", 2)).toBe("2 items");
  });

  it("formats numbers for the locale", () => {
    expect(translate(strings, "de-DE")("WebItemsCount", 12345)).toBe("12.345 items");
  });
});
