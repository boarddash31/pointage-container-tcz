// Reproducible vector masters and raster app icons. Run with Node + sharp.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'app/assets/brand');
fs.mkdirSync(out, { recursive: true });
const navy = '#103c63', cyan = '#1398cf';
const mark = (primary) => `
  <path fill="${primary}" d="M18 43h143v17H18ZM68 20h18v110H68ZM68 60h17l-34 70H31Z"/>
  <path fill="${cyan}" d="M86 20 161 43h-47L86 35Z"/>
  <path fill="${primary}" d="M138 60h3v27h-3Z"/>
  <path fill="${cyan}" d="M111 87h50v30h-50Z"/>
  <path stroke="${primary}" stroke-width="2" opacity=".4" d="M121 91v22m10-22v22m10-22v22m10-22v22"/>
  <path fill="${primary}" d="M18 130h143v12H18Z"/>
  <path fill="${cyan}" d="M18 155q24-13 48 0t48 0t47 0v10q-23-13-47 0t-48 0t-48 0Z"/>`;
const letters = (fill) => `<g fill="${fill}">
  <path d="M209 49h102v23h-37v76h-28V72h-37Z"/>
  <path d="M418 65 400 84q-13-17-29-12-17 5-17 27t18 27q17 4 29-13l19 17q-18 23-47 21-48-2-48-52t48-52q27-2 45 18Z"/>
  <path d="M437 49h105v20l-67 55h68v24H433v-20l67-55h-63Z"/>
</g>`;
const svg = (light = false) => `<svg xmlns="http://www.w3.org/2000/svg" width="630" height="180" viewBox="0 0 630 180">
${mark(light ? '#ffffff' : navy)}${letters(light ? '#ffffff' : navy)}
<path stroke="${cyan}" stroke-width="5" d="M210 164h333"/>
</svg>`;
const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<rect width="512" height="512" rx="108" fill="${navy}"/>
<g transform="translate(126 52) scale(1.45)">${mark('#ffffff')}</g>
<g transform="translate(-94 276) scale(.94)">${letters('#ffffff')}</g>
</svg>`;
async function main() {
  for (const [name, source] of [['tcz-logo', svg()], ['tcz-logo-light', svg(true)], ['tcz-icon', icon]]) {
    fs.writeFileSync(path.join(out, `${name}.svg`), source);
    await sharp(Buffer.from(source)).resize(name === 'tcz-icon' ? 1024 : 1260).png().toFile(path.join(out, `${name}.png`));
  }
  fs.mkdirSync(path.join(root,'app/web/brand'),{recursive:true});
  fs.writeFileSync(path.join(root,'app/web/brand/tcz-logo.svg'),svg());
  const targets = [
    ['app/web/favicon.png', 48],
    ...[192, 512].flatMap(n => [[`app/web/icons/Icon-${n}.png`, n], [`app/web/icons/Icon-maskable-${n}.png`, n]]),
    ...Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})
      .map(([density,n]) => [`app/android/app/src/main/res/mipmap-${density}/ic_launcher.png`, n]),
  ];
  const iosDirectory = 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  const iosCatalog = JSON.parse(fs.readFileSync(path.join(root, iosDirectory, 'Contents.json')));
  for (const entry of iosCatalog.images) {
    if (entry.filename) targets.push([`${iosDirectory}/${entry.filename}`,
      Math.round(parseFloat(entry.size) * parseFloat(entry.scale))]);
  }
  for (const [file, size] of targets) {
    if (file.includes('maskable')) {
      const inner = await sharp(Buffer.from(icon)).resize(Math.round(size * .8)).png().toBuffer();
      await sharp({create:{width:size,height:size,channels:4,background:navy}})
        .composite([{input:inner,gravity:'centre'}]).png().toFile(path.join(root,file));
    } else {
      await sharp(Buffer.from(icon)).resize(size, size).flatten({background:navy})
        .png().toFile(path.join(root, file));
    }
  }
  console.log(`Generated TCZ vector masters and ${targets.length} launcher/web icons.`);
}
main().catch(e => { console.error(e); process.exit(1); });
