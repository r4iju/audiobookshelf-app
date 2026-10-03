'use strict';
const BLOCKS = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,figure,img,table,dt,dd';
const blocksOf = doc => [...doc.body.querySelectorAll(BLOCKS)].filter(node => !node.querySelector(BLOCKS));
const viewer = () => document.getElementById('viewer');
let documentReader;
function warning() { report({warning: 'The saved location is not understood by this reader. It is kept until you choose a new passage.'}); }
function sanitise(doc) {
  doc.querySelectorAll('script,iframe,object,embed,form,base,meta[http-equiv]').forEach(node => node.remove());
  doc.querySelectorAll('*').forEach(node => [...node.attributes].forEach(attribute => {
    if (/^on/i.test(attribute.name) || /^\s*(javascript|vbscript):/i.test(attribute.value)) node.removeAttribute(attribute.name);
  }));
}
function colors(p) {
  return {color: p.theme === 'light' ? '#1c1c1e' : '#eee', background: p.theme === 'light' ? '#fff' : p.theme === 'black' ? '#000' : '#232323'};
}
function moved() { report({warning: ''}); }
async function openExpanded(bytes, payload) {
  documentReader?.close(); documentReader = null;
  viewer().replaceChildren();
  documentReader = ['cbz','cbr'].includes(payload.format) ? await ComicDocument.open(bytes, payload) : await MobiDocument.open(bytes, payload);
  report({ready: true});
}
class ComicDocument {
  static async open(bytes, payload) {
    let archive;
    if (payload.format === 'cbr') {
      if (String.fromCharCode(...bytes.slice(0, 4)) !== 'Rar!') throw Error('Not a RAR comic');
      archive = await openRar(bytes);
    } else {
      const zip = await JSZip.loadAsync(bytes);
      archive = {paths: Object.keys(zip.files).filter(path => !zip.files[path].dir), extract: path => zip.file(path).async('uint8array'), close() {}};
    }
    const number = path => { const matches = path.split('/').pop().replace(/\.[^.]*$/, '').match(/\d+/g); return matches ? Number(matches[matches.length - 1]) : Infinity; };
    const paths = archive.paths.filter(path => /\.(png|jpe?g|webp)$/i.test(path) && !path.startsWith('__MACOSX/')).sort((a,b) => number(a) - number(b));
    if (!paths.length || paths.length > 10000) { archive.close(); throw Error('No supported comic pages'); }
    const reading = new ComicDocument(archive, paths, payload.preferences);
    const infoPath = archive.paths.find(path => /(^|\/)ComicInfo\.xml$/i.test(path));
    if (infoPath) {
      try {
        const bytes = await archive.extract(infoPath);
        if (bytes.length < 1024 * 1024) {
          const doc = new DOMParser().parseFromString(new TextDecoder().decode(bytes), 'text/xml');
          if (!doc.querySelector('parsererror')) report({details: [...doc.documentElement.children].flatMap(node => node.children.length || !node.textContent.trim() ? [] : [{title:node.tagName, value:node.textContent.trim()}])});
        }
      } catch (_) { /* Optional publisher metadata does not prevent reading the panels. */ }
    }
    const location = payload.location;
    const page = /^\d+$/.test(location || '') ? Number(location) : 1;
    const valid = !location || /^\d+$/.test(location) && page >= 1 && page <= paths.length;
    if (!valid) warning();
    report({chapters: paths.map((title,index) => ({title, href: String(index + 1)}))});
    try {
      await reading.show(valid ? page - 1 : 0, false);
      return reading;
    } catch (error) { reading.close(); throw error; }
  }
  constructor(archive, paths, p) { this.archive = archive; this.paths = paths; this.p = p; this.index = 0; this.generation = 0; }
  async show(index, save) {
    if (index < 0 || index >= this.paths.length) return;
    const generation = ++this.generation;
    const path = this.paths[index];
    const bytes = await this.archive.extract(path);
    if (generation !== this.generation) return;
    if (!bytes.length || bytes.length > 64 * 1024 * 1024) throw Error('Invalid comic page');
    const type = /\.png$/i.test(path) ? 'image/png' : /\.webp$/i.test(path) ? 'image/webp' : 'image/jpeg';
    const url = URL.createObjectURL(new Blob([bytes], {type}));
    const image = new Image(); image.alt = path;
    image.src = url;
    try { await image.decode(); }
    catch (error) { URL.revokeObjectURL(url); throw Error('The comic page could not be decoded'); }
    if (generation !== this.generation) { URL.revokeObjectURL(url); return; }
    if (this.url) URL.revokeObjectURL(this.url);
    this.url = url; this.index = index; this.image = image;
    viewer().replaceChildren(image); this.preferences(this.p);
    report({page:index + 1, pages:this.paths.length});
    if (save) { moved(); report({location:String(index + 1), fraction: index / this.paths.length}); }
  }
  turn(forward) { return this.show(this.index + (forward ? 1 : -1), true); }
  navigate(target) { return this.show(Number(target) - 1, true); }
  preferences(p) {
    this.p = p; Object.assign(viewer().style, {overflow:'auto', background: colors(p).background, display:'flex', alignItems:p.fit === 'width' ? 'flex-start' : 'center', justifyContent:'center'});
    if (this.image) Object.assign(this.image.style, {width:p.fit === 'width' ? '100%' : 'auto', height:p.fit === 'width' ? 'auto' : '100%', maxWidth:'100%', objectFit:'contain'});
  }
  search() { report({results: []}); }
  close() { ++this.generation; this.archive.close(); if (this.url) URL.revokeObjectURL(this.url); }
}
class MobiDocument {
  static async open(bytes, payload) {
    const book = await openMobi(bytes);
    const sections = book.sections.flatMap((section,index) => section.load ? [index] : []);
    if (!sections.length) { book.destroy?.(); throw Error('No readable MOBI sections'); }
    const reading = new MobiDocument(book, sections, payload.preferences);
    const flatten = items => (items || []).flatMap(item => [{title: item.label, href:item.href}, ...flatten(item.subitems)]);
    report({chapters: flatten(book.toc)});
    const match = payload.location?.match(/^mobi:1:(\d+):(\d+)$/);
    const valid = !payload.location || match && sections.includes(Number(match[1]));
    reading.canSave = !!valid;
    if (!valid) warning();
    try {
      await reading.show(valid && match ? Number(match[1]) : sections[0], {block:valid && match ? Number(match[2]) : 0}, false);
      return reading;
    } catch (error) { reading.close(); throw error; }
  }
  constructor(book, sections, p) { this.book = book; this.sections = sections; this.p = p; this.generation = 0; this.canSave = false; }
  async show(section, spot, save) {
    if (!this.sections.includes(section)) return;
    const generation = ++this.generation;
    const url = await this.book.sections[section].load();
    const response = await fetch(url);
    const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
    sanitise(doc);
    const frame = document.createElement('iframe');
    frame.title = this.book.metadata?.title || 'Book text';
    frame.setAttribute('sandbox', 'allow-same-origin');
    Object.assign(frame.style, {width:'100%', height:'100%', border:'0'});
    const loaded = new Promise((resolve,reject) => {
      const timer = setTimeout(() => reject(Error('The book section did not load')), 15000);
      frame.onload = () => { clearTimeout(timer); resolve(); };
    });
    frame.srcdoc = doc.documentElement.outerHTML;
    if (generation !== this.generation) return;
    viewer().replaceChildren(frame);
    await loaded;
    if (generation !== this.generation) return;
    this.frame = frame; this.doc = frame.contentDocument; this.section = section;
    this.preferences(this.p);
    const blocks = blocksOf(this.doc), scroller = this.doc.scrollingElement;
    let anchor = spot.anchor?.(this.doc);
    if ('block' in spot && spot.block >= blocks.length && spot.block > 0) { this.canSave = false; warning(); }
    if ('block' in spot) anchor = blocks[spot.block];
    scroller.scrollTop = spot.end ? scroller.scrollHeight : anchor ? anchor.getBoundingClientRect().top + scroller.scrollTop - 16 : 0;
    this.doc.addEventListener('click', event => {
      const link = event.target.closest('a');
      if (!link) return;
      event.preventDefault();
      const href = link.getAttribute('href') || link.getAttributeNS('http://www.w3.org/1999/xlink', 'href');
      if (href) this.navigate(href).catch(failed);
    });
    this.doc.addEventListener('scroll', () => {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = setTimeout(() => this.save(), 150);
    });
    // A finger scroll is an explicit new reading place. Layout and restoration are not.
    this.doc.addEventListener('touchmove', () => { this.canSave = true; moved(); }, {passive:true});
    if (save) { this.canSave = true; moved(); this.save(); }
  }
  save() {
    if (!this.canSave || !this.doc) return;
    const blocks = blocksOf(this.doc);
    const block = Math.max(0, blocks.findIndex(node => node.getBoundingClientRect().bottom > 16));
    const sizes = this.sections.map(index => this.book.sections[index].size || 1);
    const index = this.sections.indexOf(this.section), scroller = this.doc.scrollingElement;
    const fraction = (sizes.slice(0,index).reduce((a,b) => a+b,0) + sizes[index] * Math.min(1, (scroller.scrollTop + scroller.clientHeight) / scroller.scrollHeight)) / sizes.reduce((a,b) => a+b,0);
    report({location:`mobi:1:${this.section}:${block}`, fraction});
  }
  async turn(forward) {
    const scroll = this.doc?.scrollingElement;
    if (!scroll) return;
    const step = forward ? 1 : -1;
    this.canSave = true; moved();
    const edge = forward ? scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 2 : scroll.scrollTop <= 0;
    if (edge) {
      const section = this.sections[this.sections.indexOf(this.section) + step];
      if (section !== undefined) await this.show(section, {end:!forward}, true);
    } else { scroll.scrollTop += step * Math.max(1, scroll.clientHeight - 48); this.save(); }
  }
  async navigate(href) {
    const resolved = await this.book.resolveHref(href);
    if (resolved) await this.show(resolved.index, {anchor:resolved.anchor}, true);
  }
  preferences(p) {
    this.p = p;
    if (!this.doc) return;
    const blocks = blocksOf(this.doc), passage = blocks.find(node => node.getBoundingClientRect().bottom > 16);
    const offset = passage?.getBoundingClientRect().top;
    let style = this.doc.getElementById('native-reader-style');
    if (!style) { style = this.doc.createElement('style'); style.id = 'native-reader-style'; this.doc.head.append(style); }
    const color = colors(p);
    style.textContent = `html{font-size:${p.scale}% !important;background:${color.background} !important;color:${color.color} !important}body{font-family:${p.font} !important;line-height:${p.spacing}% !important;background:${color.background} !important;color:${color.color} !important;max-width:42rem;margin:0 auto !important;padding:1rem !important;-webkit-text-stroke:${p.stroke/100}px ${color.color}}img{max-width:100%;height:auto}a{color:inherit}`;
    if (passage && offset !== undefined) this.doc.scrollingElement.scrollTop += passage.getBoundingClientRect().top - offset;
  }
  async search(query) {
    const results = [];
    for (const section of this.sections) {
      const url = await this.book.sections[section].load();
      const doc = new DOMParser().parseFromString(await (await fetch(url)).text(), 'text/html');
      for (const [block,node] of blocksOf(doc).entries()) {
        if (node.textContent.toLowerCase().includes(query.toLowerCase())) results.push({title:node.textContent.trim().slice(0,160), href:`native-search:${section}:${block}`});
        if (results.length >= 100) break;
      }
      if (results.length >= 100) break;
    }
    report({results});
  }
  close() { ++this.generation; clearTimeout(this.scrollTimer); this.book.destroy?.(); }
}
