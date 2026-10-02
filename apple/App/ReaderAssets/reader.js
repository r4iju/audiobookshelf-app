'use strict';
let book, rendition;
function report(value) { window.webkit.messageHandlers.reader.postMessage(value); }
function failed(error) { report({error: String(error.message || error)}); }
async function openBook(payload) {
  try {
    if (book) book.destroy();
    const bytes = Uint8Array.from(atob(payload.data), c => c.charCodeAt(0));
    book = ePub(bytes.buffer, {openAs: 'binary'});
    book.on('openFailed', failed);
    book.spine.hooks.content.register(document => {
      document.querySelectorAll('script,iframe,object,embed,form').forEach(element => element.remove());
      document.querySelectorAll('*').forEach(element => [...element.attributes].forEach(attribute => {
        if (/^on/i.test(attribute.name) || /^javascript:/i.test(attribute.value.trim())) element.removeAttribute(attribute.name);
      }));
    });
    rendition = book.renderTo('viewer', {width: '100%', height: '100%', flow: 'paginated', spread: payload.preferences.spread, allowScriptedContent: false});
    rendition.on('displayError', failed);
    rendition.on('relocated', location => report({location: location.start.cfi, fraction: Math.max(0, Math.min(1, location.start.percentage || 0))}));
    await book.ready;
    const navigation = await book.loaded.navigation;
    const flatten = items => items.flatMap(item => [{title:item.label.trim(), href:item.href}, ...flatten(item.subitems || [])]);
    report({chapters: flatten(navigation.toc)});
    preferences(payload.preferences);
    await rendition.display(payload.location || undefined);
    report({ready: true});
    let cached = false;
    if (payload.cache) {
      try {
        const locations = JSON.parse(payload.cache);
        if (Array.isArray(locations) && locations.length && locations.every((value, index) => {
          if (typeof value !== 'string') return false;
          const parsed = new ePub.CFI(value);
          return parsed.base.steps.length > 0 && parsed.path.steps.length > 0 &&
            (!index || parsed.compare(locations[index - 1], value) <= 0);
        })) {
          book.locations.load(payload.cache); cached = true;
        }
      } catch (_) { /* Derived locations are rebuilt if a cache was evicted or damaged. */ }
    }
    if (!cached) await book.locations.generate(1000);
    report({cache: book.locations.save()});
    const current = rendition.currentLocation();
    if (current && current.start) {
      let fraction;
      try { fraction = book.locations.percentageFromCfi(current.start.cfi) || 0; }
      catch (error) {
        if (!cached) throw error;
        book.locations.load('[]');
        await book.locations.generate(1000);
        report({cache: book.locations.save()});
        fraction = book.locations.percentageFromCfi(current.start.cfi) || 0;
      }
      report({location: current.start.cfi, fraction});
    }
  } catch (error) { failed(error); }
}
function preferences(p) {
  if (!rendition) return;
  const dark = p.theme !== 'light', color = dark ? '#eee' : '#1c1c1e';
  rendition.themes.default({'body': {color, background: p.theme === 'black' ? '#000' : dark ? '#232323' : '#fff', 'line-height': p.spacing + '% !important', '-webkit-text-stroke': (p.stroke / 100) + 'px ' + color}, 'a':{color}});
  rendition.themes.font(p.font); rendition.themes.fontSize(p.scale + '%'); rendition.spread(p.spread);
}
function navigate(target) { if (rendition) rendition.display(target).catch(failed); }
function turn(forward) { if (rendition) (forward ? rendition.next() : rendition.prev()).catch(failed); }
window.addEventListener('load', () => report({shellReady:true}));
