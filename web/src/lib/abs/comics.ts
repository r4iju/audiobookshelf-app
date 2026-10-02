const imageTypes: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

/** The media type of a page image, which archives do not record. */
export const pageImageType = (path: string) =>
  imageTypes[path.match(/\.([^./]+)$/)?.[1]?.toLowerCase() ?? ""];

const lastNumber = (path: string) => {
  const name = (path.split("/").pop() ?? path).replace(/\.[^.]*$/, "");
  const numbers = name.match(/\d+/g);
  return numbers ? Number(numbers[numbers.length - 1]) : null;
};

/** The archive's images in reading order, as the legacy reader orders them, from paths in archive order. */
export function comicPages(paths: readonly string[]) {
  const images = paths
    .filter((path) => pageImageType(path))
    .map((path) => ({ path, number: lastNumber(path) }));
  return [
    ...images
      .flatMap((image) => (image.number === null ? [] : [{ ...image, number: image.number }]))
      .sort((a, b) => a.number - b.number),
    ...images.filter((image) => image.number === null),
  ].map((image) => image.path);
}

/** Long page names lose their middle, keeping the page number at the end. */
export function pageName(path: string) {
  return path.length > 40 ? `${path.slice(0, 18)} ... ${path.slice(-17)}` : path;
}
