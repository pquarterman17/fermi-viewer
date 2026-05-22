function build_icons()
%BUILD_ICONS  Re-fetch the FermiViewer toolbar icons from Lucide.
%   The PNGs in this directory are rasterized from the Lucide icon set
%   (https://lucide.dev, MIT license) at 24x24 px in colour #333338.
%   They are fetched as SVG from the Iconify API and rasterized by a
%   small Node script — there is no native MATLAB SVG renderer.
%
%   Run only when the icon set changes (different icon, different size,
%   different colour). The PNGs are checked into git so a fresh clone
%   does not need Node installed.
%
%   Requires:
%       Node.js >= 18  (uses global fetch)
%       npm  install @resvg/resvg-js  (pure-Rust SVG renderer, no Cairo)
%
%   Icons produced (filename <- lucide name):
%       rot_cw.png       <- rotate-cw
%       rot_ccw.png      <- rotate-ccw
%       flip_h.png       <- flip-horizontal
%       flip_v.png       <- flip-vertical
%       zoom.png         <- zoom-in
%       fit.png          <- maximize
%       reset_all.png    <- refresh-cw
%       crop.png         <- crop
%       del_annot.png    <- circle-x
%
%   Run:  run icons/fermiviewer/build_icons

outDir = fileparts(mfilename('fullpath'));

[status, ~] = system('node --version');
if status ~= 0
    error('build_icons:noNode', ...
        ['Node.js was not found on PATH. Install Node 18+ from https://nodejs.org\n' ...
         'then rerun build_icons. The PNGs are checked into git, so this is\n' ...
         'only required when changing icon source/colour/size.']);
end

% Stage the rasterizer script in a temp dir so we do not pollute the repo
% with node_modules. Reuse the dir across runs to avoid re-downloading.
tmpDir = fullfile(tempdir, 'lucide-render');
if ~isfolder(tmpDir)
    mkdir(tmpDir);
end
scriptPath = fullfile(tmpDir, 'render.mjs');
fid = fopen(scriptPath, 'w');
fprintf(fid, '%s', renderScript());
fclose(fid);

if ispc
    cdPrefix = sprintf('cd /d "%s" && ', tmpDir);
    devNull  = 'nul';
else
    cdPrefix = sprintf('cd "%s" && ', tmpDir);
    devNull  = '/dev/null';
end

if ~isfolder(fullfile(tmpDir, 'node_modules', '@resvg', 'resvg-js'))
    fprintf('Installing @resvg/resvg-js into %s ...\n', tmpDir);
    cmd = [cdPrefix sprintf('npm init -y >%s && npm install --no-audit --no-fund --silent @resvg/resvg-js', devNull)];
    [status, out] = system(cmd);
    if status ~= 0
        error('build_icons:npmInstall', 'npm install failed:\n%s', out);
    end
end

cmd = [cdPrefix sprintf('node render.mjs "%s"', strrep(outDir, '\', '/'))];
[status, out] = system(cmd);
if status ~= 0
    error('build_icons:render', 'render.mjs failed:\n%s', out);
end
disp(out);
end

% ────────────────────────────────────────────────────────────────────────
function s = renderScript()
%RENDERSCRIPT  Inline ESM Node script that fetches Lucide SVGs from
%   Iconify and rasterizes them via @resvg/resvg-js.
lines = {
    "import { Resvg } from '@resvg/resvg-js';"
    "import fs from 'node:fs';"
    "import path from 'node:path';"
    ""
    "const outDir = process.argv[2];"
    "if (!outDir) { console.error('usage: node render.mjs <outDir>'); process.exit(1); }"
    ""
    "const color = '#333338';"
    "const sizePx = 24;"
    ""
    "const icons = ["
    "  ['rotate-cw',       'rot_cw.png'],"
    "  ['rotate-ccw',      'rot_ccw.png'],"
    "  ['flip-horizontal', 'flip_h.png'],"
    "  ['flip-vertical',   'flip_v.png'],"
    "  ['zoom-in',         'zoom.png'],"
    "  ['maximize',        'fit.png'],"
    "  ['refresh-cw',      'reset_all.png'],"
    "  ['crop',            'crop.png'],"
    "  ['circle-x',        'del_annot.png'],"
    "];"
    ""
    "for (const [iconName, filename] of icons) {"
    "  const url = `https://api.iconify.design/lucide/${iconName}.svg?color=${encodeURIComponent(color)}`;"
    "  const res = await fetch(url);"
    "  if (!res.ok) { console.error(`fetch failed for ${iconName}: ${res.status}`); process.exit(2); }"
    "  const svg = await res.text();"
    "  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: sizePx }, background: 'rgba(0,0,0,0)' });"
    "  const pngBuffer = resvg.render().asPng();"
    "  fs.writeFileSync(path.join(outDir, filename), pngBuffer);"
    "  console.log(`  ${filename.padEnd(16)} <- lucide:${iconName}  (${pngBuffer.length} bytes)`);"
    "}"
    ""
    "console.log(`\nWrote ${icons.length} icons to ${outDir}`);"
    };
s = char(strjoin(string(lines), newline));
end
