function [labels, info] = segmentTrained(img, model, options)
%SEGMENTTRAINED  Grain segmentation by applying a trained pixel-classifier.
%
%   Syntax:
%       [labels, info] = imaging.grains.segmentTrained(img, model)
%       [labels, info] = imaging.grains.segmentTrained(img, model, BoundaryClass=3)
%
%   Companion to imaging.grains.trainFromScribbles. Classifies every pixel
%   with the trained softmax model, then (exactly as segmentAuto does) labels
%   spatially connected components WITHIN each predicted class so separate
%   grains of the same class become distinct grains.
%
%   The feature stack is rebuilt from the model's baked-in configuration
%   (model.scales / model.gradientSigma) so it matches what the classifier
%   was trained on — the image here may be a DIFFERENT image than the one the
%   model was trained on.
%
%   No external toolboxes required.
%
%   Inputs:
%       img            — [H x W] numeric grayscale image.
%       model          — model struct from imaging.grains.trainFromScribbles
%                        (must carry .scales / .gradientSigma).
%
%   Optional Name-Value:
%       Features       — [H x W x F] precomputed feature cube (default []:
%                        compute from model.scales). Lets the GUI reuse cache.
%       BoundaryClass  — class value(s) to treat as grain BOUNDARY / non-grain
%                        and exclude from grain labeling (default []). Use
%                        when a scribble class was painted on boundaries.
%       MinArea        — minimum grain area in pixels (default 25).
%       Connectivity   — 4 or 8 (default 8).
%
%   Outputs:
%       labels         — [H x W] grain label map (0 = boundary/dropped,
%                        1..numGrains otherwise).
%       info           — struct: .numGrains, .classMap [H x W] predicted
%                        class per pixel (model.classes values), .maxProb
%                        [H x W] winning-class probability (confidence),
%                        .classes (model.classes).
%
%   See also imaging.grains.trainFromScribbles, imaging.grains.segmentAuto,
%            imaging.ml.softmaxPredict

arguments
    img                  (:,:) {mustBeNumeric}
    model                (1,1) struct
    options.Features     double = []
    options.BoundaryClass double = []
    options.MinArea      (1,1) double {mustBeNonnegative, mustBeInteger} = 25
    options.Connectivity (1,1) double {mustBeMember(options.Connectivity, [4, 8])} = 8
end

if ~isfield(model, 'scales')
    error('segmentTrained:notGrainModel', ...
        ['model lacks .scales — it was not produced by ', ...
         'imaging.grains.trainFromScribbles.']);
end

% ── Features (matching the model's training configuration) ──────────────
if isempty(options.Features)
    feats = imaging.grains.extractGrainFeatures(img, ...
        Scales=model.scales, GradientSigma=model.gradientSigma);
else
    feats = double(options.Features);
end
[H, W, F] = size(feats);
X = reshape(feats, H * W, F);

% ── Per-pixel classification ────────────────────────────────────────────
[cls, probs] = imaging.ml.softmaxPredict(model, X);
classMap = reshape(cls, H, W);
maxProb  = reshape(max(probs, [], 2), H, W);

% ── Connected components within each grain class → individual grains ────
labels = zeros(H, W);
g = 0;
for c = model.classes
    if ismember(c, options.BoundaryClass)
        continue;   % this class is boundary / non-grain
    end
    mask = (classMap == c);
    if ~any(mask(:))
        continue;
    end
    [Lc, nc] = imaging.connectedComponents(mask, Connectivity=options.Connectivity);
    for j = 1:nc
        comp = (Lc == j);
        if sum(comp(:)) >= options.MinArea
            g = g + 1;
            labels(comp) = g;
        end
    end
end

info = struct( ...
    'numGrains', g, ...
    'classMap',  classMap, ...
    'maxProb',   maxProb, ...
    'classes',   model.classes);
end
