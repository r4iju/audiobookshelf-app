import { MOBI, isMOBI } from './vendor/foliate/mobi.js';
import { unzlibSync } from './vendor/foliate/vendor/fflate.js';
import libarchive from './vendor/libarchive/libarchive.js';
import wasmBinary from './vendor/libarchive/libarchive.wasm';

window.openMobi = async bytes => {
  const file = new File([bytes], 'book.mobi');
  if (!await isMOBI(file)) throw Error('Not a supported MOBI or AZW3 file');
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 86) throw Error('Damaged MOBI record table');
  const record = header.getUint32(78);
  if (record + 14 > bytes.length) throw Error('Damaged MOBI text header');
  if (header.getUint16(record + 12)) throw Error('DRM-protected books are not supported');
  return new MOBI({unzlib: unzlibSync}).open(file);
};
let modulePromise;
window.openRar = async bytes => {
  const module = await (modulePromise ||= libarchive({wasmBinary}));
  const call = (name, result, args) => module.cwrap(name, result, args);
  const open = call('archive_open', 'number', ['number','number','string','string']);
  const close = call('archive_close', null, ['number']);
  const next = call('get_next_entry', 'number', ['number']);
  const size = call('archive_entry_size', 'number', ['number']);
  const path = call('archive_entry_pathname', 'string', ['number']);
  const type = call('archive_entry_filetype', 'number', ['number']);
  const encrypted = call('archive_entry_is_encrypted', 'number', ['number']);
  const data = call('get_filedata', 'number', ['number','number']);
  const skip = call('archive_read_data_skip', 'number', ['number']);
  const error = call('archive_error_string', 'string', ['number']);
  const pointer = module._malloc(bytes.length);
  if (!pointer) throw Error('The comic is too large to open');
  module.HEAPU8.set(bytes, pointer);
  function scan(wanted) {
    const archive = open(pointer, bytes.length, null, 'en_US.UTF-8');
    if (!archive) throw Error('Could not open the RAR archive');
    try {
      const entries = [];
      for (let entry; (entry = next(archive));) {
        const name = path(entry), length = size(entry);
        if (encrypted(entry)) throw Error('Encrypted comics are not supported');
        if (type(entry) === 32768) {
          if (entries.length >= 10000) throw Error('This comic has too many entries');
          entries.push(name);
          if (name === wanted) {
            if (!Number.isSafeInteger(length) || length < 0 || length > 64 * 1024 * 1024) throw Error('The comic page is too large');
            const buffer = data(archive, length);
            if (buffer <= 0) throw Error(error(archive) || 'The comic page could not be extracted');
            try { return module.HEAPU8.slice(buffer, buffer + length); }
            finally { module._free(buffer); }
          }
        }
        if (skip(archive) < 0) throw Error(error(archive) || 'Damaged RAR archive');
      }
      if (wanted) throw Error('The comic page is missing');
      return entries;
    } finally { close(archive); }
  }
  try {
    const paths = scan();
    return {paths, extract: async path => scan(path), close: () => module._free(pointer)};
  } catch (error) { module._free(pointer); throw error; }
};
