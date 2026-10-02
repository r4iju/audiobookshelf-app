import { describe, expect, it } from "vitest";
import { feedSlug } from "./feeds";

describe("feedSlug", () => {
  it("makes the address part of a feed the way the legacy client cleans it", () => {
    expect(feedSlug("  The Long Tide  ")).toBe("the-long-tide");
    expect(feedSlug("Señor Café: Part 1.5/2")).toBe("senor-cafe-part-1-5-2");
    expect(feedSlug("a -- b__c")).toBe("a-b__c");
    expect(feedSlug("li_9f3c-2e")).toBe("li_9f3c-2e");
    expect(feedSlug("?!")).toBe("");
  });
});
