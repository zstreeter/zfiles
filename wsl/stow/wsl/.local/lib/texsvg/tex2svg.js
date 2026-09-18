const { mathjax } = require('mathjax-full/js/mathjax.js');
const { TeX } = require('mathjax-full/js/input/tex.js');
const { SVG } = require('mathjax-full/js/output/svg.js');
const { liteAdaptor } = require('mathjax-full/js/adaptors/liteAdaptor.js');
const { RegisterHTMLHandler } = require('mathjax-full/js/handlers/html.js');
const { AllPackages } = require('mathjax-full/js/input/tex/AllPackages.js');

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);

const argv = process.argv.slice(2);
const inline = argv.includes('--inline');
const tex = argv.filter((a) => a !== '--inline')[0];
if (!tex) {
  console.error('usage: node tex2svg.js <latex> [--inline]');
  process.exit(2);
}

const doc = mathjax.document('', {
  InputJax: new TeX({ packages: AllPackages }),
  OutputJax: new SVG({ fontCache: 'local' }), // 'local' => self-contained SVG
});

const node = doc.convert(tex, { display: !inline });
let svg = adaptor.innerHTML(node);

const EX = 8;
svg = svg.replace(/(width|height)="([\d.]+)ex"/g, (_, attr, val) =>
  `${attr}="${(parseFloat(val) * EX).toFixed(1)}px"`
);

const COLOR = process.env.MATH_COLOR || '#E5484D';
svg = svg.replace(/currentColor/g, COLOR);

if (!svg.includes('xmlns=')) {
  svg = svg.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
}

const err = svg.match(/data-mjx-error="([^"]+)"/);
if (err) {
  console.error('TeX error: ' + err[1]);
  process.exit(1);
}

process.stdout.write(svg);
