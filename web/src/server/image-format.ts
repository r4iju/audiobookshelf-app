import { DomainError } from "./accounts";

export function imageType(bytes: Buffer) {
  let width = 0,
    height = 0,
    type = "";
  if (
    bytes.length >= 33 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    bytes.toString("ascii", 12, 16) === "IHDR"
  ) {
    width = bytes.readUInt32BE(16);
    height = bytes.readUInt32BE(20);
    type = "image/png";
  } else if (bytes[0] === 255 && bytes[1] === 216) {
    let offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] !== 255) break;
      const marker = bytes[offset + 1] ?? 0;
      if (marker === 218 || marker === 217) break;
      const length = bytes.readUInt16BE(offset + 2);
      if (length < 2 || offset + length + 2 > bytes.length) break;
      if ([192, 193, 194].includes(marker) && length >= 8) {
        height = bytes.readUInt16BE(offset + 5);
        width = bytes.readUInt16BE(offset + 7);
        type = "image/jpeg";
        break;
      }
      offset += length + 2;
    }
  }
  if (!width || !height || width > 8192 || height > 8192 || width * height > 20000000)
    throw new DomainError(400, "Use a valid PNG or JPEG cover under 20 million pixels");
  return type;
}
