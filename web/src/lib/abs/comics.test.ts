import { describe, expect, it } from "vitest";
import { comicPages, pageName } from "./comics";

describe("comicPages", () => {
  it("orders images by the last number in their names, not alphabetically", () => {
    expect(comicPages(["page 10.png", "page 2.png", "page 1.png", "ComicInfo.xml"])).toEqual([
      "page 1.png",
      "page 2.png",
      "page 10.png",
    ]);
  });

  it("uses the last number of the name only, ignoring folders and earlier numbers", () => {
    expect(comicPages(["v2/issue 3 p02.jpg", "v1/issue 3 p01.JPEG", "v9/issue 3 p03.webp"])).toEqual([
      "v1/issue 3 p01.JPEG",
      "v2/issue 3 p02.jpg",
      "v9/issue 3 p03.webp",
    ]);
  });

  it("puts unnumbered images after the numbered ones, in archive order, and skips other files", () => {
    expect(comicPages(["cover.png", "2.png", "notes.txt", "1.gif", "back.jpg", "1.png"])).toEqual([
      "1.png",
      "2.png",
      "cover.png",
      "back.jpg",
    ]);
  });
});

describe("pageName", () => {
  it("keeps short names and shortens long ones in the middle so the page number stays visible", () => {
    expect(pageName("page 1.png")).toBe("page 1.png");
    const long = "Skyline Issue 1 by Rin Okada scanned 2024 page 0012.png";
    expect(pageName(long)).toBe(`${long.slice(0, 18)} ... ${long.slice(-17)}`);
  });
});
