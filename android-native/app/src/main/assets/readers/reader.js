import { MOBI, isMOBI } from './foliate/mobi.js';
import { unzlibSync } from './foliate/vendor/fflate.js';
import { Archive } from './libarchive/libarchive.js';
const area = document.querySelector('#book');
const emit = (type, value = {}) => NativeReader.event(JSON.stringify({type, ...value}));
let book, rendition, archive, pages, frame, section = 0, comicPage = 1, kind, moved = false, ready = false;
let settings = {fontScale:100, theme:'light',font:'serif',lineSpacing:115,textStroke:0,spread:'auto'}, currentUrl;
const BLOCKS = 'p,li,blockquote,h1,h2,h3,h4,h5,h6,pre,td,div';
const blocks = doc => [...doc.body.querySelectorAll(BLOCKS)].filter(x => !x.querySelector(BLOCKS));
const flatToc = (toc, depth = 0) => (toc || []).flatMap(x => [{label: '  '.repeat(depth) + (x.label || x.title || 'Chapter'), href:x.href}, ...flatToc(x.subitems || x.children, depth + 1)]);
const css = () => `html{font-size:${settings.fontScale}% !important;color:${settings.theme==='light'?'#202020':'#eee'} !important;background:${settings.theme==='light'?'#fff':settings.theme==='black'?'#000':'#171717'} !important}body{font-family:${["serif","sans-serif","monospace"].includes(settings.font)?settings.font:"serif"} !important;line-height:${settings.lineSpacing||115}% !important;-webkit-text-stroke:${(settings.textStroke||0)/100}px;max-width:42rem;margin:auto !important;padding:18px !important}h1{font-size:1.8em !important;line-height:1.2 !important}h2{font-size:1.5em !important;line-height:1.2 !important}img,svg{max-width:100%;height:auto}a{color:${settings.theme==='light'?'#224488':'#aaccff'}}`;
function styleDoc(doc) { let style=doc.getElementById('native-reader-style');if(!style){style=doc.createElement('style');style.id='native-reader-style';doc.head.append(style)}style.textContent=css(); }
function notify(location, progress) { emit('place',{location,progress, moved}); }
function mobiPlace() {
 const doc=frame.contentDocument, bs=blocks(doc), sc=doc.scrollingElement;
 const block=Math.max(0,bs.findIndex(b=>b.getBoundingClientRect().bottom>20));
 const sizes=book.sections.map(s=>s.size||0), total=sizes.reduce((a,b)=>a+b,0);
 const fraction=sc.scrollHeight>sc.clientHeight?sc.scrollTop/(sc.scrollHeight-sc.clientHeight):0;
 notify(`mobi:1:${section}:${block}`,total?(sizes.slice(0,section).reduce((a,b)=>a+b,0)+(sizes[section]||0)*fraction)/total:section/book.sections.length);
}
async function showSection(index, spot = 0, anchor) {
 const s=book.sections[index]; if(!s?.load)throw Error('Chapter is not readable');
 section=index; const url=await s.load(); frame.src=url;
 await new Promise((resolve,reject)=>{frame.onload=resolve;frame.onerror=reject});
 const doc=frame.contentDocument;styleDoc(doc);
 const target=anchor?.(doc)||blocks(doc)[spot];if(spot&&!target)emit('unresolved',{location:`mobi:1:${index}:${spot}`});target?.scrollIntoView();
 doc.addEventListener('click',async e=>{const a=e.target.closest('a');if(!a)return;e.preventDefault();const href=a.getAttribute('href');if(book.isExternal(href))return;try{const p=await book.resolveHref(href);moved=true;await showSection(p.index,0,p.anchor)}catch{emit('error',{message:'This link could not be opened.'})}});
 doc.addEventListener('scroll',()=>{if(ready){moved=true;mobiPlace()}}, {passive:true});
 mobiPlace();
}
async function showComic(page) {
 comicPage=Math.max(1,Math.min(pages.length,page));
 const file=await archive.extractSingleFile(pages[comicPage-1]);
 if(currentUrl)URL.revokeObjectURL(currentUrl);currentUrl=URL.createObjectURL(file);
 area.innerHTML='';const img=document.createElement('img');img.id='comic';img.style.cssText='width:100%;height:100%;object-fit:contain';img.alt=`Page ${comicPage}`;img.src=currentUrl;
 await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(Error('Comic page image could not be decoded'));area.append(img)});
 notify(String(comicPage),(comicPage-1)/pages.length);
}
async function open(format, start) {
 kind=format;area.style.cssText='position:fixed;inset:0;overflow:auto;width:'+window.innerWidth+'px;height:'+window.innerHeight+'px';const response=await fetch('document');if(!response.ok)throw Error('Document could not be read');const bytes=await response.arrayBuffer();
 if(format==='epub'){
  book=ePub(bytes);await book.ready;await book.loaded.navigation;
  rendition=book.renderTo(area,{width:window.innerWidth,height:window.innerHeight,flow:'paginated'});
  rendition.hooks.content.register(content=>{styleDoc(content.document)});
  // The local engine forwards content link intent before its own display call.
  rendition.on('linkClicked',()=>{moved=true});
  const epubPlace=loc=>{if(loc?.start?.cfi)notify(loc.start.cfi,book.locations.length()?book.locations.percentageFromCfi(loc.start.cfi):(book.spine.length?loc.start.index/book.spine.length:0))};
  rendition.on('relocated',loc=>{if(ready)epubPlace(loc)});
  book.locations.generate(100).then(()=>{if(ready)epubPlace(rendition.currentLocation())}).catch(()=>{});
  const valid=!start||start.startsWith('epubcfi(');
  try {await rendition.display(valid?start||undefined:undefined)}catch{await rendition.display();emit('unresolved',{location:start})}
  if(!valid)emit('unresolved',{location:start});
  ready=true;emit('ready',{contents:flatToc(book.navigation.toc)});epubPlace(rendition.currentLocation());
 }else if(format==='mobi'||format==='azw3'){
  const file=new File([bytes],'book');if(!await isMOBI(file))throw Error('Not a MOBI or AZW3 document');
  book=await new MOBI({unzlib:unzlibSync}).open(file);
  frame=document.createElement('iframe');frame.setAttribute('sandbox','allow-same-origin');frame.title='Book content';frame.style.cssText='border:0;width:100%;height:100%';area.append(frame);
  let saved=/^mobi:1:(\d+):(\d+)$/.exec(start||'');if(saved&&!book.sections[Number(saved[1])]?.load)saved=null;
  const first=book.sections.findIndex(s=>s.load);
  await showSection(saved?Number(saved[1]):first,saved?Number(saved[2]):0);
  if(start&&!saved)emit('unresolved',{location:start});ready=true;
  emit('ready',{contents:flatToc(book.toc)});
 }else{
  Archive.init({workerUrl:'libarchive/worker-bundle.js'});archive=await Archive.open(new File([bytes],'comic'));
  const files=await archive.getFilesArray();pages=files.filter(x=>x.file?.name).map(x=>x.path+x.file.name).filter(p=>/\.(jpe?g|png|webp|gif)$/i.test(p));
  const number=p=>Number(p.split('/').pop().replace(/\.[^.]*$/,'').match(/\d+/g)?.at(-1)??Infinity);
  pages.sort((a,b)=>number(a)-number(b));if(!pages.length)throw Error('No readable comic pages');
  const valid=!start||(/^\d+$/.test(start)&&Number(start)>=1&&Number(start)<=pages.length);
  await showComic(valid&&start?Number(start):1);if(!valid)emit('unresolved',{location:start});ready=true;
  emit('ready',{contents:pages.map((label,i)=>({label,href:String(i+1)})),pages:pages.length});
 }
}
async function command(action,value){
 if(action==='restore'){try{await command('go',value)}catch{emit('unresolved',{location:value})}return}
 if(action==='open'){settings={...settings,...value.settings};await open(value.format,value.location);return}
 if(!ready)return;
 if(action==='settings'){settings={...settings,...value};value=settings;area.style.background=value.theme==='light'?'white':value.theme==='black'?'black':'#171717';if(rendition){rendition.spread(value.spread||'auto');rendition.getContents().forEach(c=>styleDoc(c.document))};if(frame?.contentDocument)styleDoc(frame.contentDocument);return}
 if(action==='search'){
  const results=[];
  if(rendition){for(const s of book.spine.spineItems){await s.load(book.load.bind(book));for(const hit of s.find(value))results.push({label:hit.excerpt,href:hit.cfi});s.unload()}}
  else if(book?.sections){for(let i=0;i<book.sections.length;i++){if(!book.sections[i].load)continue;const url=await book.sections[i].load();const doc=new DOMParser().parseFromString(await(await fetch(url)).text(),'text/html');blocks(doc).forEach((b,j)=>{if(b.textContent.toLocaleLowerCase().includes(value.toLocaleLowerCase()))results.push({label:b.textContent.slice(0,180),href:`mobi:1:${i}:${j}`})})}}
  emit('results',{contents:results.slice(0,200)});return;
 }
 moved=true;
 if(action==='go'){
  if(rendition)await rendition.display(value);
  else if(pages)await showComic(Number(value));
  else{const p=/^mobi:1:(\d+):(\d+)$/.exec(value);if(p)await showSection(Number(p[1]),Number(p[2]));else{const t=await book.resolveHref(value);await showSection(t.index,0,t.anchor)}}
 }else if(action==='next'||action==='previous'){
  const step=action==='next'?1:-1;
  if(rendition)await (step===1?rendition.next():rendition.prev());
  else if(pages)await showComic(comicPage+step);
  else{const doc=frame.contentDocument,sc=doc.scrollingElement;
   if(step>0?sc.scrollTop+sc.clientHeight<sc.scrollHeight-2:sc.scrollTop>0){sc.scrollTop+=step*(sc.clientHeight-36);mobiPlace()}
   else{let next=section+step;while(next>=0&&next<book.sections.length&&!book.sections[next].load)next+=step;if(next>=0&&next<book.sections.length)await showSection(next)}}
 }
}
window.addEventListener('resize',()=>{area.style.height=window.innerHeight+'px';area.style.width=window.innerWidth+'px';if(rendition)rendition.resize(window.innerWidth,window.innerHeight)});
window.readerCommand=(action,value)=>command(action,value).catch(e=>emit('error',{message:e.message||'Document could not be opened'}));
emit('boot');
