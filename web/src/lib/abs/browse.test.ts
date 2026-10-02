import { describe, expect, it } from "vitest";
import { browseFromParams, browseToParams, decodeFilter, encodeFilter, itemsQuery } from "./browse";

describe("library filters", () => {
  it("encodes values the way the server decodes them, including non-Latin text", () => {
    expect(encodeFilter("series", "Harbor Lights")).toBe("series.SGFyYm9yIExpZ2h0cw%3D%3D");
    expect(decodeFilter(encodeFilter("authors", "Ōe Kenzaburō"))).toEqual({
      group: "authors",
      value: "Ōe Kenzaburō",
    });
  });

  it("encodes progress filters too and rejects malformed ones", () => {
    expect(encodeFilter("progress", "in-progress")).toBe("progress.aW4tcHJvZ3Jlc3M%3D");
    expect(decodeFilter("not-a-filter")).toBeNull();
  });
});

describe("browse state in the address", () => {
  it("round-trips sort, direction, filter and a 1-based page", () => {
    const state = {
      sort: "media.metadata.title",
      desc: true,
      filter: encodeFilter("series", "Harbor Lights"),
      page: 2,
    };
    expect(browseFromParams(new URLSearchParams(browseToParams(state)))).toEqual(state);
  });

  it("falls back to added-at newest first and page 1 for missing or invalid values", () => {
    expect(browseFromParams(new URLSearchParams("page=-3&sort=evil"))).toEqual({
      sort: "addedAt",
      desc: true,
      filter: null,
      page: 1,
    });
  });

  it("defaults date sorts to newest first and text sorts to A to Z", () => {
    expect(browseFromParams(new URLSearchParams("sort=mtimeMs")).desc).toBe(true);
    expect(browseFromParams(new URLSearchParams("sort=media.metadata.title")).desc).toBe(false);
    expect(browseToParams({ sort: "mtimeMs", desc: true, filter: null, page: 1 })).toBe("sort=mtimeMs");
    expect(browseToParams({ sort: "media.metadata.title", desc: true, filter: null, page: 1 })).toBe(
      "sort=media.metadata.title&desc=1",
    );
  });

  it("builds the server items query with a 0-based page, collapsing series with or without a filter as the legacy bookshelf does", () => {
    const query = new URLSearchParams(
      itemsQuery(
        { sort: "media.metadata.title", desc: false, filter: null, page: 3 },
        { limit: 24, collapseSeries: true },
      ),
    );
    expect(Object.fromEntries(query)).toEqual({
      sort: "media.metadata.title",
      desc: "0",
      limit: "24",
      page: "2",
      minified: "1",
      include: "rssfeed,numEpisodesIncomplete",
      collapseseries: "1",
    });
    const filtered = new URLSearchParams(
      itemsQuery(
        { sort: "addedAt", desc: true, filter: "series.abc", page: 1 },
        { limit: 24, collapseSeries: true },
      ),
    );
    expect(filtered.get("collapseseries")).toBe("1");
    expect(filtered.get("filter")).toBe("series.abc");
  });
});
