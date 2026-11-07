// Usage: node render-er.cjs <bundled-node-modules-directory>
// Render local editable DOT sources; no network or database connection.
const fs = require('fs');
const path = require('path');
const packages = process.argv[2];
if (!packages) throw new Error('Pass the bundled node_modules directory as the first argument.');
const { instance } = require(path.join(packages, '@viz-js', 'viz'));
const sharp = require(path.join(packages, 'sharp'));
(async () => {
  const viz = await instance();
  for (const name of fs.readdirSync(__dirname).filter(name => name.endsWith('.dot'))) {
    const svg = viz.renderString(fs.readFileSync(path.join(__dirname, name), 'utf8'), { format: 'svg', engine: 'dot' });
    const out = path.join(__dirname, name.replace(/\.dot$/, '.png'));
    await sharp(Buffer.from(svg), { density: 144 }).png().toFile(out);
    const meta = await sharp(out).metadata();
    console.log(JSON.stringify({ file: path.basename(out), width: meta.width, height: meta.height }));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
