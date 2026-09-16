// tex2svg.js -- LaTeX -> standalone SVG, offline, via MathJax 3.
//
// Usage:  node tex2svg.js '<latex>' [--inline] > out.svg
//
// MathJax 3 is used instead of the older mathjax-node/mathjax-node-cli, which
// are abandoned and throw on Node >= 18. This runs on Node 22.
//
// The SVG that MathJax emits is sized in `ex` units, which assumes a surrounding
// text context. Confluence places the image in a block with no such context, so
// the ex dimensions are converted to px here (1ex ~ 8px at a 16px base) and
// written as explicit width/height. Without that, Confluence renders the math at
// an unpredictable size -- usually far too small to read.
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

// ex -> px so the image has a real, predictable size outside a text flow.
const EX = 8;
svg = svg.replace(/(width|height)="([\d.]+)ex"/g, (_, attr, val) =>
  `${attr}="${(parseFloat(val) * EX).toFixed(1)}px"`
);

// MathJax emits currentColor, which inherits from surrounding text -- but a
// data-URI <img> is a separate document, so there is nothing to inherit from and
// it resolves to black. Black is invisible on a dark background, and because the
// colour is baked into the image at render time it cannot respond to the page
// theme the way real text does. So pick one colour that clears both.
//
// #E5484D is a mid-tone red chosen for roughly balanced contrast on white and on
// Confluence's dark canvas (~4:1 either way). A darker red passes on white and
// fails on dark; a lighter one does the reverse. Override with MATH_COLOR.
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
